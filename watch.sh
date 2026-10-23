#!/usr/bin/env bash
# ai-upgrader watcher: reports progress/blockers/stalls to a bot webhook.
# Usage: ai-upgrader-watch /path/to/repo
# Setup: cp ~/.config/ai-upgrader/watch.env.example ~/.config/ai-upgrader/watch.env and fill it.
set -u
CONF="${AI_UPGRADER_WATCH_CONF:-$HOME/.config/ai-upgrader/watch.env}"
if [ ! -f "$CONF" ]; then
  echo "ERROR: setup bot webhook: $CONF missing. Copy ${CONF}.example to $CONF and fill WEBHOOK_URL and WEBHOOK_AUTH_HEADER." >&2
  exit 2
fi
. "$CONF"
if [ -z "${WEBHOOK_URL:-}" ] || [ -z "${WEBHOOK_AUTH_HEADER:-}" ]; then
  echo "ERROR: setup bot webhook: WEBHOOK_URL and WEBHOOK_AUTH_HEADER must be set in $CONF" >&2
  exit 2
fi

REPO="${1:-.}"; U="$REPO/.upgrade"; S="$U/state.yml"
POLL="${POLL:-15}"; STALL_SEC="${STALL_SEC:-900}"; STATUS_SEC="${STATUS_SEC:-600}"
NAME="$(basename "$(cd "$REPO" && pwd)")"
LOG="$U/events.log"

get() { sed -n "s/^  $1: *//p" "$S" 2>/dev/null | head -1 | tr -d "'\""; }
esc() { sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '; }

notify() { # $1=kind $2=text
  local msg="[ai-upgrader:$NAME] $1: $2"
  echo "$(date '+%F %T') $msg" | tee -a "$LOG"
  curl -fsS -m 10 -X POST "$WEBHOOK_URL" -H 'Content-Type: application/json' \
    -H "$WEBHOOK_AUTH_HEADER" \
    -d "{\"source\":\"ai-upgrader\",\"repo\":\"$NAME\",\"kind\":\"$1\",\"text\":\"$(printf '%s' "$msg" | esc)\"}" \
    >/dev/null || echo "webhook send failed" >&2
}

last_activity() { find "$U" -type f ! -name events.log -exec stat -f %m {} + 2>/dev/null | sort -n | tail -1; }
running() { pgrep -f 'ai-upgrader' | grep -vqx "$$"; }

counts() { # accepted/total milestones from plan.yml
  local P="$U/plan.yml" n d
  n=$(grep -c '^  - id:' "$P" 2>/dev/null); d=$(grep -c '^    status: ACCEPTED' "$P" 2>/dev/null)
  echo "${d:-0}/${n:-0}"
}

[ -f "$S" ] || { echo "ERROR: no $S (run ai-upgrader plan/upgrade first)" >&2; exit 1; }
prev=""; prev_blk=""; stalled=0; died=0; last_status=$(date +%s)
notify start "watching, phase=$(get PHASE) milestone=$(get MILESTONE_ID)"
while :; do
  cur="$(get PHASE)|$(get MILESTONE_ID)|$(get MILESTONE_STATUS_VALUE)|$(get REVIEW_STATUS)"
  if [ "$cur" != "$prev" ]; then
    [ -z "$prev" ] || notify progress "phase=$(get PHASE) milestone=$(get MILESTONE_ID) status=$(get MILESTONE_STATUS_VALUE) review=$(get REVIEW_STATUS)"
    prev="$cur"
  fi
  blk="$(get CURRENT_BLOCKER)"
  if [ -n "$blk" ] && [ "$blk" != "$prev_blk" ]; then notify blocker "$blk"; fi
  prev_blk="$blk"
  [ "$(get STOP_REQUESTED)" != 1 ] || [ "$stalled" = s ] || { notify stopped "stop requested"; stalled=s; }

  case "$(get PHASE)" in
    COMPLETE*) notify done "all milestones accepted"; exit 0 ;;
  esac

  age=$(( $(date +%s) - $(last_activity) ))
  if running; then
    died=0
    if [ "$age" -gt "$STALL_SEC" ]; then
      [ "$stalled" = 1 ] || { notify stalled "no activity for ${age}s at milestone=$(get MILESTONE_ID) phase=$(get PHASE)"; stalled=1; }
    else [ "$stalled" = s ] || stalled=0; fi
  else
    [ "$died" = 1 ] || { notify died "ai-upgrader process not running (phase=$(get PHASE), blocker=${blk:-none})"; died=1; }
  fi
  now=$(date +%s)
  if [ $(( now - last_status )) -ge "$STATUS_SEC" ] && running; then
    notify status "milestones $(counts) accepted; phase=$(get PHASE) milestone=$(get MILESTONE_ID) gates fast=$(get FAST_GATE) milestone=$(get MILESTONE_GATE) review=$(get REVIEW_STATUS); last activity ${age}s ago"
    last_status=$now
  fi
  sleep "$POLL"
done
