#!/usr/bin/env bash
# In-place test orchestrator: run the boot check and/or the media probe ON this machine,
# apply the release-gating policy, print a summary, and exit non-zero if a gate fails.
#
# This is the "execution / testing / reporting" half. Getting the machine ready (installing the
# packages, the DB, the corpus) is the provisioner's job (provision.sh / the CI workflow).
#
# Usage:
#   run.sh [--corpus DIR] [--phases boot,probe] [--out DIR]
#
# Gating policy:
#   boot   - every service must become active and emit its expected startup log lines.
#   probe  - CORE image formats (jpg/png/webp/gif/avif/heic) must thumbnail, and exiftool must
#            work. Non-core formats (jxl/rw2/tiff/raw) are reported but NOT gated: their support
#            depends on the distro's libjxl/libraw/ImageMagick, not on our packaging.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORPUS="${CORPUS:-$HERE/test-assets}"
OUT="${OUT:-${TMPDIR:-/tmp}/immich-test}"
PHASES="boot,probe"

while [ $# -gt 0 ]; do
  case "$1" in
    --corpus) CORPUS="$2"; shift 2 ;;
    --phases) PHASES="$2"; shift 2 ;;
    --out)    OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$OUT"

CORE_EXTS=" jpg jpeg png webp gif avif heic "   # release-gated image formats
fail=0; warn=0
summary()  { printf '%s\n' "$*" >> "$OUT/summary.txt"; }
note()     { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
: > "$OUT/summary.txt"

run_phase() { # name -> writes $OUT/<name>.log, returns the script's rc
  local name="$1"; shift
  note "phase: $name"
  "$HERE/$name.sh" "$@" 2>&1 | tee "$OUT/$name.log"
  return "${PIPESTATUS[0]}"
}

IFS=',' read -r -a want <<<"$PHASES"
for p in "${want[@]}"; do
  case "$p" in
    boot)
      run_phase boot-check; brc=$?
      # grep -c always prints a count (0 on no match) but exits 1 then, so swallow the status
      # with `|| true` rather than `|| echo 0` (which would append a second "0").
      svc_fail=$(grep -c '^SVC FAIL' "$OUT/boot-check.log" 2>/dev/null || true); svc_fail=${svc_fail:-0}
      log_fail=$(grep -c '^LOG FAIL' "$OUT/boot-check.log" 2>/dev/null || true); log_fail=${log_fail:-0}
      if [ "$brc" -ne 0 ] || [ "$svc_fail" -gt 0 ] || [ "$log_fail" -gt 0 ]; then
        fail=1; summary "❌ boot: $svc_fail service(s) not active, $log_fail expected log line(s) missing"
      else
        summary "✅ boot: all services active, all startup log lines present"
      fi
      ;;
    probe)
      export CORPUS                 # probe.sh reads CORPUS; it writes thumbnails to its own scratch dir
      run_phase probe; prc=$?
      # evaluate thumbnail results by format class
      core_fail=0; noncore_fail=0; ok=0
      while read -r status rel _; do
        ext="${rel##*.}"; ext="${ext,,}"
        if [ "$status" = OK ]; then ok=$((ok+1)); continue; fi
        case "$CORE_EXTS" in
          *" $ext "*) core_fail=$((core_fail+1)); summary "❌ probe: CORE format failed to thumbnail: $rel" ;;
          *)          noncore_fail=$((noncore_fail+1)); summary "⚠️  probe: non-core format failed (distro lib limitation): $rel" ;;
        esac
      done < <(awk '$1=="THUMB"{print $2, $3}' "$OUT/probe.log" 2>/dev/null)
      # exiftool must work
      if grep -q 'NO exiftool' "$OUT/probe.log" 2>/dev/null; then
        core_fail=$((core_fail+1)); summary "❌ probe: exiftool not found (metadata extraction broken)"
      fi
      [ "$prc" -eq 3 ] && { core_fail=$((core_fail+1)); summary "❌ probe: vips unavailable"; }
      warn=$((warn+noncore_fail))
      if [ "$core_fail" -gt 0 ]; then
        fail=1; summary "❌ probe: $core_fail core failure(s), $ok ok, $noncore_fail non-core warning(s)"
      else
        summary "✅ probe: all core formats ok ($ok thumbnailed; $noncore_fail non-core warning(s))"
      fi
      ;;
    *) echo "unknown phase: $p" >&2; exit 2 ;;
  esac
done

note "summary"
cat "$OUT/summary.txt"
# Mirror the summary into the GitHub Actions job summary when present.
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && {
  echo "### immich package test — ${PRETTY_NAME:-$(. /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")}"
  sed 's/^/- /'
} < "$OUT/summary.txt" >> "${GITHUB_STEP_SUMMARY:-/dev/null}" 2>/dev/null || true

[ "$fail" -eq 0 ] || { echo "RESULT: FAIL"; exit 1; }
echo "RESULT: PASS${warn:+ (with $warn non-core warning(s))}"
