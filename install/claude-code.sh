#!/bin/bash
set -euo pipefail; INSTALLER=claude-code; . "$(dirname "$0")/_lib.sh"; need_node
log "npm install -g @anthropic-ai/claude-code"; npm_g @anthropic-ai/claude-code
log "$(claude --version 2>/dev/null | head -1). Login: 'claude' -> opens a URL; open it in the phone browser, the localhost callback lands in this container."
