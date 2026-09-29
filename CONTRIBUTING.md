# Contributing

## Add a new scanner

1. Add it to the `Dockerfile`, pinned to an exact version (see the gitleaks
   comment for the pattern: pin, document how to bump, verify a checksum).
2. Add a step in `.claude/agents/skill-vetter.md` under "Run scanners": the
   exact command, what it catches, and instruction to treat findings as
   leads, not verdicts.
3. Make it report as "not checked" (with reason) if it errors or is
   missing — never silently skipped.
4. Add it to the "Scanner results" line in the output format.

## Adjust the manual-review flag list

The flag list in `.claude/agents/skill-vetter.md` ("Manually review every
file") is the core of what this tool catches beyond scanners. New flags need
a one-line reason (what attack pattern it catches) and, ideally, whether it
belongs in the automatic-BLOCK list or the manual-judgment list.

## Testing a change

Never run a real or suspected-malicious skill outside the sandbox.

1. Run `./run-vetter.sh` against a small, real, trusted skill and confirm
   the verdict/report still make sense with your change.
2. If you changed detection logic, also test against a known-malicious
   sample (e.g. from a public malicious-package research dataset) — only
   inside the sandbox, never installed outside `/work`. Confirm the agent
   still refuses to execute it and BLOCKs on any injection attempt.
3. Dockerfile changes: `./run-vetter.sh --rebuild` and confirm it builds
   (CI checks this too).

## Style

- `.claude/agents/skill-vetter.md` is a prompt: be precise and explicit
  ("never X"), not vague ("be careful with X") — it's the only thing between
  a user and a malicious skill's instructions.
- Shell scripts: POSIX-compatible bash, `set -euo pipefail`.
- Dockerfile: every third-party tool version-pinned, with a bump comment.
- No dependencies "just in case" — every tool added is one more thing to
  keep patched.

## Review

PRs touching the Dockerfile/`run-vetter.sh` are reviewed for sandbox
integrity (no host mounts beyond `./scratch`, capabilities still dropped, no
execution of scanned code). PRs touching the agent instructions are reviewed
for whether they weaken the untrusted-data rule, the never-auto-install
rule, or the BLOCK-on-injection rule — these are the tool's load-bearing
guarantees. CI (`docker build`) must pass.
