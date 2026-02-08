#!/bin/bash
# Generate build metadata environment info
# Unfortunately the way dpkg-buildpackage works only their provided variables are availabe (so no git and no external env vars)

set -e

# Extract upstream repository information from debian/copyright
UPSTREAM_REPO_URL=$(grep '^Source:' debian/copyright | cut -d' ' -f2-)

# Extract packaging repository information from debian/control
PACKAGING_REPO_URL=$(grep '^Vcs-Browser:' debian/control | cut -d' ' -f2-)
PACKAGING_REPO=$(echo "${PACKAGING_REPO_URL}" | cut -d'/' -f3-)

# Generate build and source URL for GitHub releases
RELEASE_URL=
SOURCE_URL=
if [[ "${PACKAGING_REPO}" == github.com/* ]]; then
	# Remove distribution suffix (~distro) from version for tag name
	TAG_VERSION="${DEB_VERSION%%~*}"
	RELEASE_URL="${PACKAGING_REPO_URL}/releases/tag/debian%2F${TAG_VERSION}"
    # For source URL use upstream tag in packaging repo
    SOURCE_URL="${PACKAGING_REPO_URL}/tree/v${DEB_VERSION_UPSTREAM}"
fi

# Generate source URL for GitHub

# Generate build env output (used in immich about and support & feedback modals)
# - IMMICH_BUILD_IMAGE would be the used docker image but unable to determine in this context
# - IMMICH_SOURCE_COMMIT would be the source commit hash but unable to determine in this context, can't be empty otherwise the source section is hidden
# - IMMICH_SOURCE_URL points to the packaging repo tag since the section "immich" already points to upstream url with tag
cat <<EOF
IMMICH_BUILD=${DEB_SOURCE}_${DEB_VERSION}
IMMICH_BUILD_URL=${RELEASE_URL}
IMMICH_BUILD_IMAGE=
IMMICH_BUILD_IMAGE_URL=
IMMICH_REPOSITORY=${PACKAGING_REPO}
IMMICH_REPOSITORY_URL=${PACKAGING_REPO_URL}
IMMICH_SOURCE_REF=v${DEB_VERSION_UPSTREAM}
IMMICH_SOURCE_COMMIT=-
IMMICH_SOURCE_URL=${SOURCE_URL}
IMMICH_THIRD_PARTY_SOURCE_URL=${PACKAGING_REPO_URL}
IMMICH_THIRD_PARTY_BUG_FEATURE_URL=${PACKAGING_REPO_URL}/issues
IMMICH_THIRD_PARTY_DOCUMENTATION_URL=${PACKAGING_REPO_URL}/wiki
IMMICH_THIRD_PARTY_SUPPORT_URL=${PACKAGING_REPO_URL}/discussions
EOF
