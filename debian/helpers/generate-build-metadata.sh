#!/bin/bash
# Generate build metadata environment info
# Uses only dpkg-buildpackage provided variables (git and external env vars not available)

set -e

# Extract upstream repository information from debian/copyright
UPSTREAM_REPO_URL=$(grep '^Source:' debian/copyright | cut -d' ' -f2-)
UPSTREAM_REPO=$(echo "${UPSTREAM_REPO_URL}" | cut -d'/' -f3-)

# Extract packaging repository URL from debian/control
PACKAGING_REPO_URL=$(grep '^Vcs-Browser:' debian/control | cut -d' ' -f2-)

# Generate build env output
cat <<EOF
IMMICH_BUILD=${DEB_SOURCE}_${DEB_VERSION}_${DEB_BUILD_ARCH}
IMMICH_BUILD_URL=-
IMMICH_BUILD_IMAGE=-
IMMICH_BUILD_IMAGE_URL=-
IMMICH_REPOSITORY=${UPSTREAM_REPO}
IMMICH_REPOSITORY_URL=${UPSTREAM_REPO_URL}
IMMICH_SOURCE_REF=v${DEB_VERSION_UPSTREAM}
IMMICH_SOURCE_COMMIT=-
IMMICH_SOURCE_URL=${UPSTREAM_REPO_URL}/releases/tag/v${DEB_VERSION_UPSTREAM}
IMMICH_THIRD_PARTY_SOURCE_URL=${PACKAGING_REPO_URL}
IMMICH_THIRD_PARTY_BUG_FEATURE_URL=${PACKAGING_REPO_URL}/issues
IMMICH_THIRD_PARTY_DOCUMENTATION_URL=${PACKAGING_REPO_URL}/wiki
IMMICH_THIRD_PARTY_SUPPORT_URL=${PACKAGING_REPO_URL}/discussions
EOF
