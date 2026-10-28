#!/usr/bin/env bash
# Render a RayStack markdown report to PDF. Usage: report-pdf.sh <report.md> [out.pdf]
# Needs npx/node (for marked) and Chrome or Chromium. Set CHROME to pick a browser binary.
# Test seams: RAYSTACK_MAC_CHROME (macOS app path), RAYSTACK_CHROME_NAMES (PATH names to try).
set -eu

if [ $# -lt 1 ] || [ ! -f "$1" ]; then
  echo "usage: report-pdf.sh <report.md> [out.pdf]" >&2
  exit 1
fi
in="$1"
out="${2:-${in%.md}.pdf}"
here="$(cd "$(dirname "$0")" && pwd)"

chrome=""
mac="${RAYSTACK_MAC_CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [ -n "${CHROME:-}" ]; then
  chrome="$CHROME"
elif [ -x "$mac" ]; then
  chrome="$mac"
else
  for c in ${RAYSTACK_CHROME_NAMES:-google-chrome google-chrome-stable chromium chromium-browser}; do
    if command -v "$c" >/dev/null 2>&1; then chrome="$c"; break; fi
  done
fi
if [ -z "$chrome" ]; then
  echo "report-pdf: no Chrome or Chromium found. Install one or set CHROME=/path/to/chrome." >&2
  exit 1
fi

case "$in" in /*) ;; *) in="$PWD/$in" ;; esac
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

title="$(head -n 1 "$in" | sed 's/^# *//; s/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')"
{
  printf '<!doctype html><html><head><meta charset="utf-8">\n'
  # Report text is untrusted: CSP blocks scripts and remote or file:// loads.
  # (--disable-javascript is a no-op and --blink-settings=scriptEnabled=false breaks printing in Chrome 156.)
  csp="default-src 'none'; style-src 'unsafe-inline'; img-src data:"
  printf '<meta http-equiv="Content-Security-Policy" content="%s">\n' "$csp"
  printf '<title>%s</title><style>\n' "$title"
  cat "$here/report.css"
  printf '</style></head><body>\n'
  # Pinned, and run from the empty temp dir so a local package.json or node_modules can't swap it.
  (cd "$tmp" && npx --yes marked@14.1.4 < "$in") > "$tmp/body.html"
  # marked passes raw HTML through: keep only the tags marked itself emits (a stray <meta refresh>
  # or <iframe> could pull a local file into the PDF) and drop file:/javascript: URLs.
  # shellcheck disable=SC2016  # JavaScript, not shell
  node -e '
    const ok = /^\/?(h[1-6]|p|a|img|ul|ol|li|code|pre|em|strong|del|blockquote|hr|br|table|thead|tbody|tr|th|td|input)(?=[\s>\/])/i;
    let h = require("fs").readFileSync(0, "utf8");
    h = h.replace(/<(?=[a-z\/!?])/gi, (m, i) => ok.test(h.slice(i + 1)) ? m : "&lt;");
    h = h.replace(/\b(href|src|data|action|srcset|poster)(\s*=\s*["\x27]?\s*)(file|javascript|vbscript):/gi, "$1$2blocked-$3:");
    process.stdout.write(h);
  ' < "$tmp/body.html"
  printf '</body></html>\n'
} > "$tmp/report.html"

rc=0
"$chrome" --headless --disable-gpu --disable-extensions --no-pdf-header-footer \
  --proxy-server=127.0.0.1:9 --proxy-bypass-list='<-loopback>' \
  --user-data-dir="$tmp/profile" \
  --print-to-pdf="$out" "file://$tmp/report.html" >/dev/null 2>&1 || rc=$?
if [ "$rc" -ne 0 ]; then
  echo "report-pdf: chrome failed (rc=$rc)" >&2
  exit 1
fi
if [ ! -s "$out" ]; then
  echo "report-pdf: Chrome did not write $out" >&2
  exit 1
fi
echo "$out"
