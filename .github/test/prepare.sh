#!/bin/bash
# Prepare an ephemeral system to run the immich package tests: add the runtime repos, install
# immich, set up PostgreSQL with immich credentials.
#
# DESTRUCTIVE — installs packages and (re)creates the `immich` postgres role/database. Meant for an
# ephemeral system (CI container/VM), never a user's real install.
#
# Wiki: https://github.com/dionysius/immich-deb/wiki  (Configuration: DB setup; Installation: PGDG)
#
# Install source — chosen explicitly by the caller (first argument):
#   * artifacts <DIR>  -> install the freshly-built .deb files in <DIR> (the CI pipeline)
#   * apt              -> apt-get install immich immich-cli (latest published packages)
#
# Usage:  prepare.sh artifacts <DIR>
#         prepare.sh apt
# Env:    USE_PGDG=1    force-add the PostgreSQL Apt repo regardless of distro
#         DB_PASSWORD   password for the immich role (default matches the shipped server.env)
set -eu
export DEBIAN_FRONTEND=noninteractive
info()  { printf '\n========== %s ==========\n' "$1"; }
error() { local code="$1"; shift; echo "$*" >&2; exit "$code"; }
MODE="${1:-}"; ARTIFACTS=""
case "$MODE" in
  artifacts) ARTIFACTS="${2:-}"; [ -n "$ARTIFACTS" ] || error 2 "usage: prepare.sh artifacts <DIR>" ;;
  apt) ;;
  *) error 2 "usage: prepare.sh {artifacts <DIR>|apt}" ;;
esac
DB_PASSWORD="${DB_PASSWORD:-myimmichpassword}"   # matches debian/install/system/server.env default
. /etc/os-release
[ -d /run/systemd/system ] || error 4 "systemd is not running (/run/systemd/system missing)"
install -d -m 0755 /etc/apt/keyrings

info "Runtime repos (nodesource + immich apt.crunchy.run), the documented production setup"
apt-get update -qq
apt-get install -y -qq curl ca-certificates gnupg
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
# immich apt repo provides the runtime deps (libvips42t64, jellyfin-ffmpeg7, vchord) and, for the
# repo install source, immich itself. install.sh only configures the repo + signing key.
curl -fsSL https://apt.crunchy.run/immich/install.sh | bash -

# noble ships pgvector < 0.7, which can't satisfy immich-db-reqs; add the official PostgreSQL Apt
# repo as the wiki documents (apt.postgresql.org.sh auto-configures the repo for this distro).
if [ "${USE_PGDG:-}" = 1 ] || { [ "$ID" = "ubuntu" ] && [ "$VERSION_ID" = "24.04" ]; }; then
  info "Adding PostgreSQL Apt repository"
  apt-get install -y -qq postgresql-common
  /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
fi

apt-get update -qq

info "Install immich (all-in-one: server + ML + db-reqs + redis) [mode: $MODE]"
if [ "$MODE" = artifacts ]; then
  # Install this arch's binaries plus the arch-independent packages (the latter only built on the
  # primary arch). Their Depends/Recommends resolve from the repos added above.
  arch="$(dpkg --print-architecture)"
  mapfile -t debs < <(ls "$ARTIFACTS"/*_all.deb "$ARTIFACTS"/*_"$arch".deb 2>/dev/null)
  [ "${#debs[@]}" -gt 0 ] || error 1 "no matching .deb files (arch=$arch) in $ARTIFACTS"
  printf '  %s\n' "${debs[@]}"
  apt-get install -y "${debs[@]}"
else
  apt-get install -y immich immich-cli
fi
echo "--- installed ---"; dpkg -l 'immich*' | awk '/^ii/{print $2, $3}'

for _ in $(seq 30); do runuser -u postgres -- pg_isready -q && break; sleep 1; done
runuser -u postgres -- pg_isready -q || error 5 "postgres did not become ready within 30s"

info "PostgreSQL role + database"
# Superuser so immich can initialise/manage the detected vector extension (vchord) on first start.
runuser -u postgres -- psql -v ON_ERROR_STOP=0 <<SQL
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'immich') THEN
    CREATE ROLE immich WITH LOGIN SUPERUSER PASSWORD '${DB_PASSWORD}';
  END IF;
END \$\$;
SQL
runuser -u postgres -- psql -tc "SELECT 1 FROM pg_database WHERE datname='immich'" | grep -q 1 \
  || runuser -u postgres -- psql -c "CREATE DATABASE immich OWNER immich;"
runuser -u postgres -- psql -c "GRANT ALL PRIVILEGES ON DATABASE immich TO immich;"

info "Start immich-server (ML autostarts on install)"
systemctl start immich-server.service || true

info "DONE"
