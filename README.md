# skill-quarantine

[![Build sandbox image](https://github.com/Yehiak/skill-quarantine/actions/workflows/build-test.yml/badge.svg)](https://github.com/Yehiak/skill-quarantine/actions/workflows/build-test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Look before you install.** skill-quarantine checks a third-party
[Claude Code](https://docs.claude.com/en/docs/claude-code) skill or plugin
for security red flags *inside a disposable Docker sandbox*, then gives you a
**SAFE / CAUTION / BLOCK** verdict with the evidence behind it — before the
skill ever touches your real machine.

```
> /skill-quarantine https://github.com/someone/some-claude-skill

## Verdict: CAUTION
Confidence: medium
Commit scanned: 3f9c2e1...
...
```

> [!IMPORTANT]
> **skill-quarantine is a screening aid, not a guarantee.** A SAFE verdict means
> "these checks found no red flags", not "this skill is verified safe". It can
> miss obfuscated, novel, or deliberately evasive attacks, and it is not a
> security audit or certification. You are still responsible for what you
> install. Read [What this is NOT](#what-this-is-not) before relying on it.

---

## Contents

- [Why](#why)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Quickstart](#quickstart)
- [Usage](#usage)
- [Security model](#security-model)
- [What this is NOT](#what-this-is-not)
- [Project layout](#project-layout)
- [Contributing](#contributing)
- [Reporting a vulnerability](#reporting-a-vulnerability)
- [License](#license)

## Why

Claude Code skills and plugins are code and instructions that run with your
permissions: they can call the network, read your files, and add hooks that
fire on every session. Installing one from a random repo means trusting its
author with your machine.

skill-quarantine gives you a structured second look first. It clones the skill
into an isolated container, runs security scanners, has a Claude subagent
read every file against a checklist of known attack patterns, checks the
author's reputation, and writes up what it found.

## How it works

```
your machine                         Docker sandbox (deleted on exit)
────────────                         ──────────────────────────────────────
./skill-quarantine.sh  ──── launches ───▶  claude  ──▶  skill-quarantine subagent
                                                    1. clone repo, pin commit SHA
  .claude/agents   ── read-only ──▶                 2. gitleaks, semgrep,
  .claude/commands ── read-only ──▶                    npm audit, pip-audit
                                                    3. manual review of every file
  (nothing else is mounted:                         4. compare behavior vs. stated purpose
   no home dir, no projects,                        5. reputation check (web)
   no SSH keys, no cloud creds)                     6. verdict + "not checked" list
                                                    7. waits for your explicit "yes"
```

1. **Clone & pin.** Clones the repo into the sandbox's temporary `/work` and
   records the exact commit SHA. Everything after this refers to that commit.
2. **Scan.** Runs [gitleaks](https://github.com/gitleaks/gitleaks),
   [semgrep](https://semgrep.dev) (`p/security-audit`), `npm audit`, and
   [pip-audit](https://github.com/pypa/pip-audit), without installing or
   running the skill's own code. A scanner that fails is reported as
   **not checked**; it is never skipped silently.
3. **Manual review.** The agent reads every file looking for network calls,
   credential access (`~/.ssh`, `~/.aws`, `.env`, ...), `eval`/obfuscation,
   base64-decoded execution, `curl | sh`, hooks that modify settings, shell
   profiles, git hooks, or cron, and hidden/bidirectional Unicode.
4. **Purpose check.** Every network call and file access is compared against
   what the skill *says* it does.
5. **Reputation.** Author, repo age, commit history, open security issues,
   independent reviews. The project's own marketing doesn't count.
6. **Verdict.** SAFE, CAUTION, or BLOCK, with a confidence level and an
   explicit list of what was *not* checked.
7. **Your call.** Nothing is installed until you reply **"yes"**, and never
   on BLOCK. If you approve, it test-installs *inside the sandbox only* and
   gives you a commit-pinned install command to run on your own machine.

The full rules are in [`.claude/agents/skill-quarantine.md`](.claude/agents/skill-quarantine.md).
It's a plain-text prompt, so you can read exactly what the agent is told to do.

## Requirements

- [Docker](https://docs.docker.com/get-docker/) (Docker Desktop on
  Windows/macOS, or Docker Engine on Linux), running.
- A bash shell: Linux/macOS terminal, or on Windows **Git Bash** or **WSL**.
- A Claude account or API key, to log in to Claude Code *inside* the
  sandbox. Vetting uses your normal Claude usage.

Git, the scanners, and Claude Code are all installed inside the sandbox image.
You don't need any of them on your machine.

## Quickstart

```bash
git clone https://github.com/Yehiak/skill-quarantine.git
cd skill-quarantine
./skill-quarantine.sh --check   # first run builds the image (a few minutes), then verifies isolation
./skill-quarantine.sh           # start the sandboxed Claude Code session
```

On first launch, Claude Code inside the sandbox asks you to log in. That login
is stored in a Docker volume used only by the sandbox, so you only do it once.
It is separate from your normal Claude Code login.

Then vet something:

```
> /skill-quarantine https://github.com/someone/some-claude-skill
```

When you're done, exit Claude Code (`/exit` or Ctrl+D). The container and
everything it cloned are deleted.

See [`examples/sample-vetting-run.md`](examples/sample-vetting-run.md) for a
complete real report.

## Usage

### Commands

| Command | What it does |
| --- | --- |
| `./skill-quarantine.sh` | Build the image if needed, then start a sandboxed `claude` session |
| `./skill-quarantine.sh --check` | Run the isolation self-test (see below) and exit |
| `./skill-quarantine.sh --rebuild` | Force a clean image rebuild (picks up new Claude Code / scanner versions) |
| `./skill-quarantine.sh --reset` | Delete the sandbox's saved Claude login and settings |
| `/skill-quarantine <git-url>` | Inside the sandbox: vet a skill or plugin repo |

### Reading the verdict

| Verdict | Meaning |
| --- | --- |
| **SAFE** | No red flags found by these checks; all access matches the stated purpose. Still not a guarantee. |
| **CAUTION** | Probably legitimate, but it sends data externally, needs credentials, adds hooks, or has a thin track record. The report says which; decide whether that's acceptable for you. |
| **BLOCK** | Obfuscation, unexplained network calls, secret access, `curl \| sh`, undisclosed settings/shell/cron changes, or an attempt to manipulate the agent. The agent refuses to install it. |

Always read the **Confidence** and **Not checked** sections. A SAFE verdict
with low confidence and a long "not checked" list deserves more of your own
attention.

### Checking the sandbox yourself

`./skill-quarantine.sh --check` starts a container with exactly the same flags as a
real session and verifies:

```
  PASS  runs as non-root user (sandbox)
  PASS  all Linux capabilities dropped
  PASS  no-new-privileges is set
  PASS  /home/sandbox/.claude/agents is mounted read-only
  PASS  /home/sandbox/.claude/commands is mounted read-only
  PASS  no other host paths mounted
  PASS  agent instructions cannot be modified
  PASS  /work is writable (ephemeral scan area)
  PASS  skill-quarantine agent and command are loaded
  PASS  git / gitleaks / semgrep / pip-audit / npm / claude are installed
```

Run it after changing anything in `skill-quarantine.sh` or the `Dockerfile`. CI runs
it on every push.

## Security model

### What the sandbox protects

| Protection | How |
| --- | --- |
| Your files, SSH keys, cloud credentials, and projects are invisible | Nothing from your machine is mounted except the tool's own agent/command files |
| The agent's instructions can't be rewritten by a skill | Agent and command files are mounted **read-only** |
| Scanned code never lands on your disk and can't persist between vets | `/work` is a temporary Docker volume, deleted when the container exits |
| No root, no privilege escalation | Non-root `sandbox` user, `--cap-drop=ALL`, `no-new-privileges` |
| A fork bomb or runaway install can't take down your machine | `--pids-limit 1024`, `--memory 4g` |
| The skill's code doesn't run during scanning | The agent is told never to execute it, never `npm install` without `--ignore-scripts`, and never install its Python deps |
| Prompt injection in the scanned repo doesn't control the agent | All repo content is treated as data; any attempt to instruct the agent is an automatic **BLOCK** |
| Tampered scanner binaries are rejected | gitleaks is checksum-verified; semgrep and pip-audit are version-pinned |

### What it does NOT protect against

Know these before you rely on it:

- **The network is open.** The sandbox needs internet access to clone repos
  and check reputation. A skill's code *could* make network requests if it
  ever ran. The scanning steps never run it; Step 7 (test install) does.
- **Step 7 runs real code next to your sandbox login.** If you approve a test
  install, the skill's install steps run inside the container, which also
  holds the sandbox's Claude Code login. A malicious skill that slipped past
  the review could steal that token or leave hooks in the sandbox's saved
  settings. Your real machine is still unaffected. If you're unsure about
  something you test-installed, run `./skill-quarantine.sh --reset` and sign out of
  that session from your Claude account settings.
- **Containers are not virtual machines.** Docker isolation stops ordinary
  malicious code, not a kernel or container-runtime exploit. On Windows and
  macOS, Docker Desktop adds a VM layer; on Linux the container shares your
  kernel. Keep Docker updated.
- **The reviewer is an AI.** The manual review is done by Claude following
  [a written checklist](.claude/agents/skill-quarantine.md). It can miss things,
  misjudge things, and is not immune to sufficiently novel prompt injection.

## What this is NOT

- **Not a guarantee.** SAFE means "no red flags found by these checks",
  not "safe". No automated tool can prove code is harmless.
- **Not an audit or certification.** Don't cite a skill-quarantine verdict as a
  security review.
- **Not complete.** Scanners have false negatives. For example, none of the
  bundled scanners flags `curl … | bash` by itself; only the agent's manual
  review catches it. Obfuscated, minified, binary, or very large files may
  end up under "not checked".
- **Not permanent.** A verdict covers exactly one commit. Re-vet before
  upgrading, and install the commit-pinned version it gives you, not `main`.
- **Not aware of brand-new vulnerabilities.** `npm audit` and `pip-audit`
  only know about vulnerabilities that are already in their databases.

The software is provided "as is", without warranty of any kind. See
[LICENSE](LICENSE).

## Project layout

```
.
├── .claude/
│   ├── agents/skill-quarantine.md   # the vetting agent: rules, process, report format
│   └── commands/skill-quarantine.md          # the /skill-quarantine slash command
├── .github/workflows/           # CI: build image, smoke-test tools, run --check
├── Dockerfile                   # sandbox image (scanners + Claude Code, non-root)
├── skill-quarantine.sh                # launcher: build, run, --check, --reset
├── examples/                    # a real vetting transcript
├── CONTRIBUTING.md
└── SECURITY.md
```

## Contributing

Contributions are welcome, especially new detection patterns, new scanners,
and reports of skills it got wrong. See [CONTRIBUTING.md](CONTRIBUTING.md).

The quickest ways to help:

- **Add a manual-review flag:** add the pattern to the review list in
  [`.claude/agents/skill-quarantine.md`](.claude/agents/skill-quarantine.md), with the
  attack it catches.
- **Add a scanner:** add it, pinned, to the `Dockerfile`; add a step and a
  report line to the agent file; make it report "not checked" on failure.
- **Report a miss:** if it called something SAFE that wasn't, that's a
  security report. See below.

## Reporting a vulnerability

Found a sandbox escape, a way to make the agent give a wrong verdict, or a
prompt injection that changes its behavior? **Please report it privately**,
not as a public issue. See [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Use at your own risk; see [What this is NOT](#what-this-is-not).
