#!/bin/bash
# Install the AOHP unit files and the systemctl/journalctl shims into this container. Idempotent;
# run at template build (agent-layer.sh) and by aohp-update / aohp-bootstrap on existing envs.
# Units: /opt/aohp-agents/units/*.service|*.timer -> /etc/aohp/system/ (supervised by aohp-containerd,
# see docs/units.md). Enabled by default: openclaw-gateway.service only. Existing enable symlinks and
# user-edited copies (/etc/aohp/system/<name>.local marker) are left alone.
set -euo pipefail
SRC=${AOHP_AGENTS_DIR:-/opt/aohp-agents}
SYS=/etc/aohp/system
mkdir -p "$SYS/aohp.target.wants"
for f in "$SRC"/units/*.service "$SRC"/units/*.timer; do
  n=$(basename "$f")
  if [ -e "$SYS/$n.local" ]; then echo "[units] $n: kept local copy"; continue; fi
  install -m 644 "$f" "$SYS/$n"
done
# default enablement (only once, so a user's later disable sticks across updates)
if [ ! -e "$SYS/.enabled-once" ]; then
  ln -sf ../openclaw-gateway.service "$SYS/aohp.target.wants/openclaw-gateway.service"
  touch "$SYS/.enabled-once"
fi
install -m 755 "$SRC/bin/systemctl" "$SRC/bin/journalctl" /usr/local/bin/
install -m 755 "$SRC/net/openclaw-watchdog.sh" /usr/local/bin/openclaw-watchdog.sh
echo "[units] installed: $(ls "$SYS" | grep -E '\.(service|timer)$' | tr '\n' ' ')"
echo "[units] enabled: $(ls "$SYS/aohp.target.wants" | tr '\n' ' ')"
