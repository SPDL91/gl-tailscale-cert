#!/bin/sh
set -eu

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
WORKER="$REPO/src/scripts/gl-tailscale-cert"
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT HUP INT TERM
FAKE_FQDN=router.test-tail.ts.net
TESTS=0
TEST_CA_KEY="$SANDBOX/test-ca.key"
TEST_CA_CERT="$SANDBOX/test-ca.crt"
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
	-subj "/CN=gl-tailscale-cert test root" \
	-keyout "$TEST_CA_KEY" -out "$TEST_CA_CERT" >/dev/null 2>&1

fail() {
	echo "not ok - $*" >&2
	exit 1
}

pass() {
	TESTS=$((TESTS + 1))
	echo "ok $TESTS - $1"
}

assert_eq() {
	[ "$1" = "$2" ] || fail "expected '$2', got '$1'"
}

assert_file() {
	[ -f "$1" ] || fail "missing file $1"
}

assert_absent() {
	[ ! -e "$1" ] || fail "unexpected path $1"
}

status_value() {
	sed -n "s/^$1=//p" "$ROOT/tmp/gl-tailscale-cert.status" | head -n 1
}

write_config() {
	enabled="$1"
	cat >"$ROOT/etc/config/ts_cert" <<EOF
config settings 'main'
	option enabled '$enabled'
	option check_interval '43200'
	option min_validity_hours '1440'
	option readiness_timeout '5'
	option request_timeout '30'
EOF
}

make_cert() {
	prefix="$1"
	days="$2"
	name="${3:-$FAKE_FQDN}"
	openssl req -newkey rsa:2048 -nodes -subj "/CN=$name" \
		-keyout "$prefix.key" -out "$prefix.csr" >/dev/null 2>&1
	printf 'subjectAltName=DNS:%s\n' "$name" >"$prefix.ext"
	openssl x509 -req -in "$prefix.csr" -CA "$TEST_CA_CERT" -CAkey "$TEST_CA_KEY" \
		-set_serial 1 -days "$days" -sha256 -extfile "$prefix.ext" \
		-out "$prefix.crt" >/dev/null 2>&1
	rm -f "$prefix.csr" "$prefix.ext"
}

make_self_signed_cert() {
	prefix="$1"
	days="$2"
	name="${3:-$FAKE_FQDN}"
	openssl req -x509 -newkey rsa:2048 -nodes -days "$days" \
		-subj "/CN=$name" -addext "subjectAltName=DNS:$name" \
		-keyout "$prefix.key" -out "$prefix.crt" >/dev/null 2>&1
}

setup_root() {
	ROOT="$SANDBOX/root"
	rm -rf "$ROOT"
	mkdir -p "$ROOT/etc/config" "$ROOT/etc/nginx/gl-conf.d" "$ROOT/etc/init.d" \
		"$ROOT/etc/ssl/certs" "$ROOT/usr/bin" "$ROOT/usr/sbin" "$ROOT/sbin" "$ROOT/tmp" "$ROOT/mockbin"
	cp "$TEST_CA_CERT" "$ROOT/etc/ssl/certs/ca-certificates.crt"

	cat >"$ROOT/etc/tailscale-status.json" <<EOF
{"BackendState":"Running","Self":{"DNSName":"$FAKE_FQDN."}}
EOF

	cat >"$ROOT/sbin/uci" <<'EOF'
#!/bin/sh
root=${GL_TAILSCALE_CERT_ROOT:?}
[ "$1" = "-q" ] && shift
[ "$1" = "get" ] || exit 1
key=${2##*.}
sed -n "s/^[[:space:]]*option[[:space:]]*$key[[:space:]]*'\([^']*\)'.*/\1/p" "$root/etc/config/ts_cert" | head -n 1
EOF
	chmod 0755 "$ROOT/sbin/uci"

	cat >"$ROOT/usr/bin/jsonfilter" <<'EOF'
#!/bin/sh
input=
expr=
while [ "$#" -gt 0 ]; do
	case "$1" in
		-i) input=$2; shift 2 ;;
		-e) expr=$2; shift 2 ;;
		*) shift ;;
	esac
done
case "$expr" in
	'@.BackendState') key=BackendState ;;
	'@.Self.DNSName') key=DNSName ;;
	*) exit 1 ;;
esac
sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$input" | head -n 1
EOF
	chmod 0755 "$ROOT/usr/bin/jsonfilter"

	cat >"$ROOT/usr/sbin/tailscale" <<'EOF'
#!/bin/sh
root=${GL_TAILSCALE_CERT_ROOT:?}
case "$1" in
	status)
		[ ! -f "$root/tmp/tailscale-unavailable" ] || exit 1
		if [ -f "$root/tmp/status-first-stale" ]; then
			count=0
			[ ! -f "$root/tmp/status-call-count" ] || count=$(cat "$root/tmp/status-call-count")
			count=$((count + 1))
			printf '%s\n' "$count" >"$root/tmp/status-call-count"
			if [ "$count" -eq 1 ]; then
				sed 's/router\.test-tail\.ts\.net/stale.test-tail.ts.net/g' "$root/etc/tailscale-status.json"
			else
				cat "$root/etc/tailscale-status.json"
			fi
		else
			cat "$root/etc/tailscale-status.json"
		fi
		;;
	cert)
		count=0
		[ ! -f "$root/tmp/request-count" ] || count=$(cat "$root/tmp/request-count")
		count=$((count + 1))
		printf '%s\n' "$count" >"$root/tmp/request-count"
		[ ! -f "$root/tmp/cert-fail" ] || exit 1
		shift
		cert_out=
		key_out=
		for arg in "$@"; do
			case "$arg" in
				--cert-file=*) cert_out=${arg#*=} ;;
				--key-file=*) key_out=${arg#*=} ;;
			esac
		done
		cp "$MOCK_CERT" "$cert_out"
		cp "$MOCK_KEY" "$key_out"
		;;
	*) exit 2 ;;
esac
EOF
	chmod 0755 "$ROOT/usr/sbin/tailscale"

	cat >"$ROOT/usr/sbin/nginx" <<'EOF'
#!/bin/sh
root=${GL_TAILSCALE_CERT_ROOT:?}
case "$1" in
	-t) [ ! -f "$root/tmp/nginx-test-fail" ] ;;
	-s)
		[ "$2" = "reload" ] || exit 2
		printf 'nginx reload\n' >>"$root/tmp/service-actions"
		[ ! -f "$root/tmp/nginx-reload-fail" ]
		;;
	*) exit 2 ;;
esac
EOF
	chmod 0755 "$ROOT/usr/sbin/nginx"

	cat >"$ROOT/etc/init.d/service-mock" <<'EOF'
#!/bin/sh
root=${GL_TAILSCALE_CERT_ROOT:?}
service=${0##*/}
printf '%s %s\n' "$service" "$1" >>"$root/tmp/service-actions"
[ ! -f "$root/tmp/$service-$1-fail" ]
EOF
	chmod 0755 "$ROOT/etc/init.d/service-mock"
	ln -s service-mock "$ROOT/etc/init.d/nginx"
	ln -s service-mock "$ROOT/etc/init.d/uhttpd"
	ln -s service-mock "$ROOT/etc/init.d/gl-tailscale-cert"

	cat >"$ROOT/mockbin/sleep" <<'EOF'
#!/bin/sh
[ -z "${GL_TAILSCALE_CERT_REAL_SLEEP:-}" ] || exec /bin/sleep "$@"
exit 0
EOF
	chmod 0755 "$ROOT/mockbin/sleep"
	write_config 1
	make_cert "$ROOT/tmp/generated" 90
	MOCK_CERT="$ROOT/tmp/generated.crt"
	MOCK_KEY="$ROOT/tmp/generated.key"
	export ROOT MOCK_CERT MOCK_KEY
}

run_worker() {
	GL_TAILSCALE_CERT_ROOT="$ROOT" \
	GL_TAILSCALE_CERT_OPENSSL=/usr/bin/openssl \
	PATH="$ROOT/mockbin:$PATH" \
		"$WORKER" "$@"
}

install_live_pair() {
	prefix="$1"
	cp "$prefix.crt" "$ROOT/etc/nginx/nginx.cer"
	cp "$prefix.key" "$ROOT/etc/nginx/nginx.key"
	cp "$prefix.crt" "$ROOT/etc/uhttpd.crt"
	cp "$prefix.key" "$ROOT/etc/uhttpd.key"
	chmod 0644 "$ROOT/etc/nginx/nginx.cer" "$ROOT/etc/uhttpd.crt"
	chmod 0600 "$ROOT/etc/nginx/nginx.key" "$ROOT/etc/uhttpd.key"
}

setup_root
write_config 0
printf sentinel >"$ROOT/etc/nginx/nginx.cer"
run_worker --once
assert_eq "$(status_value state)" disabled
assert_eq "$(cat "$ROOT/etc/nginx/nginx.cer")" sentinel
assert_absent "$ROOT/tmp/request-count"
pass "disabled state makes no certificate changes"

setup_root
touch "$ROOT/tmp/tailscale-unavailable"
if run_worker --once; then fail "unavailable Tailscale unexpectedly succeeded"; fi
assert_eq "$(status_value state)" waiting
assert_absent "$ROOT/tmp/request-count"
pass "Tailscale unavailable is recoverable and does not request"

setup_root
printf '%s\n' '{"BackendState":"Running","Self":{"DNSName":"bad name.example.com."}}' >"$ROOT/etc/tailscale-status.json"
if run_worker --once; then fail "malformed DNS name unexpectedly succeeded"; fi
assert_eq "$(status_value state)" waiting
assert_absent "$ROOT/tmp/request-count"
pass "malformed or non-ts.net hostname is rejected"

setup_root
touch "$ROOT/tmp/status-first-stale"
run_worker --once
assert_eq "$(cat "$ROOT/tmp/status-call-count")" 3
assert_eq "$(status_value fqdn)" "$FAKE_FQDN"
pass "one stale Tailscale DNS sample is ignored until two identical samples agree"

setup_root
touch "$ROOT/tmp/cert-fail"
if run_worker --once; then fail "failed certificate command unexpectedly succeeded"; fi
assert_eq "$(status_value state)" error
assert_eq "$(cat "$ROOT/tmp/request-count")" 1
pass "certificate command failure has no tight retry loop"

setup_root
make_cert "$ROOT/tmp/near-expiry" 1
install_live_pair "$ROOT/tmp/near-expiry"
near_expiry_hash=$(sha256sum "$ROOT/etc/nginx/nginx.cer")
touch "$ROOT/tmp/cert-fail"
if run_worker --once; then fail "failed due renewal unexpectedly succeeded"; fi
assert_eq "$(status_value state)" renewal_due
assert_eq "$(cat "$ROOT/tmp/request-count")" 1
assert_eq "$(sha256sum "$ROOT/etc/nginx/nginx.cer")" "$near_expiry_hash"
pass "failed due renewal keeps the still-valid certificate and waits for the normal schedule"

setup_root
install_live_pair "$ROOT/tmp/generated"
before=$(sha256sum "$ROOT/etc/nginx/nginx.cer")
run_worker --once
after=$(sha256sum "$ROOT/etc/nginx/nginx.cer")
assert_eq "$after" "$before"
assert_absent "$ROOT/tmp/request-count"
assert_absent "$ROOT/tmp/service-actions"
assert_absent "$ROOT/tmp/gl-tailscale-cert.lock"
assert_eq "$(status_value state)" valid
pass "valid identical live certificate is a no-op"

setup_root
make_self_signed_cert "$ROOT/tmp/self-signed" 365
install_live_pair "$ROOT/tmp/self-signed"
self_signed_hash=$(sha256sum "$ROOT/etc/nginx/nginx.cer")
run_worker --once
[ "$(sha256sum "$ROOT/etc/nginx/nginx.cer")" != "$self_signed_hash" ] || fail "self-signed certificate was accepted"
assert_eq "$(cat "$ROOT/tmp/request-count")" 1
assert_eq "$(status_value action)" renewal
pass "hostname-valid self-signed certificate is rejected and replaced from Tailscale"

setup_root
cp "$ROOT/tmp/generated.crt" "$ROOT/etc/uhttpd.crt"
cp "$ROOT/tmp/generated.key" "$ROOT/etc/uhttpd.key"
printf invalid >"$ROOT/etc/nginx/nginx.cer"
printf invalid >"$ROOT/etc/nginx/nginx.key"
run_worker --once
cmp -s "$ROOT/etc/nginx/nginx.cer" "$ROOT/etc/uhttpd.crt" || fail "repair cert mismatch"
cmp -s "$ROOT/etc/nginx/nginx.key" "$ROOT/etc/uhttpd.key" || fail "repair key mismatch"
assert_absent "$ROOT/tmp/request-count"
assert_eq "$(status_value action)" repair
pass "existing valid uHTTPd pair repairs nginx without a request"

setup_root
run_worker --once
assert_eq "$(cat "$ROOT/tmp/request-count")" 1
cmp -s "$ROOT/etc/nginx/nginx.cer" "$ROOT/etc/uhttpd.crt" || fail "renewed cert mismatch"
cmp -s "$ROOT/etc/nginx/nginx.key" "$ROOT/etc/uhttpd.key" || fail "renewed key mismatch"
grep -q '^uhttpd restart$' "$ROOT/tmp/service-actions" || fail "uHTTPd was not restarted after certificate activation"
if grep -q '^uhttpd reload$' "$ROOT/tmp/service-actions"; then fail "unreliable uHTTPd reload was used"; fi
assert_eq "$(stat -c %a "$ROOT/etc/nginx/nginx.cer")" 644
assert_eq "$(stat -c %a "$ROOT/etc/nginx/nginx.key")" 600
assert_eq "$(status_value action)" renewal
pass "renewal installs matching files with protected key modes"

setup_root
run_worker --once
json=$(run_worker --status --json)
assert_eq "$(printf '%s' "$json" | wc -l)" 0
case "$json" in
	'{'*'}') ;;
	*) fail "status JSON is not a single object: $json" ;;
esac
printf '%s' "$json" | grep -q '"enabled":true,' || fail "enabled is not an unquoted boolean: $json"
printf '%s' "$json" | grep -q '"state":"valid"' || fail "state missing from status JSON: $json"
for field in last_check last_success last_renewal; do
	printf '%s' "$json" | grep -q "\"$field\":[0-9]" || fail "$field is not an unquoted number: $json"
done
for field in message fqdn expiry action version; do
	printf '%s' "$json" | grep -q "\"$field\":\"" || fail "$field missing from status JSON: $json"
done
write_config 0
printf '%s' "$(run_worker --status --json)" | grep -q '"enabled":false,' || fail "disabled config did not report enabled:false"
pass "--status --json emits the single-line object the WebUI RPC decodes"

setup_root
make_cert "$ROOT/tmp/other" 90 other.test-tail.ts.net
MOCK_KEY="$ROOT/tmp/other.key"
export MOCK_KEY
printf old-cert >"$ROOT/etc/nginx/nginx.cer"
printf old-key >"$ROOT/etc/nginx/nginx.key"
if run_worker --once; then fail "mismatched key unexpectedly succeeded"; fi
assert_eq "$(cat "$ROOT/etc/nginx/nginx.cer")" old-cert
assert_eq "$(cat "$ROOT/etc/nginx/nginx.key")" old-key
assert_eq "$(status_value state)" error
pass "mismatched requested key is rejected before live files change"

setup_root
make_cert "$ROOT/tmp/wrong-host" 90 other.test-tail.ts.net
MOCK_CERT="$ROOT/tmp/wrong-host.crt"
MOCK_KEY="$ROOT/tmp/wrong-host.key"
export MOCK_CERT MOCK_KEY
printf old-cert >"$ROOT/etc/nginx/nginx.cer"
printf old-key >"$ROOT/etc/nginx/nginx.key"
if run_worker --once; then fail "wrong-host certificate unexpectedly succeeded"; fi
assert_eq "$(cat "$ROOT/etc/nginx/nginx.cer")" old-cert
assert_eq "$(cat "$ROOT/etc/nginx/nginx.key")" old-key
assert_eq "$(status_value state)" error
pass "trusted certificate for a different hostname is rejected before activation"

setup_root
mkdir "$ROOT/tmp/gl-tailscale-cert.lock"
printf '%s\n' "$$" >"$ROOT/tmp/gl-tailscale-cert.lock/pid"
if run_worker --once; then fail "overlapping run unexpectedly succeeded"; else rc=$?; fi
assert_eq "$rc" 75
assert_absent "$ROOT/tmp/request-count"
pass "atomic lock prevents overlapping runs"

setup_root
mkdir "$ROOT/tmp/gl-tailscale-cert.lock"
printf '999999\n' >"$ROOT/tmp/gl-tailscale-cert.lock/pid"
run_worker --once
assert_absent "$ROOT/tmp/gl-tailscale-cert.lock"
assert_eq "$(status_value state)" valid
pass "abandoned lock is recovered safely"

setup_root
make_cert "$ROOT/tmp/old" 90
install_live_pair "$ROOT/tmp/old"
old_hash=$(sha256sum "$ROOT/etc/nginx/nginx.cer")
touch "$ROOT/tmp/nginx-reload-fail"
if run_worker --once --force; then fail "activation failure unexpectedly succeeded"; fi
assert_eq "$(sha256sum "$ROOT/etc/nginx/nginx.cer")" "$old_hash"
assert_eq "$(status_value action)" rollback
pass "nginx activation failure restores all previous certificate files"

setup_root
cp "$ROOT/tmp/generated.crt" "$ROOT/etc/nginx/nginx.cer"
cp "$ROOT/tmp/generated.key" "$ROOT/etc/nginx/nginx.key"
run_worker --once
assert_file "$ROOT/etc/uhttpd.crt"
assert_file "$ROOT/etc/uhttpd.key"
assert_absent "$ROOT/tmp/request-count"
pass "partial installation is repaired from a valid pair"

setup_root
make_cert "$ROOT/tmp/old" 90
install_live_pair "$ROOT/tmp/old"
old_hash=$(sha256sum "$ROOT/etc/uhttpd.crt")
touch "$ROOT/tmp/uhttpd-restart-fail"
if run_worker --once --force; then fail "uHTTPd activation failure unexpectedly succeeded"; fi
assert_eq "$(sha256sum "$ROOT/etc/uhttpd.crt")" "$old_hash"
assert_eq "$(status_value action)" rollback
pass "uHTTPd activation failure rolls nginx and uHTTPd files back"

setup_root
install_live_pair "$ROOT/tmp/generated"
GL_TAILSCALE_CERT_ROOT="$ROOT" \
GL_TAILSCALE_CERT_OPENSSL=/usr/bin/openssl \
GL_TAILSCALE_CERT_WATCH_INTERVAL=1 \
GL_TAILSCALE_CERT_REAL_SLEEP=1 \
PATH="$ROOT/mockbin:$PATH" \
	"$WORKER" --daemon &
daemon_pid=$!
# The daemon waits on a real one-second clock and then runs a full validation
# pass, so these ceilings depend on how loaded the machine is. Both loops exit
# as soon as their condition holds; a generous ceiling therefore costs a healthy
# run nothing and only bounds how long a genuine failure takes to report. A
# busy CI runner has already exceeded the previous eight-second repair ceiling.
startup_polls=400 # 20 seconds at 0.05s per poll
repair_polls=800  # 40 seconds at 0.05s per poll
waited=0
while [ "$(status_value state 2>/dev/null)" != "valid" ] && [ "$waited" -lt "$startup_polls" ]; do
	/bin/sleep 0.05
	waited=$((waited + 1))
done
[ "$waited" -lt "$startup_polls" ] || { kill "$daemon_pid" 2>/dev/null || true; fail "watchdog daemon did not complete its initial check"; }
printf fallback >"$ROOT/etc/nginx/nginx.cer"
printf fallback >"$ROOT/etc/nginx/nginx.key"
waited=0

while [ "$waited" -lt "$repair_polls" ]; do
	if cmp -s "$ROOT/etc/nginx/nginx.cer" "$ROOT/etc/uhttpd.crt" &&
	   [ "$(status_value action 2>/dev/null)" = "repair" ]; then
		break
	fi
	/bin/sleep 0.05
	waited=$((waited + 1))
done
kill "$daemon_pid" 2>/dev/null || true
wait "$daemon_pid" 2>/dev/null || true
[ "$waited" -lt "$repair_polls" ] || fail "watchdog did not repair externally changed nginx files"
cmp -s "$ROOT/etc/nginx/nginx.key" "$ROOT/etc/uhttpd.key" || fail "watchdog repair key mismatch"
assert_absent "$ROOT/tmp/request-count"
assert_eq "$(status_value action)" repair
pass "daemon watchdog repairs external certificate changes without a request"

echo "1..$TESTS"
