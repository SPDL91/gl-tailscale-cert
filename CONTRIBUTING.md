# Contributing

Keep changes inside the package's existing ownership boundaries. Routing, firewall, DNS, WAN, listener, Tailscale startup, and other-plugin changes are out of scope.

Before submitting a change:

1. run `sh tests/run.sh`, including the LAN-recovery suite;
2. run the BusyBox ash, OpenResty, and browser suites described in `docs/TESTING.md` when relevant;
3. build and inspect both package formats;
4. use only synthetic `*.test-tail.ts.net` names and generated throwaway certificates in tests;
5. never attach router backups, private keys, auth keys, real tailnet names, or credential-bearing logs.

Changes to the optional ts-fix adapter require an updated pinned fixture, exact-once tests, all four nginx states, and a documented compatible upstream version/commit.

## Releasing

Never build release artifacts from a working tree. A Windows checkout once
produced CRLF line endings in the packaged lifecycle scripts, which made the
package fail to install with "not found" and exit 127. CI builds every release
on Linux from a clean checkout.

1. Update `PKG_VERSION` in `Makefile`. Nothing else carries the version; the
   workflows and tests read it from there.
2. Add a `## <version> - <date>` entry to `CHANGELOG.md`. The release notes are
   generated from that section.
3. Merge to `main` and wait for the test workflow to pass.
4. Tag and push:

   ```sh
   git tag v<version>
   git push origin v<version>
   ```

The release workflow reruns the full suite, refuses to publish if the tag and
`PKG_VERSION` disagree or the changelog entry is missing, rejects any artifact
carrying a carriage return, then publishes both artifacts with their checksums.
