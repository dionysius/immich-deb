#!/bin/bash
# Gate on whether the immich systemd services are running correctly — each must be active and answer
# its ping endpoint; print a verdict and exit non-zero on failure (the release gate). prepare.sh already
# started them; this never starts anything. Runs IN PLACE as root, requires systemd, reads journald —
# ephemeral testbed only, never a user's live install.
#
# The units are Type=notify, so the start jobs in prepare.sh only return once the services are ready
# (or failed); `active` here means ready.
#
# Usage:  boot-check.sh [--out FILE]    # --out: append the result table to FILE (default: stdout)
set -u
OUT="${OUT:-/dev/stdout}"
info()  { printf '\n========== %s ==========\n' "$1"; }
error() { local code="$1"; shift; echo "$*" >&2; exit "$code"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) error 2 "unknown option: $1" ;;
  esac
done
rc=0; svc_fail=0; ping_fail=0; rows=()

[ -d /run/systemd/system ] || error 4 "systemd is not running (/run/systemd/system missing)"

SERVICES=(immich-machine-learning immich-server)

# Ping endpoints, from the packaged default IMMICH_HOST/IMMICH_PORT.
declare -A PING=(
  [immich-machine-learning]="http://127.0.0.1:3003/ping"
  [immich-server]="http://127.0.0.1:2283/api/server/ping"
)

info "Service active state"
for s in "${SERVICES[@]}"; do
  if systemctl is-active --quiet "$s.service"; then mark="✅"; echo "SVC OK $s active"
  else mark="❌"; echo "SVC FAIL $s $(systemctl is-active "$s.service")"; rc=1; svc_fail=$((svc_fail+1)); fi
  rows+=("| \`$s\` | active | $mark |")
done

info "Ping endpoints"
for s in "${SERVICES[@]}"; do
  url="${PING[$s]}"
  # ML's worker may still be booting behind gunicorn's bound socket; the request waits for it.
  if curl -fsS --max-time 60 "$url" >/dev/null; then mark="✅"; echo "PING OK $s $url"
  else mark="❌"; echo "PING FAIL $s $url"; rc=1; ping_fail=$((ping_fail+1)); fi
  rows+=("| \`$s\` | ping: \`$url\` | $mark |")
done

if [ "$rc" != 0 ]; then
  for s in "${SERVICES[@]}"; do
    echo "--- status + last 60 journal lines: $s ---"
    systemctl status "$s.service" --no-pager -l 2>&1 | head -20 || true
    journalctl -u "$s.service" --no-pager -n 60 2>&1 || true
  done
fi

info "Summary"
if [ "$rc" -eq 0 ]; then
  verdict="✅ boot: all services active and answering ping"
else
  verdict="❌ boot: $svc_fail service(s) not active, $ping_fail ping(s) failed"
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
