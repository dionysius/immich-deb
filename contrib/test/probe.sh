#!/bin/bash
# Read-only media-processing probe. Runs the corpus through the EXACT system libraries immich
# decodes with (system libvips via the `vips` CLI, the bundled exiftool, jellyfin-ffmpeg) and
# reports pass/fail per file. Runs IN PLACE on the machine under test.
#
# Data-safe: only READS the staged corpus and WRITES thumbnails to a scratch dir under $TMPDIR.
# It never touches the immich database, the immich API, or the user's library. The only optional
# side effect is installing diagnostic CLI tools (libvips-tools / libheif-examples) if missing;
# pass --no-install to forbid even that.
#
# Output: a human header plus machine-parseable lines consumed by run.sh:
#   THUMB <OK|FAIL> <relpath> <detail>
#   META  <relpath> tags:<n>
#   MOTION <relpath> motion-tags:<n>
#
# Env:  CORPUS   path to the test-assets checkout (required)
#       OUT      scratch dir for thumbnails (default: $TMPDIR/immich-probe)
set -u
. /etc/os-release 2>/dev/null || true
CORPUS="${CORPUS:?set CORPUS to the test-assets directory}"
OUT="${OUT:-${TMPDIR:-/tmp}/immich-probe}"
ALLOW_INSTALL=1
[ "${1:-}" = "--no-install" ] && ALLOW_INSTALL=0
mkdir -p "$OUT"
line() { printf '\n========== %s ==========\n' "$1"; }

# The `vips` CLI is the faithful proxy for immich's sharp->libvips thumbnail path (same lib).
# immich-server pulls libvips42t64 but not the CLI, so fetch libvips-tools if absent.
if ! command -v vips >/dev/null 2>&1 && [ "$ALLOW_INSTALL" = 1 ]; then
  apt-get install -y -qq libvips-tools >/dev/null 2>&1 || true
fi
command -v vips >/dev/null 2>&1 || { echo "FATAL: 'vips' not available (install libvips-tools)"; exit 3; }

FF=/usr/lib/jellyfin-ffmpeg/ffmpeg
# exiftool: prefer system, else the copy vendored inside the node deploy
EXIFTOOL="$(command -v exiftool 2>/dev/null)"
[ -n "$EXIFTOOL" ] || EXIFTOOL="$(find /usr/lib/immich -type f -name exiftool 2>/dev/null | head -1)"

line "Versions"
echo "distro:   ${PRETTY_NAME:-unknown}"
echo "libvips:  $(vips --version 2>/dev/null)"
echo "ffmpeg:   $([ -x "$FF" ] && "$FF" -version 2>/dev/null | head -1 || echo '<jellyfin-ffmpeg not found>')"
echo "exiftool: ${EXIFTOOL:-<NONE FOUND>} $([ -n "$EXIFTOOL" ] && "$EXIFTOOL" -ver 2>/dev/null)"

line "vips native loaders"
vips -l 2>/dev/null | grep -oiE "VipsForeignLoad(Heif|Jxl|Jpeg|Png|Webp|Tiff|Gif|Jp2k|Magick|Nifti|Pdf|Svg)[A-Za-z]*" | sort -u | sed 's/^/  /'

line "THUMBNAIL each image/raw (immich's sharp->libvips path)"
printf '%-58s %s\n' "FILE" "RESULT"
while IFS= read -r f; do
  rel="${f#"$CORPUS"/}"
  o="$OUT/$(echo "$rel" | tr '/ ' '__').jpg"
  err="$(vips thumbnail "$f" "$o" 256 2>&1 >/dev/null)"
  if [ -s "$o" ]; then
    dim="$(vipsheader -f width "$o" 2>/dev/null)x$(vipsheader -f height "$o" 2>/dev/null)"
    printf '%-58s OK (%s)\n' "$rel" "$dim"
    echo "THUMB OK $rel $dim"
  else
    printf '%-58s FAIL: %s\n' "$rel" "$(echo "$err" | head -1)"
    echo "THUMB FAIL $rel $(echo "$err" | head -1)"
  fi
done < <(find "$CORPUS/formats" "$CORPUS/albums" -type f \
           \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
              -o -iname '*.avif' -o -iname '*.jxl' -o -iname '*.heic' -o -iname '*.gif' \
              -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.cr2' -o -iname '*.nef' \
              -o -iname '*.arw' -o -iname '*.rw2' -o -iname '*.raf' -o -iname '*.dng' \) 2>/dev/null | sort)

line "EXIFTOOL metadata extraction (dates / gps / rating / make / model)"
if [ -n "$EXIFTOOL" ]; then
  while IFS= read -r f; do
    rel="${f#"$CORPUS"/}"
    keys="$("$EXIFTOOL" -s -DateTimeOriginal -GPSLatitude -Rating -Make -Model -MIMEType "$f" 2>/dev/null | wc -l)"
    printf '%-58s tags:%s\n' "$rel" "$keys"
    echo "META $rel tags:$keys"
  done < <(find "$CORPUS/metadata" "$CORPUS/formats/motionphoto" -type f \( -iname '*.jpg' -o -iname '*.heic' \) 2>/dev/null | sort | head -20)
else
  echo "META <none> tags:0   # NO exiftool -> immich metadata extraction would be broken"
fi

line "MOTION PHOTO embedded-video detection (exiftool)"
for f in "$CORPUS"/formats/motionphoto/*; do
  [ -f "$f" ] || continue
  rel="${f#"$CORPUS"/}"
  emb="$([ -n "$EXIFTOOL" ] && "$EXIFTOOL" -s -MotionPhoto -MicroVideo -EmbeddedVideoType "$f" 2>/dev/null | wc -l || echo 0)"
  printf '%-48s motion-tags:%s\n' "$rel" "${emb:-0}"
  echo "MOTION $rel motion-tags:${emb:-0}"
done

line "DONE"
