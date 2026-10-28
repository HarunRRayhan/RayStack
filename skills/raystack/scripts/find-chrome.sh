# shellcheck shell=bash disable=SC2034  # sourced: caller reads $chrome
# Sourced, never executed. Sets $chrome to a Chrome/Chromium binary, or "" if none. Never exits.
# Honours CHROME, then RAYSTACK_MAC_CHROME (macOS app path), then RAYSTACK_CHROME_NAMES (PATH names).
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
