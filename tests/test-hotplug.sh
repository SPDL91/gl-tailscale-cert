#!/bin/sh
set -eu

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT HUP INT TERM
ROOT="$SANDBOX/root"
HOOK="$REPO/src/hotplug/iface/90-gl-tailscale-cert"
CALLS="$ROOT/tmp/worker-calls"
TESTS=0

fail() { echo "not ok - $*" >&2; exit 1; }
pass() { TESTS=$((TESTS + 1)); echo "ok $TESTS - $1"; }

mkdir -p "$ROOT/usr/bin" "$ROOT/tmp"
cp "$HOOK" "$ROOT/hook"
chmod 0755 "$ROOT/hook"

write_worker() {
	result="$1"
	cat >"$ROOT/usr/bin/gl-tailscale-cert" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$CALLS"
exit $result
EOF
	chmod 0755 "$ROOT/usr/bin/gl-tailscale-cert"
}

wait_for_calls() {
	wanted="$1"
	limit="${2:-50}"
	waited=0
	while [ "$waited" -lt "$limit" ]; do
		count=0
		[ ! -f "$CALLS" ] || count=$(wc -l <"$CALLS")
		[ "$count" -ge "$wanted" ] && return 0
		sleep 0.02
		waited=$((waited + 1))
	done
	return 1
}

write_worker 0
GL_TAILSCALE_CERT_ROOT="$ROOT" GL_TAILSCALE_CERT_HOTPLUG_DELAY=0 \
	ACTION=ifup INTERFACE=wan "$ROOT/hook"
[ ! -e "$CALLS" ] || fail "WAN event invoked certificate worker"
GL_TAILSCALE_CERT_ROOT="$ROOT" GL_TAILSCALE_CERT_HOTPLUG_DELAY=0 \
	ACTION=ifdown INTERFACE=lan "$ROOT/hook"
[ ! -e "$CALLS" ] || fail "LAN ifdown invoked certificate worker"
pass "unrelated interface events do nothing"

GL_TAILSCALE_CERT_ROOT="$ROOT" GL_TAILSCALE_CERT_HOTPLUG_DELAY=0 \
	ACTION=ifup INTERFACE=lan "$ROOT/hook"
wait_for_calls 1 || fail "LAN ifup did not invoke certificate worker"
grep -qx -- '--once' "$CALLS" || fail "hook did not request a normal one-shot check"
pass "LAN recovery invokes the existing one-shot worker"

rm -f "$CALLS"
GL_TAILSCALE_CERT_ROOT="$ROOT" GL_TAILSCALE_CERT_HOTPLUG_DELAY=1 \
	ACTION=ifupdate INTERFACE=lan "$ROOT/hook"
GL_TAILSCALE_CERT_ROOT="$ROOT" GL_TAILSCALE_CERT_HOTPLUG_DELAY=1 \
	ACTION=ifup INTERFACE=lan "$ROOT/hook"
wait_for_calls 1 250 || fail "debounced recovery did not run"
sleep 0.1
[ "$(wc -l <"$CALLS")" -eq 1 ] || fail "duplicate events started multiple workers"
pass "duplicate LAN events collapse into one recovery run"

rm -f "$CALLS"
write_worker 1
GL_TAILSCALE_CERT_ROOT="$ROOT" GL_TAILSCALE_CERT_HOTPLUG_DELAY=0 \
	ACTION=ifup INTERFACE=lan "$ROOT/hook"
wait_for_calls 1 || fail "failing worker was not invoked"
waited=0
while [ -d "$ROOT/tmp/gl-tailscale-cert.hotplug-pending" ] && [ "$waited" -lt 50 ]; do
	sleep 0.02
	waited=$((waited + 1))
done
[ ! -d "$ROOT/tmp/gl-tailscale-cert.hotplug-pending" ] || fail "pending marker survived worker failure"
pass "worker errors stay non-fatal and release the debounce marker"

echo "1..$TESTS"
