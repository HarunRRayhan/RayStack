#!/usr/bin/env bash
# Render a cover HTML page to an image. Usage: render-cover.sh <cover.html> <out.png|out.jpg> [WIDTHxHEIGHT]
# Size defaults to 1600x840. Needs Chrome or Chromium (set CHROME to pick one) and node. A .jpg out
# needs sips or ImageMagick; without either it writes <out>.png instead and says so.
set -eu

if [ $# -lt 2 ] || [ ! -f "$1" ]; then
  echo "usage: render-cover.sh <cover.html> <out.png|out.jpg> [WIDTHxHEIGHT]" >&2
  exit 1
fi
in="$1"
out="$2"
size="${3:-1600x840}"
if ! [[ "$size" =~ ^[0-9]+x[0-9]+$ ]]; then
  echo "render-cover: size must look like 1600x840" >&2
  exit 1
fi

# Needs the raystack skill installed beside blog-cover (install.sh and the plugin do this).
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

# Cover text may be untrusted. The CSP meta is written first, so it applies whatever head the input
# has; the CSP is the real security boundary. The node pass is defense-in-depth: it deletes the void
# navigation/loading tags (meta incl. refresh, base, link, embed), escapes iframe/object/script/form
# etc., and rewrites file:/javascript: URLs. data: URIs in img/font stay. Needs node; fails closed.
csp="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:"
if ! command -v node >/dev/null 2>&1; then
  echo "render-cover: node is required to sanitise the cover HTML" >&2
  exit 1
fi
{
  printf '<!doctype html><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="%s">\n' "$csp"
  # shellcheck disable=SC2016  # JavaScript, not shell
  node -e '
    let h = require("fs").readFileSync(0, "utf8");
    h = h.replace(/<\/?(meta|base|link|embed)\b[^>]*>/gi, "");
    h = h.replace(/<(?=\/?(meta|base|iframe|frame|frameset|object|embed|applet|link|script|form)(?![a-z0-9-])|\?)/gi, "&lt;");
    h = h.replace(/\b(href|src|data|action|srcset|poster)(\s*=\s*["\x27]?\s*)(file|javascript|vbscript):/gi, "$1$2blocked-$3:");
    process.stdout.write(h);
  ' < "$in"
} > "$tmp/cover.html"
if ! grep -qF "$csp" "$tmp/cover.html"; then
  echo "render-cover: CSP injection failed" >&2
  exit 1
fi

png="$tmp/cover.png"
rc=0
"$chrome" --headless --disable-gpu --hide-scrollbars --window-size="${size%x*},${size#*x}" \
  --user-data-dir="$tmp/profile" --screenshot="$png" "file://$tmp/cover.html" >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ] || [ ! -s "$png" ]; then
  echo "render-cover: chrome failed (rc=$rc)" >&2
  exit 1
fi

case "$out" in
  *.[jJ][pP][gG]|*.[jJ][pP][eE][gG])
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
