# Live-device acceptance checklist

Do not run this checklist without explicit approval for the specific router and package artifact.

## Pending v0.1.7 acceptance

v0.1.7 changes when the daemon samples the certificate files. Re-run the
recovery and coexistence checks below on a router before treating the watcher
timing as verified; the v0.1.6 results that follow predate that change.

## Recorded v0.1.6 results

- GL-MT3000 firmware 4.8.1 detected and repaired a controlled invalid replacement of the on-disk nginx certificate in 21 seconds. The worker reused the valid uHTTPd pair without a certificate request. Internet, DNS, nginx validation, and both HTTPS listeners remained healthy.
- GL-MT3000 firmware 4.8.1 and GL-MT6000 firmware 4.9.1 upgraded from v0.1.5 to v0.1.6 without a reboot or certificate request. Internet and DNS remained healthy. Each WebUI script appeared once with `gl-tailscale-fix` installed.
- On GL-MT6000, nginx, LuCI, AdGuard HTTPS, and DNS-over-TLS continued to serve the same certificate after the upgrade.

The reboot, sysupgrade, live apk-tools, and destructive package-order checks below remain pending. Do not perform them without separate approval.

## Before installation

1. Review the package checksum, exact contents, `postinst`, `prerm`, worker, RPC, and generated nginx template.
2. Record firmware, OpenWrt base, package manager, Tailscale version, `nginx -T`, `nginx -t`, and the current certificate fingerprints/expiry without copying private keys.
3. Take the normal GL/LuCI settings backup appropriate to the current firmware.
4. Confirm MagicDNS and Tailscale HTTPS Certificates are understood, including Certificate Transparency publication.

## Disabled install

1. Install the reviewed artifact; do not enable the feature.
2. Confirm `ts_cert.main.enabled=0`.
3. Confirm no `tailscale cert` request occurred and all four live certificate hashes are unchanged.
4. Confirm the procd service is enabled/running and its status is `disabled`.
5. Run `nginx -t` and confirm both native and optional ts-fix controls work.
6. Confirm the new panel appears in the intended order and clearly shows the package version.

## First enabled run

1. Enable through the independent toggle.
2. Observe bounded status polling; do not repeat the renewal button.
3. Confirm the discovered FQDN equals `Self.DNSName` without recording it in public artifacts.
4. Confirm CA-chain, hostname, certificate/key validation, and matching hashes across nginx/uHTTPd targets.
5. Confirm nginx and uHTTPd present the expected certificate over their existing listener bindings.
6. Confirm Tailscale, WAN, firewall, routes, DNS, native Apply behavior, and monitoring remain healthy.

## Recovery and coexistence

1. Save a harmless LAN setting, such as the existing DHCP lease time, and confirm the GL fallback certificate appears before the network reload.
2. Confirm either the LAN hook or the daemon watcher repairs both web interfaces within 45 seconds, without a forced certificate request when one valid pair remains.
3. Confirm WAN, routing, DNS, and an independent internet probe stay healthy; a brief Admin Panel or LuCI interruption remains acceptable.
4. Reboot once and confirm immediate repair/no-op behavior.
5. Test both plugin upgrade orders and both removal orders with `nginx -t` after each transaction.
6. Confirm each expected script appears exactly once in `/gl_home.html` and both panels recover after navigation/hard refresh.
7. Confirm removing this package leaves the last valid certificate files and ts-fix/native UI working.
8. Confirm removing ts-fix leaves this package/native UI working.

## Firmware persistence

Do not flash firmware solely for this package test. If a normal, separately approved firmware upgrade is already planned:

1. confirm `sysupgrade -l` includes every line in the package keep list, including the keep list itself and service links;
2. use **Keep Settings**;
3. confirm files survive even if package metadata does not;
4. confirm the boot service repairs regenerated web certificates;
5. reinstall the same package to recover metadata and confirm UCI settings remain unchanged.
