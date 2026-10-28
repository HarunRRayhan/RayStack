#!/usr/bin/env bash
# Shared helpers. Source this file; check FAILED at the end and exit "$FAILED".
# shellcheck disable=SC2034  # read by the sourcing script
FAILED=0
pass() { echo "ok   $*"; }
fail() { echo "FAIL $*"; FAILED=1; }
assert_eq() {
  if [ "$1" = "$2" ]; then pass "$3"; else fail "$3 (got '$1', want '$2')"; fi
}
