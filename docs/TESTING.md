# Testing

## Local suites

The repository test entry point runs backend, LAN-recovery, lifecycle, and IPK-content tests:

```sh
sh tests/run.sh
```

The backend tests use an isolated fake router root, a throwaway test CA, and generated certificates for `router.test-tail.ts.net`. The `u` in that name is a regression guard for GL BusyBox `tr` incompatibility. Tests also prove that a hostname-valid self-signed certificate is rejected and that the daemon watcher repairs externally replaced nginx files from uHTTPd without a certificate request. No public certificate request or router connection occurs.

The LAN-recovery test verifies interface/action filtering, a normal non-forced one-shot, duplicate-event debouncing, background execution, and fail-open cleanup after a worker error.

BusyBox compatibility is checked in Alpine:

```sh
docker run --rm --entrypoint /bin/ash \
  -v "$PWD:/repo:ro" alpine:edge \
  -c 'apk add --no-cache openssl >/dev/null && cd /repo && \
      /bin/ash -n src/scripts/gl-tailscale-cert && \
      /bin/ash -n src/hotplug/iface/90-gl-tailscale-cert && \
      /bin/ash tests/test-backend.sh && /bin/ash tests/test-hotplug.sh && \
      /bin/ash tests/test-lifecycle.sh'
```

## Browser test

`tests/test-webui.js` uses Playwright Chromium with a mocked GL `/rpc` endpoint. It verifies:

- standalone placement after native `ul.tailscale-config`;
- relocation immediately after `#ts-fix-section` when it appears later;
- the `ts-cert` RPC envelope and no `ts-fix` RPC call;
- unique IDs/styles;
- dark theme synchronization;
- idempotent restoration after a Vue-style DOM replacement.

## OpenResty test

`tests/test-openresty.sh` is executed in the official OpenResty Alpine image. It runs `nginx -t`, serves `/gl_home.html`, and counts injected scripts in these states:

| State | Expected ts-fix | Expected ts-cert |
|---|---:|---:|
| Native only | 0 | 0 |
| Certificate plugin only | 0 | 1 |
| ts-fix only | 1 | 0 |
| Both | 1 | 1 |

The compatibility fixture preserves the v1.0.21/current-main filter behavior from upstream commit `d86da698e17ece6b52ba1789ee27b02f7313692f`.

## Lifecycle order coverage

The tests cover the resulting end states, not the package transactions that produce them:

- certificate package installed before or after ts-fix (same validated combined nginx state);
- normal package upgrade (active files remain for takeover);
- force-reinstall (config saved, teardown, then restored);
- package metadata missing with preserved config/files;
- certificate package removed while ts-fix remains;
- ts-fix absent after certificate removal (native-only config);
- both removal outcomes through the four OpenResty states.

Real `opkg`/apk transaction ordering and GL's nginx manager remain live acceptance items.

## Package validation

The review builders create IPK and APK files with SHA-256 sidecars under ignored `build/out/`. Tests assert the exact IPK payload, root ownership, modes, maintainer hooks, no live cert/key, no private key or auth-key marker, independent namespaces, and absence of routing/firewall commands. CI verifies the APK with apk-tools v3 `apk verify --allow-untrusted`; `apk adbdump` remains a manual inspection step.
