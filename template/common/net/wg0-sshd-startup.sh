#!/bin/bash
# wg0-sshd-startup.sh — keep a WireGuard tunnel (wg0) and an sshd bound to it alive inside an
# AOHP agent container. Idempotent; safe to run every few minutes (or as a containerd service with
# --loop N). Does nothing destructive when wg0.conf is absent (exit 3, status written).
#
#   wg0-sshd-startup.sh            one pass
#   wg0-sshd-startup.sh --loop 300 repeat every 300 s (for: aohp sandbox svc-start <env> -i net-watchdog -C "...")
#   wg0-sshd-startup.sh --status   print the last status json and exit
#
# What one pass does:
#   1. wg-quick up wg0 if the interface is not up; if that fails, cycle it once (down, up).
#   2. Android has no usable "main" routing table from inside the container (traffic follows per-network
#      tables selected by ip rules), so every AllowedIPs subnet of wg0.conf must have an ip rule pointing at
#      table $WG_TABLE (default 51820, == wg-quick's default fwmark table). If a rule is missing, cycle the
#      tunnel; if it is still missing afterwards (wg0.conf without PostUp rules), add route + rule directly.
#   3. sshd: mkdir /run/sshd, ssh-keygen -A (host keys), sshd -t (config check), start
#      "sshd -E /var/log/sshd.log" if no live pid in /run/sshd.pid. Not started unless $SSHD_CONF exists.
#   4. Write status json to $STATUS_FILE: lastRunAt, exitCode, repaired, handshakeAgeSec (from
#      "wg show wg0 latest-handshakes"; null when no handshake yet), sshdPid, message.
#
# Requirements in the template: wireguard-tools (wg, wg-quick), iproute2, openssh-server. wg0.conf is NOT shipped;
# the user/bootstrap puts it at /etc/wireguard/wg0.conf (mode 600) and copies the sshd drop-in from
# /opt/aohp-agents/net/10-aohp.conf.template to /etc/ssh/sshd_config.d/10-aohp.conf with ListenAddress filled in.
# No LD_PRELOAD shim is needed on images with the aohp sepolicy netlink_audit_socket rule (LineageOS build-4+);
# on older images export SSHD_LD_PRELOAD=/usr/local/lib/aohp/libnoaudit.so before running.
set -u
WG_IF=${WG_IF:-wg0}
WG_CONF=${WG_CONF:-/etc/wireguard/$WG_IF.conf}
WG_TABLE=${WG_TABLE:-51820}
RULE_PREF_BASE=${RULE_PREF_BASE:-9000}
SSHD_CONF=${SSHD_CONF:-/etc/ssh/sshd_config.d/10-aohp.conf}
SSHD_LOG=${SSHD_LOG:-/var/log/sshd.log}
SSHD_PID_FILE=${SSHD_PID_FILE:-/run/sshd.pid}
STATUS_DIR=${STATUS_DIR:-/var/run/aohp-cron}
STATUS_FILE=${STATUS_FILE:-$STATUS_DIR/net-watchdog.json}
SSHD_LD_PRELOAD=${SSHD_LD_PRELOAD:-}
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

log(){ echo "[$(date '+%F %T')] wg0-sshd: $*" >&2; }

json_str(){ # escape a string for json
  local s=$1; s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/ }; printf '"%s"' "$s"
}

write_status(){ # exitCode repaired handshakeAgeSec sshdPid message
  mkdir -p "$STATUS_DIR" 2>/dev/null
  local hs=$3; [ -z "$hs" ] && hs=null
  local pid=$4; [ -z "$pid" ] && pid=null
  local rep=$2; [ "$rep" = 1 ] && rep=true || rep=false
  printf '{"lastRunAt":"%s","exitCode":%d,"repaired":%s,"handshakeAgeSec":%s,"sshdPid":%s,"message":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$rep" "$hs" "$pid" "$(json_str "$5")" > "$STATUS_FILE.tmp" \
    && mv -f "$STATUS_FILE.tmp" "$STATUS_FILE"
}

wg_is_up(){ ip link show "$WG_IF" >/dev/null 2>&1 && wg show "$WG_IF" >/dev/null 2>&1; }

wg_cycle(){ log "cycling $WG_IF"; wg-quick down "$WG_IF" >/dev/null 2>&1 || true; sleep 1; wg-quick up "$WG_IF"; }

allowed_subnets(){ # every AllowedIPs entry of wg0.conf except default routes
  sed -n 's/^[[:space:]]*AllowedIPs[[:space:]]*=[[:space:]]*//p' "$WG_CONF" | tr ',' '\n' | tr -d ' \t' \
    | grep -v -e '^$' -e '^0\.0\.0\.0/0$' -e '^::/0$'
}

rule_present(){ # subnet
  ip rule show 2>/dev/null | grep -q -E "to $1 lookup ($WG_TABLE|table $WG_TABLE)\b"
}

ensure_rules(){ # returns 0 if all present, 1 if something was added, 2 on failure
  local rc=0 i=0 s
  while read -r s; do
    [ -z "$s" ] && continue
    if ! rule_present "$s"; then
      log "adding route+rule for $s -> table $WG_TABLE"
      ip route replace "$s" dev "$WG_IF" table "$WG_TABLE" || rc=2
      ip rule add pref $((RULE_PREF_BASE + i)) to "$s" lookup "$WG_TABLE" || rc=2
      [ $rc -eq 0 ] && rc=1
    fi
    i=$((i+1))
  done < <(allowed_subnets)
  return $rc
}

rules_missing(){ # 0 if any AllowedIPs subnet lacks its rule
  local s
  while read -r s; do [ -n "$s" ] && ! rule_present "$s" && return 0; done < <(allowed_subnets)
  return 1
}

handshake_age(){ # seconds since newest handshake, empty if none
  local now newest=0 t
  now=$(date +%s)
  while read -r _ t; do [ -n "$t" ] && [ "$t" -gt "$newest" ] 2>/dev/null && newest=$t; done < <(wg show "$WG_IF" latest-handshakes 2>/dev/null)
  [ "$newest" -gt 0 ] && echo $((now - newest))
}

sshd_pid(){ local p; p=$(cat "$SSHD_PID_FILE" 2>/dev/null) && [ -n "$p" ] && kill -0 "$p" 2>/dev/null && echo "$p"; }

ensure_sshd(){ # returns 0 running, 1 started, 2 failed/skipped
  local sshd; sshd=$(command -v sshd 2>/dev/null) || { log "sshd not installed"; return 2; }
  [ -r "$SSHD_CONF" ] || { log "no $SSHD_CONF - sshd not managed"; return 2; }
  local p; p=$(sshd_pid) && { echo "$p"; return 0; }
  mkdir -p /run/sshd && chmod 755 /run/sshd
  ssh-keygen -A >/dev/null 2>&1 || log "ssh-keygen -A failed"
  if ! "$sshd" -t 2>>"$SSHD_LOG"; then log "sshd -t failed (see $SSHD_LOG)"; return 2; fi
  if [ -n "$SSHD_LD_PRELOAD" ]; then LD_PRELOAD=$SSHD_LD_PRELOAD "$sshd" -E "$SSHD_LOG"; else "$sshd" -E "$SSHD_LOG"; fi \
    || { log "sshd failed to start"; return 2; }
  sleep 1
  p=$(sshd_pid) || { log "sshd exited right after start (see $SSHD_LOG)"; return 2; }
  echo "$p"; return 1
}

one_pass(){
  local repaired=0 msg="" rc=0 hs="" spid=""
  if [ ! -r "$WG_CONF" ]; then
    write_status 3 0 "" "" "no $WG_CONF (tunnel not configured)"; return 3
  fi
  command -v wg-quick >/dev/null 2>&1 || { write_status 4 0 "" "" "wireguard-tools missing"; return 4; }
  if ! wg_is_up; then
    log "$WG_IF down - bringing up"
    if wg-quick up "$WG_IF"; then msg="wg up;"; repaired=1
    elif wg_cycle; then msg="wg up after cycle;"; repaired=1
    else msg="wg-quick up failed;"; rc=1; fi
  fi
  if wg_is_up && rules_missing; then
    log "ip rule(s) for AllowedIPs missing -> cycle"
    if wg_cycle; then repaired=1; fi
    if rules_missing; then
      ensure_rules; case $? in 1) msg="$msg rules re-added;"; repaired=1;; 2) msg="$msg rule add failed;"; rc=1;; esac
    else msg="$msg rules restored by cycle;"; fi
  fi
  wg_is_up && hs=$(handshake_age)
  spid=$(ensure_sshd); case $? in 0) msg="$msg sshd running";; 1) msg="$msg sshd started"; repaired=1;; 2) msg="$msg sshd not running"; [ -r "$SSHD_CONF" ] && rc=1;; esac
  [ -z "$msg" ] && msg="ok"
  write_status $rc $repaired "$hs" "$spid" "$msg"
  return $rc
}

case "${1:-}" in
  --status) cat "$STATUS_FILE" 2>/dev/null || { echo '{"message":"never run"}'; exit 1; }; exit 0;;
  --loop) n=${2:-300}; log "loop every $n s"; while :; do one_pass; sleep "$n"; done;;
  -h|--help) sed -n '2,25p' "$0"; exit 0;;
  "") one_pass;;
  *) echo "unknown argument: $1" >&2; exit 2;;
esac
