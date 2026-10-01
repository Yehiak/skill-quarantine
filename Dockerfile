# Disposable sandbox for vetting third-party Claude Code skills.
#
# Isolation comes from how skill-quarantine.sh launches this image: non-root user,
# all capabilities dropped, no-new-privileges, an ephemeral /work that is
# deleted on exit, and NO host directories mounted except the tool's own
# agent/command files (read-only). This is meant to keep opportunistic
# malicious skills (curl-pipe-to-shell, exfil on import, persistence hooks)
# off your real machine. It is not a boundary against kernel/container-
# runtime exploits — see README "Security model".

FROM node:22-bookworm

# git: clone the target skill. python3/venv: run semgrep/pip-audit (isolated
# venv below, never system Python). curl/ca-certificates: fetch gitleaks.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    python3 \
    python3-venv \
    python3-pip \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# gitleaks — pinned to an exact version and verified against a pinned
# SHA-256, so a tampered or swapped release asset fails the build.
#
# To bump: pick the new version on
# https://github.com/gitleaks/gitleaks/releases, copy the linux_x64 line from
# that release's gitleaks_<version>_checksums.txt into GITLEAKS_SHA256, update
# GITLEAKS_VERSION, then `./skill-quarantine.sh --rebuild` and `./skill-quarantine.sh --check`.
ARG GITLEAKS_VERSION=8.30.1
ARG GITLEAKS_SHA256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
ARG GITLEAKS_ARCHIVE=gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz
ARG GITLEAKS_URL=https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${GITLEAKS_ARCHIVE}

RUN curl -fsSL -o /tmp/gitleaks.tar.gz "${GITLEAKS_URL}" \
    && echo "${GITLEAKS_SHA256}  /tmp/gitleaks.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks \
    && chmod +x /usr/local/bin/gitleaks \
    && rm /tmp/gitleaks.tar.gz \
    && gitleaks version

# semgrep + pip-audit in an isolated venv, so the scanning toolchain can
# never be shadowed by a skill's own dependencies. Pinned for reproducible
# scans; bump deliberately.
ARG SEMGREP_VERSION=1.178.0
ARG PIP_AUDIT_VERSION=2.10.1
ENV SCANNER_VENV=/opt/scanner-venv
RUN python3 -m venv "${SCANNER_VENV}" \
    && "${SCANNER_VENV}/bin/pip" install --no-cache-dir --upgrade pip \
    && "${SCANNER_VENV}/bin/pip" install --no-cache-dir \
        "semgrep==${SEMGREP_VERSION}" \
        "pip-audit==${PIP_AUDIT_VERSION}"

# Symlinked (not PATH=) because Debian's /etc/profile overwrites PATH on
# login shells, which would otherwise silently drop these on the
# `bash -lc ...` entrypoint.
RUN ln -s "${SCANNER_VENV}/bin/semgrep" /usr/local/bin/semgrep \
    && ln -s "${SCANNER_VENV}/bin/pip-audit" /usr/local/bin/pip-audit

# Claude Code CLI itself (trusted, first-party) — separate from the "never
# install the target skill's own code" rule applied during scanning.
# Defaults to the latest release; pass --build-arg CLAUDE_CODE_VERSION=x.y.z
# to pin.
ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && claude --version

# Keep ALL Claude Code state (login, settings, .claude.json) under one
# directory, so skill-quarantine.sh can persist just the sandbox's login in a named
# volume and nothing else.
ENV CLAUDE_CONFIG_DIR=/home/sandbox/.claude

# Non-root user. /work is where target skills get cloned and tested;
# skill-quarantine.sh mounts an anonymous volume there that Docker deletes when
# the container exits.
RUN useradd --create-home --shell /bin/bash sandbox \
    && mkdir -p /work /home/sandbox/.claude \
    && chown -R sandbox:sandbox /work /home/sandbox/.claude

USER sandbox
WORKDIR /work

ENTRYPOINT ["/bin/bash", "-lc"]
CMD ["claude"]
