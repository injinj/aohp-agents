#!/bin/bash
# aohp-bootstrap — provision an AOHP container from a git config repo.
# usage: aohp-bootstrap <user>/<repo> [--secrets age|keystore|paste] [--token-file F] [--age-identity F] [--passphrase-file F] [--branch B]
set -euo pipefail
# Whole script lives in main() so 'curl ... | bash -s -- ...' parses it completely before any command can read stdin.
main() {
AGENTS_REPO=${AOHP_AGENTS_REPO:-https://github.com/injinj/aohp-agents.git}
AGENTS_DIR=${AOHP_AGENTS_DIR:-/opt/aohp-agents}
OC_DIR=${OPENCLAW_HOME:-$HOME/.openclaw}
repo=""; method=""; tokfile=""; ageid=""; branch=""; ppf=""
while [ $# -gt 0 ]; do case "$1" in
  --secrets) method=$2; shift 2;; --token-file) tokfile=$2; shift 2;; --age-identity) ageid=$2; shift 2;;
  --branch) branch=$2; shift 2;; --passphrase-file) ppf=$2; shift 2;; -h|--help) sed -n '2,3p' "$0"; exit 0;; *) repo=$1; shift;; esac; done
[ -n "$repo" ] || { echo "usage: aohp-bootstrap <user>/<repo> [--secrets age|keystore|paste]"; exit 2; }
log() { printf '\033[1;36m[bootstrap]\033[0m %s\n' "$*"; }

log "base packages"
export DEBIAN_FRONTEND=noninteractive
need=""; for p in git gh age curl ca-certificates python3; do dpkg -s $p >/dev/null 2>&1 || need="$need $p"; done
if [ -n "$need" ]; then apt-get update -qq; apt-get install -y -qq $need >/dev/null; fi

log "GitHub auth"
if [ -n "$tokfile" ]; then gh auth login --with-token < "$tokfile"
elif ! gh auth status >/dev/null 2>&1; then
  echo "  A one-time code will be shown; enter it at https://github.com/login/device from any browser."
  if [ -r /dev/tty ]; then gh auth login --hostname github.com --git-protocol https --web < /dev/tty
  else gh auth login --hostname github.com --git-protocol https --web; fi
fi
gh auth setup-git >/dev/null

log "agents repo -> $AGENTS_DIR"
if [ -d "$AGENTS_DIR/.git" ]; then git -C "$AGENTS_DIR" pull -q --ff-only; else git clone -q "$AGENTS_REPO" "$AGENTS_DIR"; fi
install -m 755 "$AGENTS_DIR/bin/aohp-update" "$AGENTS_DIR/bin/aohp-secrets" "$AGENTS_DIR/bin/age-pass" /usr/local/bin/
install -m 755 "$AGENTS_DIR/bootstrap.sh" /usr/local/bin/aohp-bootstrap

log "config repo $repo -> $OC_DIR"
mkdir -p "$OC_DIR"; chmod 700 "$OC_DIR"
url="https://github.com/$repo.git"
if [ ! -d "$OC_DIR/.git" ]; then
  git -C "$OC_DIR" init -q
  git -C "$OC_DIR" remote add origin "$url"
else
  git -C "$OC_DIR" remote set-url origin "$url"
fi
git -C "$OC_DIR" fetch -q origin
b=$branch
if [ -z "$b" ]; then b=$(git -C "$OC_DIR" ls-remote --symref origin HEAD 2>/dev/null | sed -n 's|^ref: refs/heads/\([^[:space:]]*\).*|\1|p' | head -1 || true); fi
b=${b:-main}
# dotfiles-style: tracked files win, untracked runtime state is kept
git -C "$OC_DIR" checkout -q -f -B "$b" "origin/$b"
git -C "$OC_DIR" branch -q --set-upstream-to="origin/$b" "$b"
[ -f "$OC_DIR/openclaw.json" ] && chmod 600 "$OC_DIR/openclaw.json"

log "secrets"
aohp-secrets setup ${method:+--method "$method"} ${ageid:+--age-identity "$ageid"} ${ppf:+--passphrase-file "$ppf"}

agents=openclaw; [ -f "$OC_DIR/agents" ] && agents=$(grep -vE '^\s*(#|$)' "$OC_DIR/agents" | tr '\n' ' ')
for a in $agents; do log "install/$a.sh"; bash "$AGENTS_DIR/install/$a.sh"; done
log "done. secrets method: $(cat "$OC_DIR/.secrets-method" 2>/dev/null); agents: $agents"
}
main "$@"
