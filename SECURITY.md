# Security Policy

`homelab-infra` is infrastructure-as-code for a single self-hosted Proxmox homelab: Terraform (state on Cloudflare R2),
Ansible, and Flux CD manifests. It ships no published artifacts or binaries - the "product" is the configuration in this
repository.

## Supported versions

Only the `main` branch is supported. There are no releases, tags, or backports – fixes land on `main` and take effect on
the next `just deploy` / `just configure` run or the next Flux reconciled.

| Version  | Supported |
|----------|-----------|
| `main`   | Yes       |
| Older commits / forks | No |

## Reporting a vulnerability

**Do not open a public issue for a security problem.**

Report privately through GitHub: **[Security → Report a
vulnerability](https://github.com/kalpak44/homelab-infra/security/advisories/new)** (GitHub private vulnerability
reporting). If that form is unavailable to you, contact the maintainer directly through the
[kalpak44](https://github.com/kalpak44) GitHub profile and ask for a private channel - do not include details in a
public message.

Please include, as far as you can:

- the file(s) and line(s) involved, or the workflow / role / manifest at fault;
- what an attacker gains (e.g. secret disclosure, privilege escalation on the Proxmox node, unauthenticated access to a
  service behind the tunnel);
- the preconditions – LAN access, a fork PR, a compromised dependency, etc.;
- a proof of concept, if you have one.

### What to expect

- **Acknowledgement:** within 7 days.
- **Assessment:** within 30 days, with a fix plan or an explanation of why it is not considered a vulnerability.
- **Fix:** committed to `main`; a GitHub security advisory is published for anything that affects people who reuse this
  repo.
- **Credit:** given in the advisory unless you ask to stay anonymous.

This is a personal, unfunded project – there is no bug bounty.

## Scope

**In scope** - anything in this repository that a third party could inherit by reusing it:

- Terraform under `terraform/` - provider configuration, resource settings, R2 backend configuration.
- Ansible under `ansible/` - playbooks and roles, including certbot / TLS handling and any place a credential is
  written to disk.
- Flux CD manifests under `gitops/` - Traefik, cert-manager, External Secrets, CrowdSec, and app manifests, including
  ingress exposure and RBAC.
- GitHub Actions workflows in `.github/workflows/` and the agent workflow template shipped by
  `terraform/github/<repo>/workflows/ai-pr-agent.yml` - injection into workflow inputs, secret exfiltration,
  privilege escalation on the self-hosted runner.
- Any credential, token, or private key accidentally committed to this repo or its history. **Report this privately and
  urgently.**

**Out of scope:**

- The maintainer's live homelab hosts and services. Do not probe, scan, or attempt to access them. The `192.168.1.x`
  addresses in this repo are RFC 1918 private addresses with no meaning outside that LAN, and the hostnames under
  `*.internal` resolve only there.
- Vulnerabilities in upstream software (Proxmox, k3s, Traefik, Vault, AdGuard Home, CrowdSec, Terraform providers, …).
  Report those to their own projects; if this repo pins a version known to be vulnerable, that pin *is* in scope.
- Deliberate design choices documented in `CLAUDE.md` and `.claude/rules/` - for example the absence of a GitHub branch
  ruleset, or a self-hosted runner. If you believe one of these is exploitable in a way the notes do not account for,
  report it and say why.
- Findings that require already having root on the Proxmox node or admin on the GitHub org.