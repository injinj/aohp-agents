#!/bin/bash
# Install/upgrade OpenClaw and the secrets-aware launcher wrapper.
set -euo pipefail; INSTALLER=openclaw; . "$(dirname "$0")/_lib.sh"
need_node
VER=${OPENCLAW_VERSION:-latest}
if [ -x /usr/local/bin/openclaw.real ]; then cur=$(NODE_OPTIONS= /usr/local/bin/openclaw.real --version 2>/dev/null | awk '{print $2}'); else cur=""; fi
if [ -z "$cur" ] || [ "$VER" != latest -a "$cur" != "$VER" ] || [ "${OPENCLAW_UPGRADE:-0}" = 1 ]; then
  log "npm install -g openclaw@$VER"; npm_g openclaw "$VER"
  [ -L /usr/local/bin/openclaw -o ! -f /usr/local/bin/openclaw.real ] && mv -f /usr/local/bin/openclaw /usr/local/bin/openclaw.real
else log "openclaw $cur present"; fi
[ -f /usr/local/bin/openclaw.real ] || { f=$(readlink -f /usr/local/bin/openclaw); mv -f "$f" /usr/local/bin/openclaw.real 2>/dev/null || true; }
log "launcher wrapper -> /usr/local/bin/openclaw"
# Single source of truth for the wrapper: install/openclaw-wrapper.sh (also baked into the rootfs templates, see template/).
install -m 755 "$(dirname "$0")/openclaw-wrapper.sh" /usr/local/bin/openclaw
mkdir -p "${OPENCLAW_HOME:-$HOME/.openclaw}/workspace" /tmp/openclaw; chmod 700 /tmp/openclaw
log "$(openclaw --version 2>/dev/null | head -1)"
