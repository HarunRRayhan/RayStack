#!/usr/bin/env bash
# Renders the sample report to PDF. Skips when no Chrome is installed.
cd "$(dirname "$0")/.." || exit 1
# shellcheck source=/dev/null
. ./tests/lib.sh

S=skills/raystack/scripts/report-pdf.sh
FOOTER='Reviewed with RayStack by Harun R. Rayhan. For a hands-on audit: https://harun.dev/consultation'
FX=tests/fixtures/sample-report.md

if [ -f "$FX" ] && grep -qF -e "$FOOTER" "$FX"; then pass "fixture has footer"; else fail "fixture has footer"; fi

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

# No chrome anywhere: must exit 1 with a message.
code=$(CHROME='' RAYSTACK_MAC_CHROME=/nonexistent RAYSTACK_CHROME_NAMES=no-such-chrome \
  bash "$S" "$FX" "$D/x.pdf" 2>"$D/err" >/dev/null; echo $?)
assert_eq "$code" 1 "no chrome exits 1"
if grep -q 'no Chrome or Chromium found' "$D/err"; then pass "no chrome message"; else fail "no chrome message"; fi

if grep -qF "default-src 'none'; style-src 'unsafe-inline'; img-src data:" "$S"; then pass "CSP meta in wrapper"; else fail "CSP meta in wrapper"; fi

# Raw HTML in a report is neutralised before Chrome sees it (fake Chrome captures the HTML).
mkdir -p "$D/bin" "$D/secret"
tok="RAYSTACK_LOCAL_TOKEN_$$"
printf '<p>%s</p>\n' "$tok" > "$D/secret/leak.html"
cat > "$D/bin/fake-chrome" <<FAKE
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in --print-to-pdf=*) printf '%%PDF-fake' > "\${a#--print-to-pdf=}" ;; file://*) cp "\${a#file://}" "$D/captured.html" ;; esac
done
FAKE
chmod +x "$D/bin/fake-chrome"
{
  cat "$FX"
  printf '\n<meta http-equiv="refresh" content="0;url=file://%s">\n\n' "$D/secret/leak.html"
  printf '<iframe src="file://%s"></iframe>\n\n<base href="file:///">\n\n' "$D/secret/leak.html"
  printf '<object data="file://%s"></object><embed src="x"><link rel="import" href="x">\n\n' "$D/secret/leak.html"
  printf '<form action="x"></form><script>x()</script>\n\n'
  printf '<a href="file://%s">a</a> <a href="javascript:x()">b</a> <img src="file:///etc/passwd">\n\n' "$D/secret/leak.html"
  # shellcheck disable=SC2016  # literal markdown backticks
  printf 'Keep `a <b> c` and <one or two sentences>.\n'
} > "$D/hostile.md"
CHROME="$D/bin/fake-chrome" bash "$S" "$D/hostile.md" "$D/h.pdf" >/dev/null 2>&1
H="$D/captured.html"
if [ -s "$H" ]; then pass "captured rendered HTML"; else fail "captured rendered HTML"; fi
for t in meta base iframe object embed form link script; do
  n=$(sed '1,/<\/head>/d' "$H" 2>/dev/null | grep -ci "<${t}[ >]")
  assert_eq "$n" 0 "no live <$t> in report body"
done
if grep -qiE '(href|src|data)="(file|javascript):' "$H"; then fail "file:/javascript: URLs neutralised"; else pass "file:/javascript: URLs neutralised"; fi
if grep -qF "$tok" "$H"; then fail "local file content absent"; else pass "local file content absent"; fi
if grep -qF '&lt;one or two sentences&gt;' "$H" || grep -qF '&lt;one or two sentences>' "$H"; then pass "stray tags shown as text"; else fail "stray tags shown as text"; fi
if grep -qF '<code>a &lt;b&gt; c</code>' "$H"; then pass "inline code untouched"; else fail "inline code untouched"; fi
if grep -qF '<h2' "$H"; then pass "markdown structure kept"; else fail "markdown structure kept"; fi

cp "$FX" "$D/r.md"
code=$(bash "$S" "$D/r.md" 2>"$D/err" >/dev/null; echo $?)
if [ "$code" = 1 ] && grep -q 'no Chrome or Chromium found' "$D/err"; then pass "skipped: no chrome"; exit "$FAILED"; fi
assert_eq "$(head -c 4 "$D/r.pdf" 2>/dev/null)" "%PDF" "default output is <input>.pdf"

(cd "$D" && bash "$OLDPWD/$S" "$OLDPWD/$FX" out.pdf >/dev/null 2>&1)
assert_eq "$(head -c 4 "$D/out.pdf" 2>/dev/null)" "%PDF" "relative output path"

{ cat "$FX"; printf '\n<script>document.title='"'x'"'</script>\n\n<img src="file:///etc/passwd">\n'; } > "$D/evil.md"
bash "$S" "$D/evil.md" "$D/evil.pdf" >/dev/null 2>&1
assert_eq "$(head -c 4 "$D/evil.pdf" 2>/dev/null)" "%PDF" "hostile markup still renders"
exit "$FAILED"
