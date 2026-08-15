# Architecture

## Ownership boundaries

| Concern | Owned path or namespace |
|---|---|
| Package | `gl-tailscale-cert` |
| UCI | `/etc/config/ts_cert` |
| LAN recovery trigger | `/etc/hotplug.d/iface/90-gl-tailscale-cert` |
| procd | `/etc/init.d/gl-tailscale-cert` |
| Worker | `/usr/bin/gl-tailscale-cert` |
| RPC | `/usr/lib/oui-httpd/rpc/ts-cert` |
| Generated nginx adapter | `/etc/nginx/gl-conf.d/ts-cert.conf` |
| Assets | `/usr/share/gl-tailscale-cert/`, `/ts-cert/` |
| DOM/CSS/storage/events | `ts-cert-*` |
| Volatile state | `/tmp/gl-tailscale-cert.*` |
| Persistence | `/lib/upgrade/keep.d/gl-tailscale-cert` |

The only foreign paths read by the UI adapter are the documented optional `gl-tailscale-fix` header/body filter files and `#ts-fix-section` placement anchor. They are never written, deleted, or called through RPC.

## Process model

procd owns one long-running `--daemon` process. The daemon launches a one-shot child immediately when enabled, waits for it, re-reads UCI, and sleeps for the configured interval. When disabled it updates volatile status and wakes every five minutes so direct UCI changes eventually take effect even if GL firmware emits no reload trigger.

Each one-shot owns an atomic `/tmp` lock. A live PID makes a second run exit with code 75. A missing or dead PID permits bounded stale-lock recovery. procd restart and UI renew requests therefore cannot overlap.

GL firmware can replace nginx's certificate while saving LAN settings. The package's interface hotplug hook reacts only to LAN `ifup` and `ifupdate`, then launches a delayed one-shot in the background. A `/tmp` marker collapses duplicate events before the worker lock handles process overlap. The hook always exits successfully so recovery errors cannot block the network event.

GL-MT3000 firmware 4.8.1 did not emit an interface event after a live DHCP lease-time change. The daemon therefore retains SHA-256 digests of the four certificate/key files in memory and compares them every 30 seconds while enabled. It uses the firmware `sha256sum` tool when available and falls back to OpenSSL SHA-256. A byte change ends the current sleep and schedules the normal one-shot validation path. Unchanged files cause no status write, certificate validation, Tailscale call, or service reload. The normal 12-hour interval still provides full validation when no file changes occur.

## Request minimization

The normal path validates nginx first, then uHTTPd, against the discovered FQDN and configured minimum remaining validity. A suitable pair becomes the repair source. Only when neither pair is suitable does the worker invoke `tailscale cert`.

FQDN discovery requires two consecutive identical, valid `Self.DNSName` samples. Certificate acceptance is anchored in the firmware CA bundle with `openssl verify -verify_hostname`, using the Tailscale fullchain as the untrusted intermediate set. This rejects GL-generated self-signed certificates and avoids OpenSSL 1.1.1t's unreliable `x509 -checkhost` process exit status.

A forced run is available only for an explicit user renewal and still requires the UCI feature gate. It does not bypass validation, locking, staging, or rollback.

## Activation and rollback

All existing target files are copied into the private RAM work directory with their modes. Four adjacent staged files are populated before any rename. After renames and `sync`, activation is ordered:

1. `nginx -t`;
2. native `nginx -s reload` (graceful HUP; GL's init script has no reload implementation);
3. uHTTPd restart. GL 4.8.1 on the MT3000 returns success from reload without replacing the in-memory TLS certificate, so reload is not a reliable activation primitive.

Any failure restores all four prior states, including prior nonexistence, then attempts to reactivate the restored configuration. Status records `rollback`; the error does not alter network routing.

## Dispatcher rationale

Lua body filters do not form an automatic plugin chain when multiple packages place the same directive in the server context. The certificate package instead uses an exact SPA location with one location-level pair. This overrides an inherited server pair for `/gl_home.html`, then explicitly dispatches the known optional pair.

The body dispatcher buffers only through `</head>` with a 256 KiB limit. It invokes the optional filter on the combined head, checks for the expected asset, adds its own versioned asset if absent, and streams later chunks unchanged. Missing or oversized head markup is returned unchanged. This design handles chunk splits, preserves order, and bounds memory.

The generated adapter is lifecycle-managed rather than an archived `/etc` file. Post-install can therefore validate it and restore/remove it before nginx ever reloads. Removal can delete the active adapter before the package manager removes its Lua assets.

## WebUI panel

The panel uses only its own `ts-cert-*` IDs, classes, events, and storage keys, the `ts-cert` RPC module, `ts_cert` UCI, and package-owned timers. It never intercepts GL's native **Apply** control. It renders after `#ts-fix-section` when that anchor exists, otherwise after `ul.tailscale-config`, and a `MutationObserver` restores that placement after Vue re-renders.

The WebUI toggle commits only `ts_cert.main.enabled` and restarts only `/etc/init.d/gl-tailscale-cert`.

## Lifecycle

Install and reinstall:

- create UCI defaults only when `/etc/config/ts_cert` does not exist;
- restore configuration saved across a force-reinstall;
- repair missing procd service symlinks;
- validate the generated nginx adapter before `nginx -s reload`, and restore the previous adapter when validation fails;
- start the daemon without requesting a certificate while the feature stays disabled.

Removal stops and disables the service, deletes the generated adapter and package configuration, and reloads nginx only after `nginx -t`. It intentionally leaves the last live certificate and key files in place.

`/lib/upgrade/keep.d/gl-tailscale-cert` preserves this package's configuration and functional files through `sysupgrade` with **Keep Settings**, including the keep list itself and the procd symlinks. It preserves no package databases, Tailscale binaries, other plugins' files, or live secrets; existing GL keep lists already cover the four live web-server certificate paths on the verified firmware. The package stays recoverable when firmware keeps its files but loses user-package metadata.

## Security posture

- Private temporary and backup material uses `0700` directories and `0600` files under `/tmp`, removed on every normal exit. Activated certificates use mode `0644` and keys `0600`.
- A PID-checked atomic directory lock prevents overlapping runs and recovers abandoned locks.
- Status and log messages carry no private keys, certificate bodies, auth keys, or credentials. No private key reaches UCI.
- Each scheduled check makes at most one certificate request; a failure waits for the normal interval.
- RPC methods accept a boolean feature gate only and execute fixed package commands.
- Errors stay fail-open for networking. This project owns no routing, firewall, DNS, WAN, or listener state.
