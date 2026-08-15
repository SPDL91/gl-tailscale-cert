#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Download, verify, and install the latest gl-tailscale-cert release.
#
#   wget -qO install.sh https://raw.githubusercontent.com/SPDL91/gl-tailscale-cert/main/install.sh && sh install.sh
#
# The package installs disabled. Nothing runs until you enable it.

set -eu

REPO="SPDL91/gl-tailscale-cert"
API="https://api.github.com/repos/$REPO/releases/latest"
WORK=""

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

info() {
	printf '%s\n' "$*"
}

cleanup() {
	[ -z "$WORK" ] || rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM

fetch() {
	# fetch URL DESTINATION
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "$1" -o "$2"
	elif command -v wget >/dev/null 2>&1; then
		wget -q -O "$2" "$1"
	else
		die "neither wget nor curl is available"
	fi
}

sha256_of() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | awk '{print $1}'
	elif command -v openssl >/dev/null 2>&1; then
		openssl dgst -sha256 "$1" | awk '{print $NF}'
	else
		die "no SHA-256 tool available to verify the download"
	fi
}

asset_url() {
	# asset_url EXTENSION; prints the first matching browser_download_url
	tr ',' '\n' <"$WORK/release.json" |
		sed -n 's/.*"browser_download_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
		grep "\\.$1\$" |
		head -n 1
}

[ "$(id -u)" = "0" ] || die "run this as root on the router"

if [ ! -f /etc/openwrt_release ]; then
	info "warning: no /etc/openwrt_release; this package targets GL.iNet OpenWrt firmware"
fi

if command -v opkg >/dev/null 2>&1; then
	MANAGER=opkg
	EXT=ipk
elif command -v apk >/dev/null 2>&1; then
	MANAGER=apk
	EXT=apk
else
	die "found neither opkg nor apk"
fi

WORK=$(mktemp -d 2>/dev/null) || WORK="/tmp/gl-tailscale-cert-install.$$"
mkdir -p "$WORK"

info "Looking up the latest release..."
fetch "$API" "$WORK/release.json" || die "could not reach the GitHub release API"

URL=$(asset_url "$EXT")
[ -n "$URL" ] || die "the latest release publishes no .$EXT artifact"
FILE=${URL##*/}

info "Downloading $FILE..."
fetch "$URL" "$WORK/$FILE" || die "could not download $FILE"

info "Verifying checksum..."
fetch "$URL.sha256" "$WORK/$FILE.sha256" || die "could not download the checksum for $FILE"
EXPECTED=$(awk 'NR == 1 {print $1}' "$WORK/$FILE.sha256")
ACTUAL=$(sha256_of "$WORK/$FILE")
[ -n "$EXPECTED" ] || die "the published checksum file is empty"
if [ "$EXPECTED" != "$ACTUAL" ]; then
	die "checksum mismatch for $FILE; expected $EXPECTED, got $ACTUAL. Nothing was installed."
fi

info "Installing $FILE with $MANAGER..."
case "$MANAGER" in
	opkg) opkg install "$WORK/$FILE" ;;
	apk) apk add --allow-untrusted "$WORK/$FILE" ;;
esac

cat <<'EOF'

Installed. The certificate feature starts disabled.

Enable it in the GL.iNet Admin Panel on the Tailscale page, or from the shell:

  uci set ts_cert.main.enabled='1'
  uci commit ts_cert
  /etc/init.d/gl-tailscale-cert restart

Check progress with:

  gl-tailscale-cert --status

MagicDNS and HTTPS Certificates must be enabled in the Tailscale admin console.
EOF
