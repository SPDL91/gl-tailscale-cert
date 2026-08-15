# Contributing

Keep changes inside the package's existing ownership boundaries. Routing, firewall, DNS, WAN, listener, Tailscale startup, and other-plugin changes are out of scope.

Before submitting a change:

1. run `sh tests/run.sh`, including the LAN-recovery suite;
2. run the BusyBox ash, OpenResty, and browser suites described in `docs/TESTING.md` when relevant;
3. build and inspect both package formats;
4. use only synthetic `*.test-tail.ts.net` names and generated throwaway certificates in tests;
5. never attach router backups, private keys, auth keys, real tailnet names, or credential-bearing logs.

Changes to the optional ts-fix adapter require an updated pinned fixture, exact-once tests, all four nginx states, and a documented compatible upstream version/commit.
