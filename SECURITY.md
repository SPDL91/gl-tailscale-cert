# Security policy

## Supported versions

Only the latest release receives fixes. Check your version with
`gl-tailscale-cert --version`.

## Reporting a vulnerability

Report privately through
[GitHub Security Advisories](https://github.com/SPDL91/gl-tailscale-cert/security/advisories/new).
Do not open a public issue for a suspected vulnerability.

Expect an acknowledgement within seven days. This project has a single
maintainer, so a fix may take longer than the acknowledgement.

**Never include** private keys, Tailscale auth keys, your tailnet name, your
router's `*.ts.net` hostname, or unredacted router logs. A description of the
behaviour and the affected file or command is enough to start.

## Scope

The package runs as root, writes the certificate and key files both web servers
serve, and reloads those servers. Findings in these areas matter most:

- certificate or key validation that accepts material it should reject;
- the activation and rollback path leaving a web server without a usable
  certificate;
- private key material reaching a log, status file, UCI value, or the package
  itself;
- the OUI RPC or WebUI panel executing anything beyond its fixed commands;
- privilege escalation through the worker, hotplug hook, or lifecycle scripts.

Out of scope: GL.iNet firmware and its nginx/OUI stack, Tailscale itself, and
Let's Encrypt. Report those upstream. Certificate Transparency publishing your
router's DNS name is inherent to public certificate issuance, is documented in
the README, and is not a vulnerability in this package.
