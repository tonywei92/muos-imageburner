#!/bin/sh
# Package muOS Image Burner as an installable .muxapp archive.
#
#   build/package.sh --love-dir DIR [--tools-dir DIR] [--version V] [--out FILE]
#
# The repo does not contain the LÖVE runtime or the static filesystem tools
# (they are gitignored; see BUILD.md). Point --love-dir at a directory that
# contains `love` and `libs/`, and --tools-dir (default: build/) at a directory
# containing `mke2fs` and `mkntfs` (and optional `tune2fs`).
#
# Produces a zip with a top-level `application/` folder, which muOS's Archive
# Manager extracts into the user applications path.
set -e

APP_NAME="Image Burner"
REPO=$(cd "$(dirname "$0")/.." && pwd)
TOOLS_DIR="$REPO/build"
VERSION="1.0.0"
OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --love-dir) LOVE_DIR="$2"; shift 2 ;;
    --tools-dir) TOOLS_DIR="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[ -n "$LOVE_DIR" ] || { echo "error: --love-dir is required (dir with 'love' and 'libs/')" >&2; exit 1; }
[ -f "$LOVE_DIR/love" ] || { echo "error: $LOVE_DIR/love not found" >&2; exit 1; }
[ -f "$LOVE_DIR/libs/liblove-11.5.so" ] || { echo "error: $LOVE_DIR/libs/liblove-11.5.so not found" >&2; exit 1; }
[ -f "$LOVE_DIR/libs/libluajit-5.1.so.2" ] || { echo "error: $LOVE_DIR/libs/libluajit-5.1.so.2 not found" >&2; exit 1; }
[ -f "$TOOLS_DIR/mke2fs" ] || { echo "error: $TOOLS_DIR/mke2fs not found (build it, see BUILD.md)" >&2; exit 1; }
[ -f "$TOOLS_DIR/mkntfs" ] || { echo "error: $TOOLS_DIR/mkntfs not found (build it, see BUILD.md)" >&2; exit 1; }

[ -n "$OUT" ] || OUT="$REPO/build/ImageBurner-$VERSION.muxapp"
STAGE=$(mktemp -d)
DEST="$STAGE/application/$APP_NAME"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$DEST/imageburner/tools" "$DEST/libs" "$DEST/licenses"

cp "$REPO/mux_launch.sh" "$REPO/mux_lang.ini" "$DEST/"
cp "$REPO"/imageburner/*.lua "$DEST/imageburner/"
cp "$LOVE_DIR/love" "$DEST/love"
cp "$LOVE_DIR/libs/liblove-11.5.so" "$LOVE_DIR/libs/libluajit-5.1.so.2" "$DEST/libs/"
cp "$TOOLS_DIR/mke2fs" "$TOOLS_DIR/mkntfs" "$DEST/imageburner/tools/"
[ -f "$TOOLS_DIR/tune2fs" ] && cp "$TOOLS_DIR/tune2fs" "$DEST/imageburner/tools/" || true
cp "$REPO/LICENSE.md" "$DEST/licenses/LICENSE.md"

chmod 755 "$DEST/love" "$DEST/mux_launch.sh" "$DEST/imageburner/tools/"*

rm -f "$OUT"
if command -v zip >/dev/null 2>&1; then
  ( cd "$STAGE" && zip -qr "$OUT" application )
elif command -v python3 >/dev/null 2>&1; then
  ( cd "$STAGE" && python3 -m zipfile -c "$OUT" application )
else
  echo "error: need 'zip' or 'python3' to create the archive" >&2; exit 1
fi

echo "Wrote $OUT"
ls -la "$OUT"
