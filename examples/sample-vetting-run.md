# Sample vetting run

Real transcript from vetting
[`anthropics/skills`](https://github.com/anthropics/skills), specifically
`skills/slack-gif-creator`, inside the built `skill-quarantine` sandbox. Repo
cloned with `git clone --depth 50 https://github.com/anthropics/skills.git`.

## Scanner output (verbatim excerpts)

**gitleaks** (`gitleaks detect --source skills/slack-gif-creator --no-git -v`):
```
2:28AM INF scanned ~43697 bytes (43.70 KB) in 102ms
2:28AM INF no leaks found
```

**semgrep** (`semgrep --config p/security-audit --metrics=off skills/slack-gif-creator`):
```
✅ Scan completed successfully.
 • Findings: 0 (0 blocking)
 • Rules run: 79
 • Targets scanned: 7
Ran 79 rules on 7 files: 0 findings.
```

**pip-audit** (`pip-audit --disable-pip --no-deps -r requirements.txt`):
```
ERROR:pip_audit._cli:requirement pillow is not pinned to an exact version: pillow>=10.0.0 (from RequirementLine(line_number=1, line='pillow>=10.0.0', filename=PosixPath('requirements.txt')))
```
`--disable-pip` refuses unpinned requirements files — common, not itself a
red flag. Reported as "not checked" below rather than a clean scan.

**npm audit**: not applicable — no `package.json`.

## Final report

```
## Verdict: SAFE
Confidence: high
Commit scanned: 8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4

### What it does
A knowledge + utility skill for building Slack-compatible animated GIFs:
local PIL/imageio/numpy code to compose frames, apply easing/animation
math, and validate output against Slack's size/dimension/color limits.
No network access, no external services.

### How to use it
Install as a Claude Code skill; invoke by asking for a Slack-ready
animated GIF. SKILL.md documents its Python API (GIFBuilder, validators,
easing, frame_composer helpers).

### Scanner results
- gitleaks: clean — no leaks found
- semgrep (p/security-audit): clean — 79 rules run on 7 files, 0 findings
- npm audit: not applicable (no package.json / JS dependencies)
- pip-audit: not checked — requirements.txt uses version ranges
  (e.g. pillow>=10.0.0), not exact pins, so offline pip-audit can't run
  without installing packages, which scanning must not do

### Manual findings
- Network calls: none found (matches stated purpose — pure local GIF
  generation). Imports are limited to math, typing, pathlib, numpy, PIL,
  imageio.v3 — no socket/urllib/requests/subprocess/os.system/eval/exec/
  base64/pickle anywhere in core/
- File access: only the user-supplied GIF path, via PIL
  (core/validators.py:39, Image.open(gif_path)); no credential/secret file
  access; no writes outside the working directory
- Obfuscation/eval/base64: none found
- Curl-pipe-to-shell: none found
- Hooks/settings/cron/shell profile modification: none found
- Hidden/bidirectional unicode: none found

### Reputation
First-party skill from Anthropic's official `anthropics/skills` GitHub
org — not a third-party author. Active repo, organic commit history, open
community PR/issue queue. Independent (non-Anthropic) security review of
this specific repo is thin — most search results are the project's own
docs or third-party "awesome list" aggregations. Noted as a data gap, not
a red flag, given first-party provenance and fully readable source.

### Not checked
- pip-audit: requirements.txt not pinned to exact versions (see above)
- Full repo history beyond the shallow clone depth (--depth 50)
- Independent third-party security audits of this specific skill: none found

### Install command
git clone https://github.com/anthropics/skills.git && \
  cd skills && git checkout 8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4
(then copy or symlink skills/slack-gif-creator into ~/.claude/skills/,
pinned to this commit)
```

The interactive "wait for yes, then sandbox-install" step was not exercised
in this walkthrough — verdict is SAFE and no further install was requested.
