#!/bin/sh
# Build a reviewable legacy IPK without an SDK. Canonical distribution builds
# should use the matching OpenWrt SDK and the repository Makefile.
set -eu

for command_name in install sed gzip tar sha256sum; do
	command -v "$command_name" >/dev/null 2>&1 || {
		echo "Missing build tool: $command_name" >&2
		exit 1
	}
done

VERSION="${1:-${VERSION:-0.1.7}}"
VERSION="${VERSION#v}"
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
ROOT_DIR=$(dirname "$SCRIPT_DIR")
OUT_DIR="$ROOT_DIR/build/out"
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT HUP INT TERM
mkdir -p "$BUILD_DIR/control" "$BUILD_DIR/data" "$OUT_DIR"
DATA="$BUILD_DIR/data"
CTRL="$BUILD_DIR/control"

install -d "$DATA/etc/init.d" "$DATA/usr/bin"
install -m 0755 "$ROOT_DIR/src/init.d/gl-tailscale-cert" "$DATA/etc/init.d/gl-tailscale-cert"
sed "s/{{VERSION}}/$VERSION/g" "$ROOT_DIR/src/scripts/gl-tailscale-cert" >"$DATA/usr/bin/gl-tailscale-cert"
chmod 0755 "$DATA/usr/bin/gl-tailscale-cert"
install -d "$DATA/etc/hotplug.d/iface"
install -m 0755 "$ROOT_DIR/src/hotplug/iface/90-gl-tailscale-cert" "$DATA/etc/hotplug.d/iface/90-gl-tailscale-cert"

install -d "$DATA/usr/lib/oui-httpd/rpc" "$DATA/usr/libexec/gl-tailscale-cert"
install -m 0644 "$ROOT_DIR/src/rpc/ts-cert" "$DATA/usr/lib/oui-httpd/rpc/ts-cert"
install -m 0755 "$ROOT_DIR/src/lifecycle/postinst" "$DATA/usr/libexec/gl-tailscale-cert/postinst"
install -m 0755 "$ROOT_DIR/src/lifecycle/prerm" "$DATA/usr/libexec/gl-tailscale-cert/prerm"

install -d "$DATA/usr/share/gl-tailscale-cert/defaults" "$DATA/usr/share/gl-tailscale-cert/nginx" "$DATA/usr/share/gl-tailscale-cert/www"
install -m 0600 "$ROOT_DIR/src/config/ts_cert" "$DATA/usr/share/gl-tailscale-cert/defaults/ts_cert"
install -m 0644 "$ROOT_DIR/src/nginx/ts-cert.conf" "$DATA/usr/share/gl-tailscale-cert/nginx/ts-cert.conf"
install -m 0644 "$ROOT_DIR/src/nginx/ui-header-filter.lua" "$DATA/usr/share/gl-tailscale-cert/ui-header-filter.lua"
sed "s/{{VERSION}}/$VERSION/g" "$ROOT_DIR/src/nginx/ui-dispatch-filter.lua" >"$DATA/usr/share/gl-tailscale-cert/ui-dispatch-filter.lua"
chmod 0644 "$DATA/usr/share/gl-tailscale-cert/ui-dispatch-filter.lua"
sed "s/{{VERSION}}/$VERSION/g" "$ROOT_DIR/src/www/ts-cert.js" >"$DATA/usr/share/gl-tailscale-cert/www/ts-cert.js"
chmod 0644 "$DATA/usr/share/gl-tailscale-cert/www/ts-cert.js"
gzip -9 -c "$DATA/usr/share/gl-tailscale-cert/www/ts-cert.js" >"$DATA/usr/share/gl-tailscale-cert/www/ts-cert.js.gz"
chmod 0644 "$DATA/usr/share/gl-tailscale-cert/www/ts-cert.js.gz"

install -d "$DATA/lib/upgrade/keep.d"
install -m 0644 "$ROOT_DIR/src/upgrade/keep.d/gl-tailscale-cert" "$DATA/lib/upgrade/keep.d/gl-tailscale-cert"

sed "s/{{VERSION}}/$VERSION/g" "$SCRIPT_DIR/control" >"$CTRL/control"
install -m 0755 "$SCRIPT_DIR/postinst" "$CTRL/postinst"
install -m 0755 "$SCRIPT_DIR/prerm" "$CTRL/prerm"
printf '2.0\n' >"$BUILD_DIR/debian-binary"

(cd "$CTRL" && tar --owner=0 --group=0 --numeric-owner -czf "$BUILD_DIR/control.tar.gz" .)
(cd "$DATA" && tar --owner=0 --group=0 --numeric-owner -czf "$BUILD_DIR/data.tar.gz" .)
IPK="$OUT_DIR/gl-tailscale-cert_${VERSION}_all.ipk"
rm -f "$IPK" "$IPK.sha256"
(cd "$BUILD_DIR" && tar --owner=0 --group=0 --numeric-owner -czf "$IPK" ./debian-binary ./control.tar.gz ./data.tar.gz)
(cd "$(dirname "$IPK")" && sha256sum "$(basename "$IPK")" >"$(basename "$IPK").sha256")
echo "Built $IPK"
