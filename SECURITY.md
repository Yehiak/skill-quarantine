# Security Policy

skill-quarantine is a best-effort community tool, not a certified security
product — see [README: What this is NOT](README.md#what-this-is-not).

## Reporting

Found a way to bypass the checks (e.g. a SAFE/CAUTION verdict on something
malicious, or a prompt-injection payload that changes the agent's behavior)
or a sandbox escape? Report it privately, not as a public issue:

- Preferred: [GitHub private vulnerability reporting](../../security/advisories/new)
- Alternative: email the maintainers (see the repo's GitHub profile)

Include reproduction steps and impact. A description or a controlled PoC is
enough — don't send a live weaponized payload.

## Response time

Best-effort, volunteer-maintained. Rough targets: acknowledgment within a
few days, initial assessment within two weeks. No SLA.

## Scope

In scope: this repo's agent instructions, Dockerfile, and scripts. Out of
scope: vulnerabilities in Docker, gitleaks, semgrep, npm/pip, or Claude Code
themselves — report those upstream, unless a bug in one of them specifically
undermines this tool's guarantees (e.g. a scanner silently failing open), in
which case we still want to know.
