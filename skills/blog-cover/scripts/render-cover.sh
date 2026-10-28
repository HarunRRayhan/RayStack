#!/usr/bin/env bash
# Render a cover HTML page to an image. Usage: render-cover.sh <cover.html> <out.png|out.jpg> [WIDTHxHEIGHT]
# Size defaults to 1600x840. Needs Chrome or Chromium (set CHROME to pick one). A .jpg out needs
# sips or ImageMagick; without either it writes <out>.png instead and says so.
set -eu

if [ $# -lt 2 ] || [ ! -f "$1" ]; then
  echo "usage: render-cover.sh <cover.html> <out.png|out.jpg> [WIDTHxHEIGHT]" >&2
  exit 1
fi
in="$1"
out="$2"
size="${3:-1600x840}"
case "$size" in
  [0-9]*x[0-9]*) ;;
  *) echo "render-cover: size must look like 1600x840" >&2; exit 1 ;;
esac

# shellcheck source=../../raystack/scripts/find-chrome.sh source-path=SCRIPTDIR
. "$(dirname "$0")/../../raystack/scripts/find-chrome.sh"
if [ -z "$chrome" ]; then
  echo "render-cover: no Chrome or Chromium found" >&2
  exit 1
fi

case "$in" in /*) ;; *) in="$PWD/$in" ;; esac
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Cover text may be untrusted: the CSP blocks scripts and any remote or file:// load.
csp="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:"
sed "s|<head>|<head><meta http-equiv=\"Content-Security-Policy\" content=\"$csp\">|" "$in" > "$tmp/cover.html"

png="$tmp/cover.png"
rc=0
"$chrome" --headless --disable-gpu --hide-scrollbars --window-size="${size%x*},${size#*x}" \
  --user-data-dir="$tmp/profile" --screenshot="$png" "file://$tmp/cover.html" >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$png" ]; then
  echo "render-cover: chrome failed (rc=$rc)" >&2
  exit 1
fi

case "$out" in
  *.jpg|*.jpeg)
    if command -v sips >/dev/null 2>&1; then
      sips -s format jpeg "$png" --out "$out" >/dev/null
    elif command -v magick >/dev/null 2>&1; then
      magick "$png" "$out"
    elif command -v convert >/dev/null 2>&1; then
      convert "$png" "$out"
    else
      out="${out%.*}.png"
      echo "render-cover: no sips or ImageMagick, wrote PNG" >&2
      cp "$png" "$out"
    fi ;;
  *) cp "$png" "$out" ;;
esac
echo "$out"
