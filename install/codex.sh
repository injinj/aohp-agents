#!/bin/bash
set -euo pipefail; INSTALLER=codex; . "$(dirname "$0")/_lib.sh"; need_node
log "npm install -g @openai/codex"; npm_g @openai/codex
log "$(codex --version 2>/dev/null | head -1). Login: 'codex login' (ChatGPT OAuth; callback on localhost:1455 reaches this container from the phone browser)."
