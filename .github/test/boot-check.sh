#!/bin/bash
# Gate on whether the immich systemd services are running correctly — wait up to WAIT for each to go
# active and emit its startup log lines, then print a verdict and exit non-zero on failure (the
# release gate). prepare.sh already started them; this never starts anything. Runs IN PLACE as root,
# requires systemd, reads journald — ephemeral testbed only, never a user's live install.
#
# The units are Type=exec, so `systemctl is-active` goes true the instant the process execs — long
# before the app is ready (ML does a uv dependency sync on first boot). Readiness is the expected
# startup log lines landing in journald, waited on up to WAIT.
#
# Gating policy: every service must become active and emit its expected startup log lines.
#
# Usage:  boot-check.sh [--out FILE]    # --out: append the result table to FILE (default: stdout)
# Env:    WAIT   seconds to wait for readiness (default 300; ML's first uv sync is slow)
set -u
WAIT="${WAIT:-300}"
OUT="${OUT:-/dev/stdout}"
info()  { printf '\n========== %s ==========\n' "$1"; }
error() { local code="$1"; shift; echo "$*" >&2; exit "$code"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) error 2 "unknown option: $1" ;;
  esac
done
rc=0; svc_fail=0; log_fail=0; rows=()

[ -d /run/systemd/system ] || error 4 "systemd is not running (/run/systemd/system missing)"

SERVICES=(immich-machine-learning immich-server)

# Readiness signals; track immich's output, update across major immich versions.
server_msgs=("Immich Server is listening on" "Immich Microservices is running" "Machine learning server became healthy")
ml_msgs=("Application startup complete")

has_msg() { journalctl -u "$1.service" --no-pager 2>/dev/null | grep -qF "$2"; }
all_ready() {
  local m
  for m in "${ml_msgs[@]}";     do has_msg immich-machine-learning "$m" || return 1; done
  for m in "${server_msgs[@]}"; do has_msg immich-server           "$m" || return 1; done
}

info "Wait for readiness — all startup log lines present (timeout ${WAIT}s)"
i=0; ready=0
while [ "$i" -lt "$WAIT" ]; do
  dead=""
  for s in "${SERVICES[@]}"; do systemctl is-failed --quiet "$s.service" && dead="$s"; done
  [ -n "$dead" ] && { echo "  $dead entered failed state"; break; }
  if all_ready; then ready=1; break; fi
  sleep 2; i=$((i+2))
done
echo "  readiness after ~${i}s: $([ "$ready" = 1 ] && echo yes || echo 'NO (timeout/failed)')"

info "Service active state"
for s in "${SERVICES[@]}"; do
  if systemctl is-active --quiet "$s.service"; then mark="✅"; echo "SVC OK $s active"
  else mark="❌"; echo "SVC FAIL $s active"; rc=1; svc_fail=$((svc_fail+1)); fi
  rows+=("| \`$s\` | active | $mark |")
done

info "Startup log messages"
check_logs() {
  local svc="$1"; shift; local m mark
  for m in "$@"; do
    if has_msg "$svc" "$m"; then mark="✅"; echo "LOG OK $svc \"$m\""
    else mark="❌"; echo "LOG FAIL $svc \"$m\""; rc=1; log_fail=$((log_fail+1)); fi
    rows+=("| \`$svc\` | log: \`$m\` | $mark |")
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

info "Summary"
if [ "$rc" -eq 0 ]; then
  verdict="✅ boot: all services active, all startup log lines present"
else
  verdict="❌ boot: $svc_fail service(s) not active, $log_fail expected log line(s) missing"
fi
[ "$OUT" = /dev/stdout ] || mkdir -p "$(dirname "$OUT")"
{
  echo ""
  echo "| Service | Assertion | Result |"
  echo "|---|---|---|"
  printf '%s\n' "${rows[@]}"
  echo ""
  echo "$verdict"
} >> "$OUT"

[ "$rc" -eq 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit "$rc"
