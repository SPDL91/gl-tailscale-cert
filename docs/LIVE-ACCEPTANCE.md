# Live-device acceptance checklist

Do not run this checklist without explicit approval for the specific router and package artifact.

## Recorded v0.1.8 results

### GL-MT3000, firmware 4.9.1-op25 (OpenWrt 25.12)

OpenWrt 25.12.5, kernel 6.12.94, apk-tools 3.0.5. The device reached this state
by a firmware upgrade from OpenWrt 21.02 with **Keep Settings**, which also
exercises sysupgrade persistence and package-metadata loss.

- Every path in the keep list survived the upgrade: worker, procd script and its
  `S99` link, UCI config, generated nginx adapter, RPC, and the keep list
  itself. All four certificate files stayed byte-identical.
- The package kept working with no package-manager record of it. The daemon ran,
  reported `valid`, and `nginx -t` passed, because apk did not inherit the opkg
  database.
- The installer selected the `.apk` artifact, verified its checksum, and
  installed with apk. The post-install script ran without error, apk then listed
  the package, and the preserved `enabled=1` was not overwritten.
- A controlled invalid replacement of the nginx pair repaired in 24 seconds from
  the valid uHTTPd pair, with no certificate request. Modes stayed `0644` and
  `0600`.
- With `gl-tailscale-fix` present, `/gl_home.html` carried each script exactly
  once, ts-fix first, and `--status --json` returned a well-formed object.

This covers the apk-tools and sysupgrade items that earlier releases could not
verify.

### GL-MT6000, firmware 4.9.1

OpenWrt 21.02-SNAPSHOT, Tailscale 1.102.2, with `gl-tailscale-fix` 1.0.21 and
AdGuard Home installed alongside.

- Upgraded from v0.1.6 through the one-line installer with no error. All four
  certificate files stayed byte-identical, so the upgrade made no certificate
  request. No packaged script contained a carriage return.
- A controlled invalid replacement of the on-disk nginx certificate and key
  repaired in 12 seconds from the valid uHTTPd pair. `last_renewal` did not
  move, so no certificate request occurred. Certificate mode stayed `0644` and
  key mode `0600`.
- DNS resolution was sampled every two seconds through the repair window with
  no failures, and an independent internet probe passed afterwards.
- After repair, `nginx -t` passed and both the nginx listener on 443 and
  AdGuard's DNS-over-TLS listener on 853 served the expected certificate.
- With `gl-tailscale-fix` present, `/gl_home.html` carried each script exactly
  once, with the ts-fix asset ahead of the ts-cert asset.

AdGuard Home reads `/etc/nginx/nginx.cer` and `/etc/nginx/nginx.key` directly
for DNS-over-TLS on this device, so it consumes the same files this package
manages. AdGuard 0.107.72 and later watch those files and reload after a
change, so a renewal reaches the DNS-over-TLS listener without help. Earlier
versions load the certificate once at startup and keep serving the previous one
until they restart. The device carried 0.107.73.

### GL-MT3000, firmware 4.8.1

OpenWrt 21.02-SNAPSHOT, with `gl-tailscale-fix` 1.0.21 installed alongside.

- The one-line installer resolved the release, verified its SHA-256, and
  upgraded the package with no error. All four certificate files stayed
  byte-identical, so the upgrade made no certificate request.
- A controlled invalid replacement of the on-disk nginx certificate and key
  repaired in 34 seconds, consistent with the 30-second watch interval. The
  worker reused the valid uHTTPd pair; `last_renewal` did not move, so no
  certificate request occurred.
- After repair, `nginx -t` passed and the TLS listener served the expected
  Let's Encrypt certificate for the router's Tailscale name.
- A reboot brought the procd service back through its `S99` link, reached
  `valid`, left all four files byte-identical, and made no certificate request.
- All four package transaction orders passed, with `nginx -t` clean after each:

  | Transaction | Result |
  |---|---|
  | Remove this package, keep ts-fix | Certificate files left in place, ts-fix files untouched, only the ts-fix script injected |
  | Reinstall it with ts-fix present | Saved config restored, both scripts injected once, ts-fix first |
  | Remove ts-fix, keep this package | This package unaffected, only its own script injected, its asset still served |
  | Reinstall ts-fix over this package | Both scripts injected once, ts-fix first |

  `last_renewal` stayed at zero throughout, so no transaction triggered a
  certificate request. Download the ts-fix package and verify its checksum
  before removing it, so reinstalling does not depend on network access later.

v0.1.7 failed acceptance on the MT3000 and was withdrawn: its lifecycle scripts
shipped with CRLF endings, so `opkg install` reported the postinst as "not
found" with exit 127. See the 0.1.8 entry in `CHANGELOG.md`.

Reboot and package-order checks ran on the MT3000 under OpenWrt 21.02. The
sysupgrade and apk-tools items were covered by the 25.12 upgrade recorded above.
Package-order checks have not been repeated under apk.

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
