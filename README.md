# gl-tailscale-cert

Serve the GL.iNet Admin Panel and LuCI over HTTPS without a browser certificate
warning.

The package fetches the router's Tailscale certificate for its `*.ts.net` name
and installs it into both web servers: nginx for the GL.iNet Admin Panel and
uHTTPd for LuCI. It then keeps that certificate in place. It renews the
certificate before expiry and restores it after a reboot, a firmware upgrade, or
a LAN settings save that overwrites the router's certificate.

The feature starts disabled. Nothing happens until you enable it.

## Requirements

- A GL.iNet router on firmware 4.5–4.9 with Tailscale already running.
- MagicDNS and HTTPS Certificates enabled in the Tailscale admin console. See
  [Enabling HTTPS](https://tailscale.com/docs/how-to/set-up-https-certificates).

Requesting the certificate publishes the router's full Tailscale DNS name in
public Certificate Transparency logs.

If AdGuard Home serves DNS-over-TLS from `/etc/nginx/nginx.cer`, use AdGuard
0.107.72 or later. It watches that file and reloads after a renewal. Earlier
versions read the certificate once at startup and keep serving the previous one
until they restart.

For tested models, firmware tiers, and the full dependency list, see
[docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## Install

Over SSH on the router:

```sh
wget -qO install.sh https://raw.githubusercontent.com/SPDL91/gl-tailscale-cert/main/install.sh && sh install.sh
```

The script picks the artifact matching the router's package manager, verifies its
published SHA-256, and installs nothing if the checksum does not match. Read
[install.sh](install.sh) first if you would rather see what it does before
running it.

To install by hand instead, download the artifact and its `.sha256` sidecar from
[Releases](https://github.com/SPDL91/gl-tailscale-cert/releases), copy both to
the router, and verify before installing:

```sh
sha256sum -c gl-tailscale-cert_0.1.9_all.ipk.sha256

# OpenWrt 24.10 and older
opkg install /tmp/gl-tailscale-cert_0.1.9_all.ipk

# OpenWrt 25.12 and newer
apk add --allow-untrusted /tmp/gl-tailscale-cert-0.1.9.apk
```

## Enable

In the GL.iNet Admin Panel, open the Tailscale page and turn on the certificate
option.

From the shell:

```sh
uci set ts_cert.main.enabled='1'
uci commit ts_cert
/etc/init.d/gl-tailscale-cert restart
```

Reload the admin panel in a browser once the certificate lands. The router keeps
its previous certificate if anything fails, so a failed attempt leaves the web
interface reachable.

## Commands

```sh
gl-tailscale-cert --status          # current state; add --json for a parseable form
gl-tailscale-cert --verify          # read-only check of the current certificate state
gl-tailscale-cert --once            # run one check now
gl-tailscale-cert --once --force    # renew now
gl-tailscale-cert --version
```

Every command respects the enable setting. `--verify` writes nothing.

## Settings

The package owns `/etc/config/ts_cert`. The defaults suit most routers.

```uci
config settings 'main'
        option enabled '0'
        option check_interval '43200'    # full validation, seconds
        option watch_interval '30'       # certificate file watch, seconds
        option min_validity_hours '1440'
        option readiness_timeout '120'
        option request_timeout '180'
```

Restart the service after editing the file by hand:

```sh
/etc/init.d/gl-tailscale-cert restart
```

The worker clamps values that fall below safe limits.

## Scope

The package never changes routing, firewall rules, DNS, WAN behavior,
listeners, SSH, Tailscale settings, or `/usr/bin/gl_tailscale`. It contacts
Let's Encrypt only when neither web server already holds a usable certificate.
Removing the package leaves the last valid certificate in place.

It also works alongside
[`gl-tailscale-fix`](https://github.com/RemoteToHome-io/gl-tailscale-fix)
without patching or depending on it.

## Build from source

The root `Makefile` provides the canonical OpenWrt source-package definition.
Place the repository in a package feed or SDK `package/` directory and build it
with the SDK matching the target firmware.

For review builds without an SDK:

```sh
sh pkg/build.sh 0.1.9
sh pkg/build-apk.sh build/out/gl-tailscale-cert_0.1.9_all.ipk build/out
```

The second command requires apk-tools v3. Use an SDK build for distribution.

## Documentation

- [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) — supported firmware, tested
  devices, runtime dependencies.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — process model, activation and
  rollback, security posture, lifecycle.
- [docs/TESTING.md](docs/TESTING.md) — test suites.
- [docs/LIVE-ACCEPTANCE.md](docs/LIVE-ACCEPTANCE.md) — on-device acceptance
  steps.
- [CONTRIBUTING.md](CONTRIBUTING.md) — contribution rules.

Report security issues through [SECURITY.md](SECURITY.md). Do not open a public
issue containing router logs or tailnet names.

## License

GPL-3.0-only. The small `gl-tailscale-fix` compatibility fixtures retain their
upstream copyright and GPL notice.
