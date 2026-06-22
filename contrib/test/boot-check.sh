#!/bin/bash
# Boot the immich systemd services and assert they come up healthy. Runs IN PLACE as root and
# requires systemd (PID 1). Intended for a throwaway testbed (it starts services and reads
# journald) — not meant to be run against a user's live install.
#
# The units are Type=exec, so `systemctl is-active` goes true the instant the process execs — long
# before the app has finished starting (ML even does a uv dependency sync on first boot). So we wait
# on the actual readiness signal: the expected startup log lines appearing in journald (up to WAIT),
# then assert active state + log lines.
#
# Emits machine-parseable lines consumed by run.sh:
#   SVC <OK|FAIL> <service> active
#   LOG <OK|FAIL> <service> "<expected message>"
#
# Env:  WAIT   seconds to wait for readiness (default 300; ML's first uv sync is slow)
set -u
WAIT="${WAIT:-300}"
line() { printf '\n========== %s ==========\n' "$1"; }
rc=0

[ -d /run/systemd/system ] || { echo "FATAL: systemd is not running (PID 1 is not systemd)"; exit 4; }

SERVICES=(immich-machine-learning immich-server)   # ML first so the server can reach it

# Expected startup log lines per service. These track immich's output and may need updating across
# major immich versions; a miss is a hard failure.
server_msgs=("Immich Server is listening on" "Immich Microservices is running" "Machine learning server became healthy")
ml_msgs=("Application startup complete")

has_msg() { journalctl -u "$1.service" --no-pager 2>/dev/null | grep -qF "$2"; }
all_ready() {
  local m
  for m in "${ml_msgs[@]}";     do has_msg immich-machine-learning "$m" || return 1; done
  for m in "${server_msgs[@]}"; do has_msg immich-server           "$m" || return 1; done
}

line "Start services"
systemctl daemon-reload || true
for s in "${SERVICES[@]}"; do systemctl start "$s.service" || true; done

line "Wait for readiness — all startup log lines present (timeout ${WAIT}s)"
i=0; ready=0
while [ "$i" -lt "$WAIT" ]; do
  dead=""
  for s in "${SERVICES[@]}"; do systemctl is-failed --quiet "$s.service" && dead="$s"; done
  [ -n "$dead" ] && { echo "  $dead entered failed state"; break; }
  if all_ready; then ready=1; break; fi
  sleep 2; i=$((i+2))
done
echo "  readiness after ~${i}s: $([ "$ready" = 1 ] && echo yes || echo 'NO (timeout/failed)')"

line "Service active state"
for s in "${SERVICES[@]}"; do
  if systemctl is-active --quiet "$s.service"; then echo "SVC OK $s active"
  else echo "SVC FAIL $s active"; rc=1; fi
done

line "Startup log messages"
check_logs() {
  local svc="$1"; shift; local m
  for m in "$@"; do
    if has_msg "$svc" "$m"; then echo "LOG OK $svc \"$m\""; else echo "LOG FAIL $svc \"$m\""; rc=1; fi
  done
}
check_logs immich-server "${server_msgs[@]}"
check_logs immich-machine-learning "${ml_msgs[@]}"

if [ "$rc" != 0 ]; then
  for s in "${SERVICES[@]}"; do
    echo "--- status + last 60 journal lines: $s ---"
    systemctl status "$s.service" --no-pager -l 2>&1 | head -20 || true
    journalctl -u "$s.service" --no-pager -n 60 2>&1 || true
  done
fi

line "DONE (rc=$rc)"
exit "$rc"
