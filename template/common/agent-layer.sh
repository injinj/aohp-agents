#!/bin/bash
# Agent layer shared by all rootfs templates (runs inside the image at build time; needs bash, git, node, curl).
#   - clones aohp-agents to /opt/aohp-agents (aohp-bootstrap / aohp-secrets / aohp-update / age-pass on PATH)
#   - installs OpenClaw via install/openclaw.sh (npm install -g openclaw@OPENCLAW_VERSION + the launcher wrapper
#     install/openclaw-wrapper.sh: strips --jitless, exports SHELL=/bin/bash, loads secrets)
#   - keyless default config /root/.openclaw/openclaw.json and the AOHP workspace (AGENTS.md + skills)
#   - /root/.bashrc PATH/LANG/TERM, hostname aohp-dev
# The aohp CLI and /opt/aohp-skills are COPY'd in by the Dockerfile before this runs (built in template/aohp-cli.Dockerfile).
set -euo pipefail
OPENCLAW_VERSION=${OPENCLAW_VERSION:-2026.9.6}
AOHP_AGENTS_REPO=${AOHP_AGENTS_REPO:-https://github.com/injinj/aohp-agents.git}
AOHP_AGENTS_REF=${AOHP_AGENTS_REF:-main}
P=/tmp/provision
log() { echo "[agent-layer] $*"; }

# /etc/resolv.conf and /etc/hostname are NOT written here: podman bind-mounts both into every RUN step, so the writes
# would not land in the image layer. build-template.sh injects them into the exported rootfs instead.

log "aohp-agents ($AOHP_AGENTS_REF) -> /opt/aohp-agents"
rm -rf /opt/aohp-agents
git clone -q --branch "$AOHP_AGENTS_REF" "$AOHP_AGENTS_REPO" /opt/aohp-agents
install -m 755 /opt/aohp-agents/bin/aohp-update /opt/aohp-agents/bin/aohp-secrets /opt/aohp-agents/bin/age-pass /usr/local/bin/
install -m 755 /opt/aohp-agents/bootstrap.sh /usr/local/bin/aohp-bootstrap
# Units (systemd-subset service files supervised by aohp-containerd, docs/units.md) + the systemctl/journalctl
# shims (/usr/local/bin precedes /usr/bin, so they shadow Debian's real systemctl, which cannot work here anyway).
# Only openclaw-gateway.service is enabled; wg0/sshd/watchdogs stay disabled until the user enables them.
bash /opt/aohp-agents/install/units.sh
# Network helpers (inactive until the user configures wg0.conf + the sshd drop-in): the watchdog script on PATH,
# sources stay in /opt/aohp-agents/net/ (-> template/common/net/). Never enabled by the template itself.
install -m 755 /opt/aohp-agents/net/wg0-sshd-startup.sh /usr/local/bin/wg0-sshd-startup.sh
test -r /opt/aohp-agents/net/10-aohp.conf.template

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
aohp --help | grep -q '^ *unit' || { echo "aohp CLI lacks the 'unit' subcommand (need injinj/aohp feat/units)" >&2; exit 1; }
test "$(command -v systemctl)" = /usr/local/bin/systemctl || { echo "systemctl shim not first on PATH" >&2; exit 1; }
test -L /etc/aohp/system/aohp.target.wants/openclaw-gateway.service
aohp --version 2>/dev/null || true
aohp-bootstrap --help | head -2
gh --version | head -1; age --version
wg --version 2>/dev/null | head -1 || echo "wg: not installed?"; command -v sshd >/dev/null || { echo "sshd missing" >&2; exit 1; }
rm -f /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub   # Debian postinst generates them; each container must make its own (ssh-keygen -A in the watchdog)
test -z "$(ls /etc/ssh/ssh_host_*_key 2>/dev/null)" || { echo "host keys still present" >&2; exit 1; }
gcc --version | head -1; python3 -V; git --version; jq --version

printf 'export PATH=/root/.cargo/bin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\nexport LANG=C.UTF-8 TERM=xterm-256color\n' > /root/.bashrc
