#!/usr/bin/env bash
# Cover renderer + fallback template. Real render skips when no Chrome is installed.
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=/dev/null
. ./tests/lib.sh

S=skills/blog-cover/scripts/render-cover.sh
T=skills/blog-cover/assets/cover-template.html
D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

if [ -f "$T" ]; then pass "template exists"; else fail "template exists"; fi
for s in 1600px 840px '{{TITLE}}' '{{BADGES}}' '{{FOOTER_LEFT}}' '{{FOOTER_RIGHT}}'; do
  if grep -qF -e "$s" "$T" 2>/dev/null; then pass "template has $s"; else fail "template has $s"; fi
done
assert_eq "$(grep -c 'http' "$T" 2>/dev/null)" 0 "template has no http"

echo '<!doctype html><html><head><meta charset="utf-8"></head><body>x</body></html>' > "$D/c.html"

code=$(CHROME='' RAYSTACK_MAC_CHROME=/nonexistent RAYSTACK_CHROME_NAMES=no-such-chrome \
  bash "$S" "$D/c.html" "$D/x.png" 2>"$D/err" >/dev/null; echo $?)
assert_eq "$code" 1 "no chrome exits 1"
if grep -qF 'render-cover: no Chrome or Chromium found' "$D/err"; then pass "no chrome message"; else fail "no chrome message"; fi

# Fake Chrome records its args and the HTML it was given, and writes a PNG-ish file.
mkdir -p "$D/bin"
cat > "$D/bin/fake-chrome" <<FAKE
#!/usr/bin/env bash
: > "$D/args"
for a in "\$@"; do
  printf '%s\n' "\$a" >> "$D/args"
  case "\$a" in --screenshot=*) printf 'PNGfake' > "\${a#--screenshot=}" ;; file://*) cp "\${a#file://}" "$D/captured.html" ;; esac
done
FAKE
chmod +x "$D/bin/fake-chrome"

out=$(CHROME="$D/bin/fake-chrome" bash "$S" "$D/c.html" "$D/o.png" 2>/dev/null)
assert_eq "$out" "$D/o.png" "prints written path"
if grep -qF "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:\">" "$D/captured.html"; then pass "CSP injected"; else fail "CSP injected"; fi
if grep -qx -e '--window-size=1600,840' "$D/args"; then pass "default size 1600,840"; else fail "default size 1600,840"; fi
CHROME="$D/bin/fake-chrome" bash "$S" "$D/c.html" "$D/o.png" 1200x630 >/dev/null 2>&1
if grep -qx -e '--window-size=1200,630' "$D/args"; then pass "custom size 1200,630"; else fail "custom size 1200,630"; fi

# .jpg with no sips/magick/convert on PATH: falls back to PNG with a warning.
mkdir -p "$D/min"
for t in env bash dirname mktemp rm sed cp; do ln -s "$(command -v "$t")" "$D/min/$t"; done
out=$(PATH="$D/min" CHROME="$D/bin/fake-chrome" "$(command -v bash)" "$S" "$D/c.html" "$D/o.jpg" 2>"$D/err")
assert_eq "$out" "$D/o.png" "jpg fallback prints PNG path"
if [ -s "$D/o.png" ]; then pass "jpg fallback wrote png"; else fail "jpg fallback wrote png"; fi
if grep -qF 'render-cover: no sips or ImageMagick, wrote PNG' "$D/err"; then pass "jpg fallback warns"; else fail "jpg fallback warns"; fi

# Real render, only when a Chrome exists.
code=$(bash "$S" "$D/c.html" "$D/probe.png" 2>"$D/err" >/dev/null; echo $?)
if [ "$code" = 1 ] && grep -q 'no Chrome or Chromium found' "$D/err"; then pass "skip real render (no chrome)"; exit "$FAILED"; fi
title='Hardening an AWS account: IAM \&amp; SCPs, S3 \&lt;public\&gt; buckets, and the 90-char title test'
sed -e "s|{{TITLE}}|$title|" -e 's|{{BADGES}}||' -e 's|{{FOOTER_LEFT}}|example.com|' -e 's|{{FOOTER_RIGHT}}|@example|' "$T" > "$D/real.html"
bash "$S" "$D/real.html" "$D/real.png" >/dev/null 2>&1
dims=$(python3 -I -c 'import struct,sys;d=open(sys.argv[1],"rb").read(24);print(*struct.unpack(">II",d[16:24]),sep="x")' "$D/real.png" 2>/dev/null)
assert_eq "$dims" 1600x840 "real render is 1600x840"
exit "$FAILED"
