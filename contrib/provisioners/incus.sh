#!/usr/bin/env bash
# External provisioner: run the immich package tests inside local incus instances, one per image —
# containers by default, or VMs with --vm.
#
# This is the secondary way to run the tests (the primary is the CI pipeline in
# .github/workflows/packaging.yml). It REUSES the in-machine scripts from ../test verbatim — it just
# creates the instance, pushes the scripts in, and runs them. Unlike the pipeline it installs the
# LATEST PUBLISHED packages from the apt repo (provision.sh's `apt` mode), not freshly-built
# artifacts. Incus instances run systemd as PID 1, so boot-check exercises the real .service units.
#
# You pass the incus image(s) to test, exactly as `incus launch` expects them — an alias or a
# fingerprint, with the remote — e.g. images:debian/13, images:ubuntu/24.04, or a fingerprint. One
# instance is created per image; any existing instance of that name is removed first, so every run
# starts from a clean install.
#
# Expandable: this is one orchestrator. Another transport (docker, ssh, a remote VM, ...) is just
# another script next to this one that does the same three things — create/reach a machine, push
# ../test/*.sh into it, and run provision.sh + run.sh there.
#
# Usage:
#   ./incus.sh images:debian/13 images:ubuntu/24.04 images:ubuntu/26.04
#   ./incus.sh --vm images:ubuntu/24.04         # VMs instead of containers
#   ./incus.sh --keep images:debian/13          # leave the instance running afterwards
#   ./incus.sh --cleanup                        # delete all immich-test-* instances and exit
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE="$(cd "$HERE/../test" && pwd)"          # the shared in-machine scripts
REPO="$(cd "$HERE/../.." && pwd)"            # repo root (for fetch-corpus version resolution)
PREFIX="immich-test"
STAGE=/root/immich-test                       # where the scripts land inside the container

CLEANUP=0 KEEP=0 VM=0
IMAGES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --cleanup)  CLEANUP=1; shift ;;
    --keep)     KEEP=1; shift ;;
    --vm)       VM=1; shift ;;
    -h|--help)  sed -n '2,24p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *)  IMAGES+=("$1"); shift ;;
  esac
done
LAUNCH_OPTS=(); [ "$VM" = 1 ] && LAUNCH_OPTS=(--vm)

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
command -v incus >/dev/null || { echo "incus not found" >&2; exit 1; }

# A valid, deterministic container name derived from the image spec (incus names allow [a-zA-Z0-9-]).
cname() { printf '%s-%s' "$PREFIX" "$(printf '%s' "$1" | tr -c 'a-zA-Z0-9' '-' | sed 's/--*/-/g; s/^-//; s/-$//')"; }

if [ "$CLEANUP" = 1 ]; then
  incus list -f csv -c n 2>/dev/null | grep "^$PREFIX-" | while read -r c; do
    incus delete -f "$c" && echo "deleted $c" || true
  done
  exit 0
fi

[ "${#IMAGES[@]}" -gt 0 ] || { echo "no image given, e.g.: $0 images:debian/13 images:ubuntu/24.04" >&2; exit 2; }

wait_ready() { # instance is up, the agent answers (VMs), and it has network/apt
  local c="$1" _
  for _ in $(seq 1 60); do
    incus exec "$c" -- sh -c 'command -v apt-get >/dev/null && getent hosts deb.nodesource.com >/dev/null' 2>/dev/null && return 0
    sleep 2
  done
  echo "  WARNING: $c not ready after 120s" >&2
}

# Resolve + fetch the pinned corpus once on the host (it has git + the repo + network), then push
# the same checkout into every container. Avoids needing git inside the containers. Kept outside the
# repo tree so it doesn't show up in git status.
CORPUS="${TMPDIR:-/tmp}/immich-test-corpus"
log "Fetching test-assets corpus on host -> $CORPUS"
( cd "$REPO" && "$CORE/fetch-corpus.sh" "$CORPUS" )

rc=0
for img in "${IMAGES[@]}"; do
  c="$(cname "$img")"
  log "[$img] instance $c"
  incus delete -f "$c" >/dev/null 2>&1 || true   # always start clean: stop + remove any existing
  incus launch "${LAUNCH_OPTS[@]}" "$img" "$c" >/dev/null || { echo "  launch failed for '$img'"; rc=1; continue; }
  echo "  launched$([ "$VM" = 1 ] && echo ' (vm)')"
  wait_ready "$c"

  # Hardcoded per-OS testbed workarounds, decided from what's actually inside (image-spec agnostic).
  # Ubuntu 24.04 in an unprivileged incus CONTAINER can't set up the unit's PrivateIPC namespace, so
  # the services fail to start — VMs and bare-metal are fine, so only apply it for containers. The
  # package keeps PrivateIPC=true. This is the only source of SYSTEMD_OVERRIDE; it is NOT taken from
  # the environment. Add future workarounds to the case below.
  # shellcheck disable=SC2016  # $ID/$VERSION_ID must expand in the instance's shell, not here
  os="$(incus exec "$c" -- sh -c '. /etc/os-release; echo "$ID $VERSION_ID"' 2>/dev/null || echo '')"
  ov=""
  [ "$VM" = 0 ] && case "$os" in "ubuntu 24.04") ov="PrivateIPC=false" ;; esac
  prov_env=(); [ -n "$ov" ] && prov_env=(SYSTEMD_OVERRIDE="$ov")

  log "[$img] staging scripts + corpus -> $c:$STAGE"
  incus exec "$c" -- rm -rf "$STAGE"
  incus exec "$c" -- mkdir -p "$STAGE"
  incus file push --quiet "$CORE"/*.sh "$c$STAGE/"
  incus file push --recursive --quiet "$CORPUS" "$c$STAGE/"   # lands at $STAGE/<basename>

  log "[$img] provision (latest published packages from the apt repo)${ov:+ [override: $ov]}"
  incus exec "$c" -- env "${prov_env[@]}" bash "$STAGE/provision.sh" apt \
    || { echo "  provision failed"; rc=1; }

  log "[$img] run tests (boot + corpus probe)"
  incus exec "$c" -- bash "$STAGE/run.sh" --phases boot,probe --corpus "$STAGE/$(basename "$CORPUS")" \
    || { echo "  [$img] TESTS FAILED"; rc=1; }

  [ "$KEEP" = 1 ] || incus stop "$c" >/dev/null 2>&1 || true
done

log "done (rc=$rc). Instances prefixed '$PREFIX-'; remove with: $0 --cleanup"
exit "$rc"
