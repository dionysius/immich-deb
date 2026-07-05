#!/bin/bash
# Gate on the vchord-upgrade trigger: upgrading the postgresql-<v>-vchord package must make
# immich-db-reqs' dpkg file trigger restart PostgreSQL (reloading the new shared library) and
# immich-server, so immich's `ALTER EXTENSION vchord UPDATE` succeeds with no manual intervention.
#
# Without the trigger, the old vchord.so stays mapped (it is in shared_preload_libraries) and immich
# fails with: could not find function "_vchord_rabitq4_in_wrapper" ... (SQLSTATE 42883). This test
# installs a newer vchord .deb from upstream and asserts the automatic recovery.
#
# prepare.sh already installed immich (baseline vchord) and created the extension; this never installs
# immich. Runs IN PLACE as root, requires systemd, reads journald — ephemeral testbed only.
#
# TARGET is the vchord version to upgrade to; it must be newer than the installed baseline and within
# immich's supported range (so immich actually runs the UPDATE). Bump it when immich's supported
# vchord version moves — same maintenance as boot-check.sh's readiness strings.
#
# Usage:  vchord-upgrade-check.sh [--out FILE]     # --out: append the result table to FILE
# Env:    VCHORD_TARGET  version to upgrade to (default 1.1.1)
#         VCHORD_REPO    GitHub owner/repo providing the .deb (default supervc-stack/VectorChord)
#         VCHORD_REV     debian revision of the upstream .deb (default 1)
#         DBNAME         immich database (default immich)
#         WAIT           seconds to wait for immich-server readiness (default 180)
set -u
OUT="${OUT:-/dev/stdout}"
WAIT="${WAIT:-180}"
VCHORD_TARGET="${VCHORD_TARGET:-1.1.1}"
VCHORD_REPO="${VCHORD_REPO:-supervc-stack/VectorChord}"
VCHORD_REV="${VCHORD_REV:-1}"
DBNAME="${DBNAME:-immich}"

info() { printf '\n========== %s ==========\n' "$1"; }
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

rows=(); rc=0
add_row() { rows+=("| $1 | $2 | $3 |"); }
psql_immich() { runuser -u postgres -- psql -d "$DBNAME" -tAc "$1" 2>/dev/null | tr -d '[:space:]'; }

emit() {  # emit SUMMARY_TABLE + verdict to OUT, print RESULT, exit
  local verdict="$1" result="$2" code="$3"
  [ "$OUT" = /dev/stdout ] || mkdir -p "$(dirname "$OUT")"
  {
    echo ""
    echo "**vchord upgrade trigger** (baseline → \`$VCHORD_TARGET\`)"
    echo ""
    echo "| Check | Detail | Result |"
    echo "|---|---|---|"
    printf '%s\n' "${rows[@]}"
    echo ""
    echo "$verdict"
  } >> "$OUT"
  echo "RESULT: $result"
  exit "$code"
}
skip() {  # warn (GitHub annotation) but exit 0 — the test could not run, which must not fail the job
  info "SKIP"; echo "$1"
  echo "::warning title=vchord upgrade trigger skipped::$1"
  add_row "precondition" "$1" "⚠️"; emit "⚠️ vchord upgrade trigger: skipped — $1" SKIP 0
}

[ -d /run/systemd/system ] || { echo "systemd is not running" >&2; exit 4; }
systemctl list-unit-files immich-server.service >/dev/null 2>&1 || skip "immich-server.service not installed"

# PostgreSQL major immich actually talks to (authoritative — avoids matching phantom/other-major
# vchord entries in the dpkg db), then that cluster's installed vchord baseline (strip -revision).
PGVER=$(psql_immich "SELECT current_setting('server_version_num')::int/10000")
[ -n "$PGVER" ] || skip "cannot query the PostgreSQL server (no connection to DB '$DBNAME')"
pkg="postgresql-${PGVER}-vchord"
BASE_FULL=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || true)
BASELINE=${BASE_FULL%%-*}
[ -n "$BASELINE" ] || skip "$pkg is not installed"
ARCH=$(dpkg --print-architecture)

info "Context"
echo "postgres major : $PGVER"
echo "vchord baseline: $BASELINE  (target: $VCHORD_TARGET, arch: $ARCH)"

extver=$(psql_immich "SELECT extversion FROM pg_extension WHERE extname='vchord'")
[ -n "$extver" ] || skip "vchord extension not present in DB '$DBNAME' (immich not using vchord)"
echo "extension in DB: $extver"
if dpkg --compare-versions "$BASELINE" eq "$VCHORD_TARGET"; then
  skip "target $VCHORD_TARGET is already the installed vchord version (apt baseline caught up — bump VCHORD_TARGET)"
elif dpkg --compare-versions "$BASELINE" gt "$VCHORD_TARGET"; then
  skip "installed vchord $BASELINE is newer than target $VCHORD_TARGET (bump VCHORD_TARGET)"
fi

# Download the upstream target .deb
url="https://github.com/$VCHORD_REPO/releases/download/$VCHORD_TARGET/postgresql-${PGVER}-vchord_${VCHORD_TARGET}-${VCHORD_REV}_${ARCH}.deb"
deb=$(mktemp --suffix=.deb)
info "Fetch upstream vchord $VCHORD_TARGET"
echo "$url"
ok=""
for _ in 1 2 3; do curl -fSL "$url" -o "$deb" && { ok=1; break; }; sleep 3; done
# Missing/unreachable asset: skip loudly rather than red-gate a release on upstream packaging or a
# transient network — this platform's target .deb could not be fetched.
[ -n "$ok" ] || { rm -f "$deb"; skip "could not download $pkg $VCHORD_TARGET ($url)"; }

pm_before=$(psql_immich "SELECT pg_postmaster_start_time()")
FROM=$(date '+%Y-%m-%d %H:%M:%S')

info "Upgrade vchord (dpkg -i) — the trigger must do the rest, no manual restart"
dpkg_out=$(DEBIAN_FRONTEND=noninteractive dpkg -i "$deb" 2>&1); echo "$dpkg_out"
rm -f "$deb"

info "Wait for immich-server to settle (timeout ${WAIT}s)"
i=0
while [ "$i" -lt "$WAIT" ]; do
  systemctl is-failed --quiet immich-server.service && { echo "  immich-server failed"; break; }
  journalctl -u immich-server.service --no-pager -S "$FROM" 2>/dev/null | grep -qF "Immich Server is listening on" && break
  sleep 2; i=$((i+2))
done
# let postgres finish accepting connections after its restart
for _ in $(seq 15); do runuser -u postgres -- pg_isready -q && break; sleep 1; done
pm_after=$(psql_immich "SELECT pg_postmaster_start_time()")
new_ext=$(psql_immich "SELECT extversion FROM pg_extension WHERE extname='vchord'")
jrn() { journalctl -u immich-server.service --no-pager -S "$FROM" 2>/dev/null; }

# Assertions
check() {  # name detail condition(0/1)
  if [ "$3" = 0 ]; then add_row "$1" "$2" "✅"; echo "OK   $1 — $2"
  else add_row "$1" "$2" "❌"; echo "FAIL $1 — $2"; rc=1; fi
}
grep -qF "Processing triggers for immich-db-reqs" <<<"$dpkg_out"; check "dpkg trigger fired" "Processing triggers for immich-db-reqs" $?
[ -n "$pm_before" ] && [ -n "$pm_after" ] && [ "$pm_before" != "$pm_after" ]; check "postgresql restarted" "postmaster reloaded the new library" $?
jrn | grep -qF "Updating VectorChord extension to $VCHORD_TARGET"; check "immich ran the migration" "Updating VectorChord extension to $VCHORD_TARGET" $?
jrn | grep -qE "_vchord_rabitq4_in_wrapper|could not find function"; ne=$?; [ "$ne" -ne 0 ]; check "no stale-library error" "no 42883 could-not-find-function" $?
[ "$new_ext" = "$VCHORD_TARGET" ]; check "extension updated" "vchord now $new_ext" $?
systemctl is-active --quiet immich-server.service; check "immich-server active" "service running after upgrade" $?

if [ "$rc" != 0 ]; then
  info "immich-server status + last 60 journal lines"
  systemctl status immich-server.service --no-pager -l 2>&1 | head -20 || true
  jrn | tail -60 || true
fi

if [ "$rc" -eq 0 ]; then
  emit "✅ vchord upgrade trigger: postgres + immich auto-restarted, extension at $VCHORD_TARGET, no manual step" PASS 0
else
  emit "❌ vchord upgrade trigger: automatic recovery failed (see checks above)" FAIL 1
fi
