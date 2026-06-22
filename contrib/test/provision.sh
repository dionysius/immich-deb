#!/bin/bash
# Provision a throwaway machine to run the immich package tests: add the runtime repos, install
# immich, set up PostgreSQL as the project wiki documents, and make sure postgres + redis are up.
# Runs IN PLACE as root and requires systemd. The immich services are started by boot-check.sh.
#
# Install source — chosen explicitly by the caller (first argument):
#   * artifacts <DIR>  -> install the freshly-built .deb files in <DIR> (the CI pipeline)
#   * apt              -> apt-get install immich immich-cli (latest published; external provisioners)
#
# DESTRUCTIVE — installs packages and (re)creates the `immich` postgres role/database. Only run in
# a disposable container/VM, never against a user's install.
#
# Wiki: https://github.com/dionysius/immich-deb/wiki  (Configuration: DB setup; Installation: PGDG)
#
# Usage:  provision.sh artifacts <DIR>
#         provision.sh apt
# Env:    USE_PGDG=1    force-add the PostgreSQL Apt repo regardless of distro
#         DB_PASSWORD   password for the immich role (default matches the shipped server.env)
#         SYSTEMD_OVERRIDE  set by the orchestrator (incus.sh / CI), not a user knob: one or more
#                       "Directive=Value" (';'- or newline-separated) written to a [Service] drop-in
#                       on BOTH immich units. Carries hardcoded per-environment workarounds, e.g.
#                       'PrivateIPC=false' for Ubuntu 24.04 under an unprivileged incus container,
#                       where PrivateIPC=true can't create its namespace and the services fail to
#                       start. The package keeps its hardened defaults.
set -eu
export DEBIAN_FRONTEND=noninteractive
MODE="${1:-}"; ARTIFACTS=""
case "$MODE" in
  artifacts) ARTIFACTS="${2:-}"; [ -n "$ARTIFACTS" ] || { echo "usage: provision.sh artifacts <DIR>" >&2; exit 2; } ;;
  apt) ;;
  *) echo "usage: provision.sh {artifacts <DIR>|apt}" >&2; exit 2 ;;
esac
DB_PASSWORD="${DB_PASSWORD:-myimmichpassword}"   # matches debian/install/system/server.env default
. /etc/os-release
line() { printf '\n========== %s ==========\n' "$1"; }
[ -d /run/systemd/system ] || { echo "FATAL: systemd is not running (PID 1 is not systemd)"; exit 4; }
install -d -m 0755 /etc/apt/keyrings

line "Runtime repos (nodesource + immich apt.crunchy.run), the documented production setup"
apt-get update -qq
apt-get install -y -qq curl ca-certificates gnupg
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
# immich apt repo provides the runtime deps (libvips42t64, jellyfin-ffmpeg7, vchord) and, for the
# repo install source, immich itself. install.sh only configures the repo + signing key.
curl -fsSL https://apt.crunchy.run/immich/install.sh | bash -

# noble ships pgvector < 0.7, which can't satisfy immich-db-reqs; add the official PostgreSQL Apt
# repo as the wiki documents (apt.postgresql.org.sh auto-configures the repo for this distro).
if [ "${USE_PGDG:-}" = 1 ] || { [ "$ID" = "ubuntu" ] && [ "$VERSION_ID" = "24.04" ]; }; then
  line "Adding PostgreSQL Apt repository (pgvector >= 0.7 workaround)"
  apt-get install -y -qq postgresql-common
  /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
fi

apt-get update -qq

line "Install immich (all-in-one: server + ML + db-reqs + redis) [mode: $MODE]"
if [ "$MODE" = artifacts ]; then
  # Install this arch's binaries plus the arch-independent packages (the latter only built on the
  # primary arch). Their Depends/Recommends resolve from the repos added above.
  arch="$(dpkg --print-architecture)"
  mapfile -t debs < <(ls "$ARTIFACTS"/*_all.deb "$ARTIFACTS"/*_"$arch".deb 2>/dev/null)
  [ "${#debs[@]}" -gt 0 ] || { echo "no matching .deb files (arch=$arch) in $ARTIFACTS" >&2; exit 1; }
  printf '  %s\n' "${debs[@]}"
  apt-get install -y "${debs[@]}"
else
  apt-get install -y immich immich-cli
fi
echo "--- installed ---"; dpkg -l 'immich*' | awk '/^ii/{print $2, $3}'

if [ -n "${SYSTEMD_OVERRIDE:-}" ]; then
  # Test-environment overrides: see the SYSTEMD_OVERRIDE note in the header. Written as a drop-in so
  # the packaged units are left untouched; boot-check starts the services afterwards.
  line "Apply systemd drop-in override(s) to the immich units"
  for s in immich-server immich-machine-learning; do
    install -d "/etc/systemd/system/$s.service.d"
    { echo "[Service]"
      # split on ';' or newlines, trim, drop blanks -> one directive per line
      printf '%s\n' "$SYSTEMD_OVERRIDE" | tr ';' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d'
    } > "/etc/systemd/system/$s.service.d/10-test-override.conf"
    echo "  $s:"; sed 's/^/    /' "/etc/systemd/system/$s.service.d/10-test-override.conf"
  done
  systemctl daemon-reload
fi

line "Ensure postgres + redis are up (systemd autostarts them on install; the immich user, /etc/immich and the service state dirs are handled by the packages + systemd)"
systemctl start postgresql 2>/dev/null || true
systemctl start redis-server 2>/dev/null || true
for _ in $(seq 30); do runuser -u postgres -- pg_isready -q && break; sleep 1; done

line "PostgreSQL role + database (per wiki Configuration)"
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

line "DONE"
