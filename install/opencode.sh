#!/bin/bash
set -euo pipefail; INSTALLER=opencode; . "$(dirname "$0")/_lib.sh"
log "official installer"; curl -fsSL https://opencode.ai/install | bash 2>&1 | tail -2
log "$(opencode --version 2>/dev/null | head -1)"
