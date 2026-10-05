#!/bin/bash
# Agent layer shared by all rootfs templates (runs inside the image at build time; needs bash, git, node, curl).
#   - clones aohp-agents to /opt/aohp-agents (aohp-bootstrap / aohp-secrets / aohp-update / age-pass on PATH)
#   - installs OpenClaw via install/openclaw.sh (npm install -g openclaw@OPENCLAW_VERSION + the launcher wrapper
#     install/openclaw-wrapper.sh: strips --jitless, exports SHELL=/bin/bash, loads secrets)
#   - keyless default config /root/.openclaw/openclaw.json and the AOHP workspace (AGENTS.md + skills)
#   - /root/.bashrc PATH/LANG/TERM, hostname aohp-dev, resolv.conf
# The aohp CLI and /opt/aohp-skills are COPY'd in by the Dockerfile before this runs (built in template/aohp-cli.Dockerfile).
set -euo pipefail
OPENCLAW_VERSION=${OPENCLAW_VERSION:-2026.9.6}
AOHP_AGENTS_REPO=${AOHP_AGENTS_REPO:-https://github.com/injinj/aohp-agents.git}
AOHP_AGENTS_REF=${AOHP_AGENTS_REF:-main}
P=/tmp/provision
log() { echo "[agent-layer] $*"; }

echo aohp-dev > /etc/hostname
rm -f /etc/resolv.conf && printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf

log "aohp-agents ($AOHP_AGENTS_REF) -> /opt/aohp-agents"
rm -rf /opt/aohp-agents
git clone -q --branch "$AOHP_AGENTS_REF" "$AOHP_AGENTS_REPO" /opt/aohp-agents
install -m 755 /opt/aohp-agents/bin/aohp-update /opt/aohp-agents/bin/aohp-secrets /opt/aohp-agents/bin/age-pass /usr/local/bin/
install -m 755 /opt/aohp-agents/bootstrap.sh /usr/local/bin/aohp-bootstrap

log "openclaw $OPENCLAW_VERSION (npm; slow under qemu for arm64)"
export NODE_OPTIONS=
OPENCLAW_VERSION=$OPENCLAW_VERSION bash /opt/aohp-agents/install/openclaw.sh
test -x /usr/local/bin/openclaw.real
grep -q 'SHELL=/bin/bash' /usr/local/bin/openclaw

log "default config + workspace"
mkdir -p /root/.openclaw/workspace/skills /tmp/openclaw
chmod 700 /root/.openclaw /tmp/openclaw
install -m 600 $P/openclaw-default.json /root/.openclaw/openclaw.json
cp -r $P/workspace/. /root/.openclaw/workspace/
cp -r /opt/aohp-skills/. /root/.openclaw/workspace/skills/     # same skills the Alpine template ships; identical to the aohp repo's skills/

log "versions"
NODE_OPTIONS="--jitless" openclaw --version
aohp --help | grep -q '^ *secret' || { echo "aohp CLI lacks the 'secret' subcommand" >&2; exit 1; }
aohp --version 2>/dev/null || true
aohp-bootstrap --help | head -2
gh --version | head -1; age --version
gcc --version | head -1; python3 -V; git --version; jq --version

printf 'export PATH=/root/.cargo/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\nexport LANG=C.UTF-8 TERM=xterm-256color\n' > /root/.bashrc
