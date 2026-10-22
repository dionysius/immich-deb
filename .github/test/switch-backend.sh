#!/bin/bash
# Switch immich-machine-learning to a prebuilt backend from freshly-built .deb files: installing it
# replaces the current backend and its postinst restarts the service onto it. Asserts that it is the
# only backend left installed; run boot-check.sh afterwards for the service itself.
#
# DESTRUCTIVE — installs and removes packages. Meant for an ephemeral system (CI container/VM), never a
# user's real install.
#
# Usage:  switch-backend.sh <DIR> <BACKEND>    # e.g. switch-backend.sh artifacts cpu
set -eu
export DEBIAN_FRONTEND=noninteractive
info()  { printf '\n========== %s ==========\n' "$1"; }
error() { local code="$1"; shift; echo "$*" >&2; exit "$code"; }
[ $# -eq 2 ] || error 2 "usage: switch-backend.sh <DIR> <BACKEND>"
DIR=$1; BACKEND=$2
arch="$(dpkg --print-architecture)"

info "Switch to immich-machine-learning-$BACKEND"
debs=("$DIR"/immich-machine-learning-"$BACKEND"_*_"$arch".deb)
[ -e "${debs[0]}" ] || error 1 "missing ${debs[0]}"
# devices on the shared python depend on the shared venv, the others bundle their own
if dpkg-deb -f "${debs[0]}" Depends | grep -q immich-machine-learning-venv; then
  debs+=("$DIR"/immich-machine-learning-venv_*_"$arch".deb)
  [ -e "${debs[1]}" ] || error 1 "missing ${debs[1]}"
fi
apt-get install -y "${debs[@]}"

installed=$(dpkg-query -W -f '${db:Status-Status} ${Package}\n' 'immich-machine-learning-*' 2>/dev/null \
  | awk '$1 == "installed" {print $2}' | grep -Ev -- '-(venv|dbgsym)$' || true)
echo "--- installed backends ---"; echo "$installed"
[ "$installed" = "immich-machine-learning-$BACKEND" ] || error 1 "expected only immich-machine-learning-$BACKEND installed"

info "DONE"
