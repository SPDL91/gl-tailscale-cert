# Compatibility

## Firmware tiers

| Tier | GL.iNet firmware | OpenWrt base | Package manager | Artifact | Status |
|---|---|---|---|---|---|
| Primary | 4.5.x–4.9.x | 21.02 through 24.10 | `opkg` | `all.ipk` | Local suites pass; core workflow checked on two GL routers |
| Preview | 4.9.x `op25` | 25.12 | apk-tools v3 | `noarch.apk` | Format verified; live GL WebUI acceptance pending |

OpenWrt 24.10 and older use `opkg`; OpenWrt 25.12 and newer use apk-tools v3.
See the OpenWrt [package management guide](https://openwrt.org/docs/guide-user/additional-software/managing_packages),
[apk guide](https://openwrt.org/docs/guide-user/additional-software/apk), and
[package policy](https://openwrt.org/docs/guide-developer/package-policies).

## Verified devices

| Device | Firmware | OpenWrt base | Tailscale |
|---|---|---|---|
| Flint 2 / GL-MT6000 | 4.9.1 | 21.02-SNAPSHOT | 1.92.5 |
| Beryl AX / GL-MT3000 | 4.8.1 | — | 1.102.2 |

The package contains architecture-independent shell, Lua, and JavaScript.

## Dependencies

`opkg` and `apk` resolve the package's dependencies (`uci`, `jsonfilter`,
`openssl-util`, `ca-bundle`) during install. GL.iNet firmware supplies
everything else the package uses, including Tailscale itself. This package never
installs or updates Tailscale.

## Out of scope

Stock OpenWrt remains outside the v0.1 WebUI target set. The package reads
GL.iNet's nginx/OUI RPC stack and uHTTPd certificate paths directly, so it
depends on that firmware layout.
