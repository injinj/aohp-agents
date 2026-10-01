# shared helpers for install/*.sh
export DEBIAN_FRONTEND=noninteractive
log() { printf '\033[1;32m[%s]\033[0m %s\n' "${INSTALLER:-install}" "$*"; }
need_node() { command -v node >/dev/null 2>&1 || { log "node missing — install Node 24 (official tarball)"; curl -fsSL https://nodejs.org/dist/v24.21.0/node-v24.21.0-linux-$(uname -m | sed 's/aarch64/arm64/;s/x86_64/x64/').tar.xz | tar -xJ -C /usr/local --strip-components=1; }; }
npm_g() { # npm_g <pkg> [version]: install/upgrade a global npm package without --jitless
  local want="$1${2:+@$2}"; NODE_OPTIONS= npm install -g --no-fund --no-audit "$want" 2>&1 | tail -1; }
