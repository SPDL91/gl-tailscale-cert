# Changelog

## Unreleased

## 0.1.9 - 2026-08-22

- Report the actual feature state after installing. The installer always said the feature starts disabled, which misread an install over a preserved `enabled='1'` config, such as after a firmware upgrade.
- Simplify WebUI placement by relying on its existing DOM observer instead of three delayed retries and periodic reinsertion.
- Remove the unused panel collapse control, custom update event, RPC fields, worker metadata, helper, and literal-only dispatcher test.
- Keep the live-device checklist while removing recorded acceptance-session results already preserved in repository history.

## 0.1.8 - 2026-08-15

- Fix a v0.1.7 packaging defect that made installation fail on the router. The lifecycle `postinst` and `prerm` shipped with CRLF line endings, so BusyBox looked for an interpreter named `sh\r`, and `opkg install` reported "not found" and exit 127 for a script that existed and was executable. Found on a GL-MT3000 during live acceptance.
- Pin `src/lifecycle/*`, `src/config/*`, and `src/nginx/*` to LF. Only some extensionless packaged files carried an explicit line-ending rule, so the rest inherited `text=auto` and picked up CRLF from a Windows checkout.
- Reject a carriage return anywhere in any packaged file, rather than only in the hotplug hook, and check the shebang of every packaged script.

## 0.1.7 - 2026-08-15

- Fix the file watcher missing a certificate overwrite that lands while its one-shot check finishes. The daemon sampled the four files after the check completed, so an overwrite arriving in that window became the baseline and the watcher waited a full 12-hour interval instead of repairing within 30 seconds.
- Sample before the check runs instead. A change the check makes itself costs one extra pass, which finds every file valid and returns without a certificate request or a service reload.
- Raise the watchdog test's timing ceilings and name them, so a loaded CI runner no longer reports a false failure.

## 0.1.6 - 2026-08-14

- Replace the unavailable `cksum` watcher command with `sha256sum` and an OpenSSL SHA-256 fallback after live GL-MT3000 firmware testing exposed the compatibility gap.
- Add a regression that makes any future watcher use of `cksum` fail explicitly.
- Allow the delayed hotplug debounce test enough scheduling time to avoid a misleading tag-build failure under a busy container runner.
- Complete live watcher acceptance on GL-MT3000 firmware 4.8.1: controlled nginx certificate replacement repaired in 21 seconds without a certificate request or internet/DNS interruption.

## 0.1.5 - 2026-08-14

- Add a 30-second in-memory certificate-file watcher because GL-MT3000 firmware 4.8.1 does not emit an `iface` hotplug event after a DHCP lease-time change.
- Run the existing validated one-shot path only when a certificate or key file changes; keep the normal 12-hour validation interval and hotplug fast path.
- Add a daemon regression test proving external nginx certificate replacement repairs from uHTTPd without a certificate request.
- Enforce LF line endings for the extensionless BusyBox hotplug script and verify its packaged shebang bytes.

## 0.1.4 - 2026-08-14

- Add a package-owned, debounced LAN interface recovery hook for GL firmware that overwrites nginx certificates after LAN settings changes.
- Keep the hook fail-open and asynchronous; reuse the existing feature gate, worker lock, validation, no-request repair, and rollback paths.
- Preserve the hook through sysupgrade and add BusyBox, package-content, event-filtering, debounce, and failure-cleanup tests.
- Simplify WebUI guidance and status text under the project interface-content rules.
- Update technical documentation and live acceptance steps for both verified router models and the observed GL certificate-regeneration path.

## 0.1.3 - 2026-08-13

- Restart uHTTPd after certificate activation and rollback because GL-MT3000 firmware 4.8.1 reports reload success without replacing the certificate served by its TLS listener.
- Add regression coverage that rejects uHTTPd reload as an activation mechanism.

## 0.1.2 - 2026-08-13

- Avoid unsupported BusyBox `tr` character classes that corrupted lowercase `u` to `l` during FQDN normalization.
- Add a BusyBox regression hostname containing `u` and preserve Tailscale's canonical lowercase name byte-for-byte.

## 0.1.1 - 2026-08-13

- Require a firmware-trusted CA chain for every reused, requested, repaired, or activated certificate.
- Reject hostname-valid self-signed GL certificates instead of propagating them across web servers.
- Add the explicit `ca-bundle` runtime dependency and regression coverage.

## 0.1.0 - 2026-08-13

- Initial standalone opt-in certificate worker and procd service.
- Validated cross-server repair, renewal, activation, and full rollback.
- Self-preserving sysupgrade list and metadata-loss/force-reinstall lifecycle.
- Independent OUI RPC and GL Tailscale WebUI panel.
- Exact-location Lua dispatcher compatible with the gl-tailscale-fix v1.0.21 filter contract.
- OpenWrt source-package Makefile plus review IPK and apk-tools v3 builders.
- Backend, lifecycle, package, dispatcher, OpenResty, and headless-browser tests.
