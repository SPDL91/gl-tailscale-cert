#!/bin/sh
set -eu

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT HUP INT TERM
ROOT="$SANDBOX/root"
TESTS=0

fail() { echo "not ok - $*" >&2; exit 1; }
pass() { TESTS=$((TESTS + 1)); echo "ok $TESTS - $1"; }
assert_file() { [ -f "$1" ] || fail "missing file $1"; }
assert_absent() { [ ! -e "$1" ] || fail "unexpected path $1"; }

mkdir -p "$ROOT/etc/config" "$ROOT/etc/nginx/gl-conf.d" "$ROOT/etc/init.d" \
	"$ROOT/usr/sbin" "$ROOT/usr/share/gl-tailscale-cert/defaults" \
	"$ROOT/usr/share/gl-tailscale-cert/nginx" "$ROOT/usr/share/ts-fix" "$ROOT/tmp"
cp "$REPO/src/config/ts_cert" "$ROOT/usr/share/gl-tailscale-cert/defaults/ts_cert"
cp "$REPO/src/nginx/ts-cert.conf" "$ROOT/usr/share/gl-tailscale-cert/nginx/ts-cert.conf"

cat >"$ROOT/usr/sbin/nginx" <<'EOF'
#!/bin/sh
root=${GL_TAILSCALE_CERT_ROOT:?}
if [ "$1" = "-s" ] && [ "$2" = "reload" ]; then
	printf 'nginx reload\n' >>"$root/tmp/actions"
fi
exit 0
EOF
chmod 0755 "$ROOT/usr/sbin/nginx"
cat >"$ROOT/etc/init.d/mock" <<'EOF'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$1" >>"${GL_TAILSCALE_CERT_ROOT}/tmp/actions"
exit 0
EOF
chmod 0755 "$ROOT/etc/init.d/mock"
ln -s mock "$ROOT/etc/init.d/nginx"
ln -s mock "$ROOT/etc/init.d/gl-tailscale-cert"

GL_TAILSCALE_CERT_ROOT="$ROOT" "$REPO/src/lifecycle/postinst"
assert_file "$ROOT/etc/config/ts_cert"
grep -q "option enabled '0'" "$ROOT/etc/config/ts_cert" || fail "fresh install not disabled"
assert_file "$ROOT/etc/nginx/gl-conf.d/ts-cert.conf"
grep -q '^gl-tailscale-cert enable$' "$ROOT/tmp/actions" || fail "service not enabled"
grep -q '^gl-tailscale-cert restart$' "$ROOT/tmp/actions" || fail "service not restarted"
pass "fresh install creates disabled config and repairs service activation"

sed -i "s/option enabled '0'/option enabled '1'/" "$ROOT/etc/config/ts_cert"
GL_TAILSCALE_CERT_ROOT="$ROOT" "$REPO/src/lifecycle/postinst"
grep -q "option enabled '1'" "$ROOT/etc/config/ts_cert" || fail "postinst overwrote user config"
pass "reinstall after metadata loss preserves existing UCI configuration"

printf ts-fix >"$ROOT/etc/nginx/gl-conf.d/ts-fix.conf"
printf ts-fix-asset >"$ROOT/usr/share/ts-fix/keep"
printf cert >"$ROOT/etc/nginx/nginx.cer"
printf key >"$ROOT/etc/nginx/nginx.key"
PKG_UPGRADE=1 GL_TAILSCALE_CERT_ROOT="$ROOT" "$REPO/src/lifecycle/prerm"
assert_file "$ROOT/etc/config/ts_cert"
assert_file "$ROOT/etc/nginx/gl-conf.d/ts-cert.conf"
pass "normal opkg upgrade leaves active config and service for takeover"

GL_TAILSCALE_CERT_ROOT="$ROOT" "$REPO/src/lifecycle/prerm"
assert_absent "$ROOT/etc/config/ts_cert"
assert_absent "$ROOT/etc/nginx/gl-conf.d/ts-cert.conf"
assert_file "$ROOT/etc/nginx/gl-conf.d/ts-fix.conf"
assert_file "$ROOT/usr/share/ts-fix/keep"
assert_file "$ROOT/etc/nginx/nginx.cer"
assert_file "$ROOT/etc/nginx/nginx.key"
pass "removal owns only ts-cert files and leaves certificates and ts-fix intact"

GL_TAILSCALE_CERT_ROOT="$ROOT" "$REPO/src/lifecycle/postinst"
grep -q "option enabled '1'" "$ROOT/etc/config/ts_cert" || fail "force reinstall did not restore config"
assert_file "$ROOT/etc/nginx/gl-conf.d/ts-cert.conf"
pass "force reinstall restores saved config and WebUI adapter"

echo "1..$TESTS"
