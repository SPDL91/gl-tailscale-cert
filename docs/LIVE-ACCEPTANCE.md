# Live-device acceptance checklist

Do not run this checklist without explicit approval for the specific router and package artifact.

## Before installation

1. Review the package checksum, exact contents, `postinst`, `prerm`, worker, RPC, and generated nginx template.
2. Record firmware, OpenWrt base, package manager, Tailscale version, `nginx -T`, `nginx -t`, and the current certificate fingerprints and expiry without copying private keys.
3. Take the normal GL.iNet or LuCI settings backup appropriate to the current firmware.
4. Confirm that the operator understands MagicDNS, Tailscale HTTPS Certificates, and Certificate Transparency publication.

## Disabled install

1. Install the reviewed artifact without enabling the feature.
2. Confirm `ts_cert.main.enabled=0`.
3. Confirm no `tailscale cert` request occurred and all four live certificate hashes remain unchanged.
4. Confirm the procd service runs and reports `disabled`.
5. Run `nginx -t`, then confirm the native and optional ts-fix controls work.
6. Confirm the new panel appears in the intended order and shows the package version.

## First enabled run

1. Enable the feature through its toggle.
2. Observe bounded status polling; do not repeat the renewal request.
3. Confirm the discovered FQDN equals `Self.DNSName` without recording it in public artifacts.
4. Confirm CA-chain, hostname, certificate/key validation, and matching hashes across nginx and uHTTPd targets.
5. Confirm nginx and uHTTPd present the expected certificate over their existing listener bindings.
6. Confirm Tailscale, WAN, firewall, routes, DNS, native Apply behavior, and monitoring remain healthy.

## Recovery and coexistence

1. Save a harmless LAN setting, such as the existing DHCP lease time, and confirm the GL fallback certificate appears before the network reload.
2. Confirm either the LAN hook or daemon watcher repairs both web interfaces within 45 seconds without a forced certificate request when one valid pair remains.
3. Confirm WAN, routing, DNS, and an independent internet probe remain healthy. A brief Admin Panel or LuCI interruption remains acceptable.
4. Reboot once and confirm immediate repair or no-op behavior.
5. Test both plugin upgrade orders and both removal orders with `nginx -t` after each transaction.
6. Confirm each expected script appears exactly once in `/gl_home.html` and both panels recover after navigation or a hard refresh.
7. Confirm removing this package leaves the last valid certificate files and ts-fix or native UI working.
8. Confirm removing ts-fix leaves this package and the native UI working.

## Firmware persistence

Do not flash firmware solely for this package test. If a normal, separately approved firmware upgrade already has approval:

1. Confirm `sysupgrade -l` includes every line in the package keep list, including the keep list and service links.
2. Use **Keep Settings**.
3. Confirm files survive even if package metadata does not.
4. Confirm the boot service repairs regenerated web certificates.
5. Reinstall the same package to recover metadata and confirm UCI settings remain unchanged.
