#!/bin/sh
# Repackage the reviewed IPK payload with OpenWrt 25.12 apk-tools v3.
set -eu

IPK="${1:?usage: build-apk.sh PACKAGE.ipk [OUTPUT-DIR]}"
OUT_DIR="${2:-$(dirname "$IPK")}"

command -v apk >/dev/null 2>&1 || { echo "apk-tools v3 is required" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 1; }
if apk mkpkg 2>&1 | grep -q "is not an apk command"; then
	echo "apk-tools v3 with mkpkg is required" >&2
	exit 1
fi
[ -f "$IPK" ] || { echo "IPK not found: $IPK" >&2; exit 1; }

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT HUP INT TERM
mkdir -p "$WORK_DIR/files" "$WORK_DIR/control"
tar -xzf "$IPK" -C "$WORK_DIR" --no-same-owner
tar -xzf "$WORK_DIR/data.tar.gz" -C "$WORK_DIR/files" --no-same-owner
tar -xzf "$WORK_DIR/control.tar.gz" -C "$WORK_DIR/control" --no-same-owner

field() {
	sed -n "s/^$1: //p" "$WORK_DIR/control/control" | head -n 1
}

NAME=$(field Package)
VERSION=$(field Version)
MAINTAINER=$(field Maintainer)
DEPENDS=$(field Depends | tr ',' ' ' | tr -s ' ')
DESCRIPTION=$(awk '
  /^Description:/ { sub(/^Description: */, ""); value=$0; next }
  value != "" && /^ / { line=$0; sub(/^ +/, "", line); value=value " " line; next }
  value != "" { print value; exit }
  END { if (value != "") print value }
' "$WORK_DIR/control/control")
if [ -z "$NAME" ] || [ -z "$VERSION" ]; then
	echo "Invalid IPK control metadata" >&2
	exit 1
fi

APK_VERSION=$(printf '%s' "$VERSION" | sed 's/-ci\./_p/')
OUTPUT="$OUT_DIR/$NAME-$APK_VERSION.apk"
SOURCE_DATE_EPOCH=0 apk mkpkg \
	--info "name:$NAME" \
	--info "version:$APK_VERSION" \
	--info "description:$DESCRIPTION" \
	--info "arch:noarch" \
	--info "license:GPL-3.0-only" \
	--info "origin:gl-tailscale-cert" \
	--info "maintainer:$MAINTAINER" \
	--info "url:https://github.com/SPDL91/gl-tailscale-cert" \
	--info "depends:$DEPENDS" \
	--script "post-install:$WORK_DIR/control/postinst" \
	--script "post-upgrade:$WORK_DIR/control/postinst" \
	--script "pre-deinstall:$WORK_DIR/control/prerm" \
	--files "$WORK_DIR/files" \
	--output "$OUTPUT"
(cd "$(dirname "$OUTPUT")" && sha256sum "$(basename "$OUTPUT")" >"$(basename "$OUTPUT").sha256")
echo "Built $OUTPUT"
