#!/bin/bash
# Generate immich-db-reqs-* packaging files for PostgreSQL versions defined in debian/control
# This script reads debian/control to find all immich-db-reqs-NN packages and generates
# the corresponding .install, .postinst, and .prerm files from template files
# Template files use ##PSQL_VERSION## as placeholder for the PostgreSQL version number

set -e

# Extract PostgreSQL version numbers from immich-db-reqs-* package names in debian/control
PSQL_VERSIONS=$(grep -oP '^Package: immich-db-reqs-\K[0-9]+$' debian/control | sort -n)

if [ -z "$PSQL_VERSIONS" ]; then
    echo "No immich-db-reqs-* packages found in debian/control" >&2
    exit 1
fi

# Template files
TEMPLATE_INSTALL="debian/immich-db-reqs-tmpl.install"
TEMPLATE_POSTINST="debian/immich-db-reqs-tmpl.postinst"
TEMPLATE_PRERM="debian/immich-db-reqs-tmpl.prerm"

# Generate files for each PostgreSQL version
for file in "$TEMPLATE_INSTALL" "$TEMPLATE_POSTINST" "$TEMPLATE_PRERM"; do
    for ver in $PSQL_VERSIONS; do
        target="${file/tmpl/"$ver"}"
        if [ -f "$file" ]; then
            sed "s/##PSQL_VERSION##/${ver}/g" "$file" > "${target}"
        fi
    done
done
