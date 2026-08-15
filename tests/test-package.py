#!/usr/bin/env python3
"""Inspect the built IPK and source tree for packaging and scope invariants."""

from io import BytesIO
from pathlib import Path
import re
import tarfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
IPK = ROOT / "build/out/gl-tailscale-cert_0.1.8_all.ipk"


def nested_tar(outer, name):
    member = outer.getmember(name)
    return tarfile.open(fileobj=BytesIO(outer.extractfile(member).read()), mode="r:gz")


class PackageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not IPK.exists():
            raise unittest.SkipTest(f"build first: {IPK}")
        cls.outer = tarfile.open(IPK, mode="r:gz")
        cls.data = nested_tar(cls.outer, "./data.tar.gz")
        cls.control = nested_tar(cls.outer, "./control.tar.gz")
        cls.members = {member.name.lstrip("./"): member for member in cls.data.getmembers() if member.isfile()}

    def test_required_package_files(self):
        expected = {
            "etc/init.d/gl-tailscale-cert",
            "etc/hotplug.d/iface/90-gl-tailscale-cert",
            "usr/bin/gl-tailscale-cert",
            "usr/lib/oui-httpd/rpc/ts-cert",
            "usr/libexec/gl-tailscale-cert/postinst",
            "usr/libexec/gl-tailscale-cert/prerm",
            "usr/share/gl-tailscale-cert/defaults/ts_cert",
            "usr/share/gl-tailscale-cert/nginx/ts-cert.conf",
            "usr/share/gl-tailscale-cert/ui-header-filter.lua",
            "usr/share/gl-tailscale-cert/ui-dispatch-filter.lua",
            "usr/share/gl-tailscale-cert/www/ts-cert.js",
            "usr/share/gl-tailscale-cert/www/ts-cert.js.gz",
            "lib/upgrade/keep.d/gl-tailscale-cert",
        }
        self.assertEqual(set(self.members), expected)

    def test_file_modes(self):
        executable = {
            "etc/init.d/gl-tailscale-cert",
            "etc/hotplug.d/iface/90-gl-tailscale-cert",
            "usr/bin/gl-tailscale-cert",
            "usr/libexec/gl-tailscale-cert/postinst",
            "usr/libexec/gl-tailscale-cert/prerm",
        }
        for name, member in self.members.items():
            expected = 0o755 if name in executable else (0o600 if name.endswith("defaults/ts_cert") else 0o644)
            self.assertEqual(member.mode & 0o777, expected, name)
            self.assertEqual(member.uid, 0, name)
            self.assertEqual(member.gid, 0, name)

    def test_control_metadata_and_hooks(self):
        control_text = self.control.extractfile("./control").read().decode()
        self.assertIn("Package: gl-tailscale-cert", control_text)
        self.assertIn("Version: 0.1.8", control_text)
        self.assertIn("ca-bundle", control_text)
        self.assertIn("Architecture: all", control_text)
        self.assertIn("License: GPL-3.0-only", control_text)
        for hook in ("./postinst", "./prerm"):
            member = self.control.getmember(hook)
            self.assertEqual(member.mode & 0o777, 0o755)

    def test_no_live_secrets_or_certificate_payloads(self):
        forbidden_names = re.compile(r"(^|/)(nginx\.cer|nginx\.key|uhttpd\.crt|uhttpd\.key|cert\.pem|key\.pem)$")
        for name, member in self.members.items():
            self.assertIsNone(forbidden_names.search(name), name)
            payload = self.data.extractfile(member).read()
            self.assertNotIn(b"BEGIN PRIVATE KEY", payload, name)
            self.assertNotIn(b"tskey-", payload, name)
            # Catch any real tailnet name generically. Naming a specific one here
            # would publish it, which is the leak this test exists to prevent.
            self.assertNotRegex(payload.decode("utf-8", "replace"), r"\b[a-z0-9-]+\.ts\.net\b", name)

    def test_routing_and_foreign_plugin_scope_is_untouched(self):
        worker = self.data.extractfile(self.members["usr/bin/gl-tailscale-cert"]).read().decode()
        for forbidden in (
            "/usr/bin/gl_tailscale",
            "tailscale up",
            "tailscale set",
            "tailscale down",
            "firewall.",
            "network.",
            "ip rule",
            "ip route",
        ):
            self.assertNotIn(forbidden, worker)
        keep = self.data.extractfile(self.members["lib/upgrade/keep.d/gl-tailscale-cert"]).read().decode()
        self.assertNotIn("ts-fix", keep)
        self.assertNotIn("tailscaled", keep)

    def test_nginx_uses_native_graceful_reload(self):
        worker = self.data.extractfile(self.members["usr/bin/gl-tailscale-cert"]).read().decode()
        postinst = self.data.extractfile(self.members["usr/libexec/gl-tailscale-cert/postinst"]).read().decode()
        prerm = self.data.extractfile(self.members["usr/libexec/gl-tailscale-cert/prerm"]).read().decode()
        self.assertIn('"$NGINX" -s reload', worker)
        self.assertIn('"$NGINX" -s reload', postinst)
        self.assertIn('"$NGINX" -s reload', prerm)

    def test_no_packaged_file_carries_carriage_returns(self):
        """A CR anywhere in a packaged text file is a shipping defect.

        BusyBox resolves `#!/bin/sh\\r` as an interpreter named `sh\\r`, so the
        script fails with "not found" and exit 127 even though it exists and is
        executable. A previous release shipped that way because this check
        covered only the hotplug hook while `.gitattributes` left other
        extensionless files on `text=auto`.
        """
        for name, member in self.members.items():
            if name.endswith(".gz"):
                continue
            payload = self.data.extractfile(member).read()
            self.assertNotIn(b"\r", payload, f"{name} contains a carriage return")

    def test_packaged_scripts_start_with_a_busybox_shebang(self):
        # The init script legitimately dispatches through rc.common, so match the
        # interpreter rather than the whole line, and require the line to end
        # cleanly: a trailing CR here is what BusyBox reports as "not found".
        for name in (
            "etc/init.d/gl-tailscale-cert",
            "etc/hotplug.d/iface/90-gl-tailscale-cert",
            "usr/bin/gl-tailscale-cert",
            "usr/libexec/gl-tailscale-cert/postinst",
            "usr/libexec/gl-tailscale-cert/prerm",
        ):
            first_line = self.data.extractfile(self.members[name]).read().split(b"\n", 1)[0]
            self.assertTrue(first_line.startswith(b"#!/bin/sh"), f"{name}: {first_line!r}")
            self.assertFalse(first_line.endswith(b"\r"), f"{name} shebang ends with CR")

    def test_hotplug_hook_stays_in_scope(self):
        hook = self.data.extractfile(self.members["etc/hotplug.d/iface/90-gl-tailscale-cert"]).read().decode()
        for forbidden in ("firewall", "ip route", "ip rule", "ubus call network"):
            self.assertNotIn(forbidden, hook)

    def test_packaged_defaults_ship_opt_in_and_watch_interval(self):
        defaults = self.data.extractfile(self.members["usr/share/gl-tailscale-cert/defaults/ts_cert"]).read().decode()
        self.assertIn("option enabled '0'", defaults)
        self.assertIn("option watch_interval '30'", defaults)

    def test_independent_runtime_namespaces(self):
        ui = self.data.extractfile(self.members["usr/share/gl-tailscale-cert/www/ts-cert.js"]).read().decode()
        self.assertIn("params: [token, 'ts-cert'", ui)
        self.assertNotIn("params: [token, 'ts-fix'", ui)
        self.assertNotIn("localStorage.setItem('theme'", ui)
        rpc = self.data.extractfile(self.members["usr/lib/oui-httpd/rpc/ts-cert"]).read().decode()
        self.assertIn('local CONFIG = "ts_cert"', rpc)
        self.assertNotIn('require "ts-fix"', rpc)

    def test_version_placeholders_are_resolved(self):
        for name in (
            "usr/bin/gl-tailscale-cert",
            "usr/share/gl-tailscale-cert/ui-dispatch-filter.lua",
            "usr/share/gl-tailscale-cert/www/ts-cert.js",
        ):
            payload = self.data.extractfile(self.members[name]).read()
            self.assertNotIn(b"{{VERSION}}", payload, name)
            self.assertIn(b"0.1.8", payload, name)


if __name__ == "__main__":
    unittest.main(verbosity=2)
