# Disposable sandbox for vetting third-party Claude Code skills: no host FS
# access beyond whatever run-vetter.sh bind-mounts (./scratch only, never
# $HOME), non-root user, scanning tools pre-installed and version-pinned.
# Not a boundary against kernel exploits (see README "What this does NOT
# do") — it's meant to keep opportunistic malicious skills (curl-pipe-to-
# shell, exfil on import, etc.) off your real machine.

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

# gitleaks — pinned to an exact version, never "latest", so scans stay
# reproducible. Current: v8.30.1 (Anthropic verified against
# https://github.com/gitleaks/gitleaks/releases at build-author time).
#
# To bump: check the releases page for the new version and asset filename
# (naming has changed across majors before), update GITLEAKS_VERSION, then
# `./run-vetter.sh --rebuild` and confirm `gitleaks version` matches.
ARG GITLEAKS_VERSION=8.30.1
ARG GITLEAKS_ARCHIVE=gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz
ARG GITLEAKS_URL=https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${GITLEAKS_ARCHIVE}

RUN curl -fsSL -o /tmp/gitleaks.tar.gz "${GITLEAKS_URL}" \
    && tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks \
    && chmod +x /usr/local/bin/gitleaks \
    && rm /tmp/gitleaks.tar.gz \
    && gitleaks version

# semgrep + pip-audit in an isolated venv, so the scanning toolchain can
# never be shadowed by a skill's own dependencies.
ENV SCANNER_VENV=/opt/scanner-venv
RUN python3 -m venv "${SCANNER_VENV}" \
    && "${SCANNER_VENV}/bin/pip" install --no-cache-dir --upgrade pip \
    && "${SCANNER_VENV}/bin/pip" install --no-cache-dir semgrep pip-audit

# Symlinked (not PATH=) because Debian's /etc/profile overwrites PATH on
# login shells, which would otherwise silently drop these on `claude`/
# run-vetter.sh's `bash -lc ...` launch.
RUN ln -s "${SCANNER_VENV}/bin/semgrep" /usr/local/bin/semgrep \
    && ln -s "${SCANNER_VENV}/bin/pip-audit" /usr/local/bin/pip-audit

# Claude Code CLI itself (trusted, first-party) — separate from the "never
# install the target skill's own code" rule applied during scanning.
RUN npm install -g @anthropic-ai/claude-code \
    && claude --version

# Non-root user. /work is where target skills get cloned/tested — separate
# from ./scratch's mount point for agent config + login state, and wiped on
# every container exit (--rm).
RUN useradd --create-home --shell /bin/bash vetter \
    && mkdir -p /work \
    && chown -R vetter:vetter /work

USER vetter
WORKDIR /home/vetter

ENTRYPOINT ["/bin/bash", "-lc"]
CMD ["claude"]
