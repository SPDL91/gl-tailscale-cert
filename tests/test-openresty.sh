#!/bin/sh
set -eu

# The OUI RPC is never loaded by any other test; a syntax error there ships silently
# and breaks the whole WebUI panel, so at least prove it parses.
for lua in /repo/src/rpc/ts-cert /repo/src/nginx/ui-header-filter.lua; do
	luajit -bl "$lua" >/dev/null || { echo "lua parse failed: $lua" >&2; exit 1; }
done
echo "ok - packaged Lua parses"

mkdir -p /usr/share/gl-tailscale-cert/www /usr/share/gl-ngx /usr/share/ts-fix /tmp/logs
cp /repo/src/nginx/ui-header-filter.lua /usr/share/gl-tailscale-cert/ui-header-filter.lua
VERSION=$(sed -n 's/^PKG_VERSION:=//p' /repo/Makefile)
sed "s/{{VERSION}}/$VERSION/g" /repo/src/nginx/ui-dispatch-filter.lua >/usr/share/gl-tailscale-cert/ui-dispatch-filter.lua
cp /repo/src/www/ts-cert.js /usr/share/gl-tailscale-cert/www/ts-cert.js
cp /repo/tests/fixtures/openresty/oui-access.lua /usr/share/gl-ngx/oui-access.lua
printf 'fixture' >/usr/share/ts-fix/ts-fix.js

check_state() {
	name="$1"
	expect_fix="$2"
	expect_cert="$3"
	conf="/repo/tests/fixtures/openresty/$name.conf"
	if [ "$expect_fix" = "1" ]; then
		cp /repo/tests/fixtures/ts-fix-v1.0.21/ts-fix-body-filter.lua /usr/share/ts-fix/ts-fix-body-filter.lua
		cp /repo/tests/fixtures/ts-fix-v1.0.21/ts-fix-header-filter.lua /usr/share/ts-fix/ts-fix-header-filter.lua
	else
		rm -f /usr/share/ts-fix/ts-fix-body-filter.lua /usr/share/ts-fix/ts-fix-header-filter.lua
	fi
	openresty -t -c "$conf" -p /tmp >/dev/null
	openresty -c "$conf" -p /tmp
	trap 'openresty -s stop -c "$conf" -p /tmp >/dev/null 2>&1 || true' EXIT HUP INT TERM
	sleep 1
	html=$(wget -qO- http://127.0.0.1:18080/gl_home.html)
	root_html=$(wget -qO- http://127.0.0.1:18080/)
	fix_count=$({ printf '%s' "$html" | grep -o '/ts-fix/ts-fix.js' || true; } | wc -l | tr -d ' ')
	cert_count=$({ printf '%s' "$html" | grep -o '/ts-cert/ts-cert.js' || true; } | wc -l | tr -d ' ')
	root_fix_count=$({ printf '%s' "$root_html" | grep -o '/ts-fix/ts-fix.js' || true; } | wc -l | tr -d ' ')
	root_cert_count=$({ printf '%s' "$root_html" | grep -o '/ts-cert/ts-cert.js' || true; } | wc -l | tr -d ' ')
	[ "$fix_count" = "$expect_fix" ] || { echo "$name: expected $expect_fix ts-fix scripts, got $fix_count" >&2; exit 1; }
	[ "$cert_count" = "$expect_cert" ] || { echo "$name: expected $expect_cert ts-cert scripts, got $cert_count" >&2; exit 1; }
	[ "$root_fix_count" = "$expect_fix" ] || { echo "$name root: expected $expect_fix ts-fix scripts, got $root_fix_count" >&2; exit 1; }
	[ "$root_cert_count" = "$expect_cert" ] || { echo "$name root: expected $expect_cert ts-cert scripts, got $root_cert_count" >&2; exit 1; }
	openresty -s stop -c "$conf" -p /tmp >/dev/null
	trap - EXIT HUP INT TERM
	echo "ok - nginx $name state injects fix=$fix_count cert=$cert_count"
}

check_state base 0 0
check_state cert-only 0 1
check_state fix-only 1 0
check_state both 1 1
