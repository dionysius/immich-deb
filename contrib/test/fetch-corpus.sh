#!/usr/bin/env bash
# Fetch the immich test-assets corpus, pinned to the commit immich uses at the PACKAGED
# version. Pure git, independent of git-buildpackage:
#
#   - The packaged version comes from debian/changelog (dpkg-parsechangelog) or, in CI, the
#     debian/<version> tag that triggered the run.
#   - The pinned corpus commit is NOT in this repo: gbp imports the upstream tarball, which
#     carries .gitmodules (the URL) but drops the submodule gitlink. The gitlink lives in
#     immich-app/immich at tag v<version>, path e2e/test-assets. We read it with `git ls-tree`
#     after a cheap treeless fetch of just that tag, then shallow-fetch test-assets at it.
#
# This deliberately does NOT use a git submodule, so the corpus is never vendored in our branch.
#
# Usage: fetch-corpus.sh [DEST_DIR]            (default DEST_DIR: ./test-assets)
# Env:
#   IMMICH_VERSION    override the upstream version (else derived from changelog / $GITHUB_REF)
#   TEST_ASSETS_REF   bypass the pin and use this test-assets ref instead (e.g. "main")
#   IMMICH_REMOTE     immich repo url (default https://github.com/immich-app/immich)
#   ASSETS_REMOTE     test-assets repo url (default https://github.com/immich-app/test-assets)
set -euo pipefail

DEST="${1:-./test-assets}"
IMMICH_REMOTE="${IMMICH_REMOTE:-https://github.com/immich-app/immich}"
ASSETS_REMOTE="${ASSETS_REMOTE:-https://github.com/immich-app/test-assets}"

say() { printf 'fetch-corpus: %s\n' "$*"; }

# 1. packaged upstream version -> immich git tag (2.7.5-8 -> v2.7.5 ; 3.0.0~rc.2-1 -> v3.0.0-rc.2)
if [ -n "${IMMICH_VERSION:-}" ]; then
  uver="$IMMICH_VERSION"
elif command -v dpkg-parsechangelog >/dev/null 2>&1 && [ -f debian/changelog ]; then
  full="$(dpkg-parsechangelog -S Version)"; uver="${full%-*}"
elif [ -n "${GITHUB_REF_NAME:-}" ]; then
  full="${GITHUB_REF_NAME#debian/}"; uver="${full%-*}"
else
  echo "fetch-corpus: cannot determine version (set IMMICH_VERSION)" >&2; exit 2
fi
tag="v${uver//\~/-}"          # debian '~rc.N' pre-release -> git '-rc.N'
say "packaged upstream version $uver -> immich tag $tag"

# 2. resolve the pinned corpus commit (unless explicitly overridden)
if [ -n "${TEST_ASSETS_REF:-}" ]; then
  ref="$TEST_ASSETS_REF"
  say "pin bypassed, using test-assets ref '$ref'"
else
  git remote get-url immich >/dev/null 2>&1 || git remote add immich "$IMMICH_REMOTE"
  say "fetching $tag (treeless) from $IMMICH_REMOTE"
  git fetch --quiet --depth 1 --filter=blob:none immich "refs/tags/$tag:refs/tags/$tag"
  ref="$(git ls-tree "$tag" e2e/test-assets | awk '$2=="commit"{print $3}')"
  [ -n "$ref" ] || { echo "fetch-corpus: no e2e/test-assets gitlink at $tag" >&2; exit 1; }
  say "$tag pins test-assets @ $ref"
fi

# 3. shallow-fetch test-assets at that commit into its own folder
rm -rf "$DEST"; mkdir -p "$DEST"
git init --quiet "$DEST"
git -C "$DEST" remote add origin "$ASSETS_REMOTE"
# GitHub allows fetching an exact commit; fall back to the named ref if the server refuses.
git -C "$DEST" fetch --quiet --depth 1 origin "$ref" \
  || git -C "$DEST" fetch --quiet --depth 1 origin "refs/heads/$ref:refs/remotes/origin/$ref"
git -C "$DEST" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
say "corpus ready at $DEST ($(find "$DEST" -type f -not -path '*/.git/*' | wc -l) files)"
