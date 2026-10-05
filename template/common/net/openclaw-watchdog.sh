#!/bin/sh
# openclaw-watchdog.sh — one health-check pass for the OpenClaw gateway running as the AOHP unit
# openclaw-gateway.service (see /opt/aohp-agents/docs/units.md). Modeled on chex's
# /usr/local/sbin/openclaw-watchdog.sh: curl $OPENCLAW_HEALTH_URL; count consecutive failures in
# $STATE_FILE; at $OPENCLAW_WATCHDOG_FAILS failures restart the unit (systemctl shim -> aohp unit
# restart) and reset the counter. Exit 0 always (a oneshot that "fails" would only add noise); the
# decision is logged to the unit log (journalctl -u openclaw-watchdog).
# Does nothing when the gateway unit is not active (nothing to watch), or when it is in auto-restart
# (containerd is already handling it).
URL=${OPENCLAW_HEALTH_URL:-http://127.0.0.1:18789/health}
MAXF=${OPENCLAW_WATCHDOG_FAILS:-3}
UNIT=${OPENCLAW_WATCHDOG_UNIT:-openclaw-gateway}
STATE_FILE=${STATE_FILE:-/var/run/aohp-cron/openclaw-watchdog.fails}
mkdir -p "$(dirname "$STATE_FILE")"
log() { echo "[$(date '+%F %T')] openclaw-watchdog: $*"; }

state=$(systemctl is-active "$UNIT" 2>/dev/null || true)
case "$state" in
  active) ;;
  activating) log "$UNIT is activating (auto-restart), leaving it to containerd"; exit 0 ;;
  *) log "$UNIT is $state, nothing to watch"; echo 0 > "$STATE_FILE"; exit 0 ;;
esac

if curl -fsS -m 10 -o /dev/null "$URL"; then
  echo 0 > "$STATE_FILE"
  exit 0
fi
fails=$(( $(cat "$STATE_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$fails" > "$STATE_FILE"
log "health check failed ($fails/$MAXF): $URL"
if [ "$fails" -ge "$MAXF" ]; then
  log "restarting $UNIT"
  systemctl restart "$UNIT" || log "restart failed"
  echo 0 > "$STATE_FILE"
fi
exit 0
