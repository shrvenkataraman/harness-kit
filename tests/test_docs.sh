#!/usr/bin/env bash
# Docs coverage: names are derived from the code at run time. Run: bash tests/test_docs.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WT=$(dirname "$HERE")
cd "$WT" || exit 2
fails=0
pass() { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fails=$((fails+1)); }

README="$WT/README.md"; HARN="$WT/docs/harnesses.md"; CONTRIB="$WT/CONTRIBUTING.md"

# check_all <label> <file> <names...>: every name appears in the file
check_all() {
  local label="$1" file="$2" n missing="" count=0; shift 2
  if [ ! -f "$file" ]; then bad "$label: missing file $file"; return; fi
  for n in "$@"; do count=$((count+1)); grep -qF -- "$n" "$file" || missing="$missing $n"; done
  if [ "$count" -eq 0 ]; then bad "$label: derived zero names (parser broke)"
  elif [ -z "$missing" ]; then pass "$label ($count names)"
  else bad "$label: not documented:$missing"; fi
}

# AC1: subcommands from the usage() block (lines "  hk <word>")
subs=$(awk '/^usage\(\)/{u=1} u&&/^EOF$/{exit} u&&/^  hk [a-z]/{print $2}' hk | sort -u)
# shellcheck disable=SC2086
check_all "AC1: every usage() subcommand is in README.md" "$README" $subs

# AC2: HK_* environment variables
vars=$(grep -ohE 'HK_[A-Z_]+' hk lib.sh harnesses.d/*.sh | sort -u)
# shellcheck disable=SC2086
check_all "AC2: every HK_* variable is in README.md" "$README" $vars

# AC3: policy keys
keys=$(grep -ohE 'policy [a-z_]+' hk lib.sh | awk '{print $2}' | sort -u)
# shellcheck disable=SC2086
check_all "AC3: every policy key is in README.md" "$README" $keys

# AC4: harness guide names the search folders and both modes
if [ -f "$HARN" ] \
   && grep -qF 'HK_HARNESS_DIR' "$HARN" && grep -qF 'harnesses.d' "$HARN" \
   && grep -qF 'XDG_CONFIG_HOME' "$HARN" && grep -qE '(^|[^a-z])work([^a-z]|$)' "$HARN" \
   && grep -qE '(^|[^a-z])read([^a-z]|$)' "$HARN" && grep -qF 'harness_dirs' "$HARN"; then
  pass "AC4: docs/harnesses.md names search order folders and both modes"
else bad "AC4: docs/harnesses.md must name harness_dirs, HK_HARNESS_DIR, XDG_CONFIG_HOME, harnesses.d, modes work and read"; fi

# Ticket text: CONTRIBUTING and README basics
if [ -f "$CONTRIB" ] && grep -qF 'tests/run_tests.sh' "$CONTRIB" && grep -qi shellcheck "$CONTRIB"; then
  pass "CONTRIBUTING.md names tests/run_tests.sh and shellcheck"
else bad "CONTRIBUTING.md must name tests/run_tests.sh and shellcheck"; fi
if [ -f "$README" ] && grep -qF 'hk install' "$README" && grep -qF '$HK_ROOT' "$README" && grep -qi license "$README"; then
  pass "README.md has install step, \$HK_ROOT and license line"
else bad "README.md must have 'hk install', \$HK_ROOT and a license line"; fi

[ "$fails" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$fails FAILED"; exit 1
