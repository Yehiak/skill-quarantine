# skill-vetter

Sandboxed vetting for third-party Claude Code skills/plugins. Point it at a
repo; a subagent clones it into a locked-down, disposable Docker container,
runs scanners and manual checks, searches its reputation, and gives you a
SAFE / CAUTION / BLOCK verdict — before anything touches your real machine.

## What this does NOT do

- SAFE means "no red flags found by these checks," not "verified safe." It's
  not an audit, guarantee, or certification.
- It can miss obfuscated, novel, or sufficiently clever attacks.
- It's a risk-reduction tool, not a guarantee — you remain responsible for
  what you install on your own machine.
- The sandbox reduces but doesn't eliminate risk during scanning (see
  [Limitations](#limitations) — the container still has network access).

## Prerequisites

[Docker](https://www.docker.com/). Everything else (git, scanners, Claude
Code) lives inside the sandbox image, not your host.

## Quickstart

```bash
git clone https://github.com/<you>/skill-vetter.git
cd skill-vetter
./run-vetter.sh              # builds the image on first run
./run-vetter.sh --rebuild    # force a fresh build
```

This drops you into a `claude` session inside the container with the
`skill-vetter` subagent loaded:

```
> /vet https://github.com/someone/some-claude-skill
```

You'll get a report ending in a verdict. Nothing installs or runs beyond
scanning until you reply "yes" — and never at all on BLOCK. See
[`examples/sample-vetting-run.md`](examples/sample-vetting-run.md) for a
full transcript.

## How it works

1. Clone into `/work`, record the exact commit SHA, read the skill's stated
   purpose.
2. Run scanners: gitleaks, semgrep (`p/security-audit`), npm audit,
   pip-audit — without ever installing the skill's own code. Failures are
   reported as "not checked," never skipped silently.
3. Manually review every file: network calls, credential access,
   obfuscation, curl-pipe-to-shell, hooks, hidden unicode.
4. Check every network/file access against the skill's stated purpose.
5. Check reputation: author, repo age, history, independent review.
6. Verdict (SAFE/CAUTION/BLOCK) with confidence and a "not checked" list.
7. Wait for your explicit "yes," then (if not BLOCK) test-install inside
   `/work` only, and hand you the install command for your own machine,
   pinned to that commit.

Full rules: [`.claude/agents/skill-vetter.md`](.claude/agents/skill-vetter.md)
— it's a prompt, not a black box.

## Limitations

- Scanners have false negatives/positives; the agent verifies findings
  manually but can still miss things.
- The sandbox has network access (needed for cloning and reputation
  lookups) — it protects your host filesystem and credentials, not the
  network. For zero-network-trust scanning, run with `--network=none` and
  accept that dependency-download checks will fail.
- Prompt-injection resistance isn't absolute against a sufficiently novel
  attack.
- A verdict is a snapshot of one commit — re-vet before upgrading.
- Dependency scanning is only as good as the npm audit/pip-audit databases.

## Extending

- New scanner: add it to the `Dockerfile` (pinned), add a step in
  `.claude/agents/skill-vetter.md`, add it to the report format. See
  [CONTRIBUTING.md](CONTRIBUTING.md).
- New manual-review flag: add it to the manual-review list in
  `.claude/agents/skill-vetter.md` with the attack pattern it catches.

## License

[MIT](LICENSE)

## Security

Found a bypass or sandbox escape? See [SECURITY.md](SECURITY.md) — report
privately, not as a public issue.
