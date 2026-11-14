#!/usr/bin/env bash
# Tests for harness lookup (harnesses.d). Run: tests/test_harnesses.sh
set -uo pipefail
WT=$(realpath "$(dirname "$0")/..")
TMP=$(mktemp -d /tmp/hk-harn.XXXXXX)
trap 'rm -rf "$TMP"' EXIT
fails=0
pass() { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fails=$((fails+1)); }

# Run a snippet in a subshell (die calls exit). Output goes to $TMP/out.
run() { ( export HK_ROOT="$TMP/root" HK_DIR="$WT" XDG_CONFIG_HOME="$TMP/xdg"; unset HK_HARNESS_DIR
          . "$WT/lib.sh"; eval "$1" ) >"$TMP/out" 2>&1; }

# AC1: the stub harness is a built-in file in harnesses.d
if [ -f "$WT/harnesses.d/stub.sh" ] && grep -q '^harness_stub()' "$WT/harnesses.d/stub.sh"; then
  pass "AC1: built-in stub lives in harnesses.d/stub.sh"; else bad "AC1: built-in stub lives in harnesses.d/stub.sh"; fi

# AC2: user harness runs
mkdir -p "$TMP/h1"
echo 'harness_echoer() { echo "ECHO $1"; }' > "$TMP/h1/echoer.sh"
run "export HK_HARNESS_DIR='$TMP/h1'; harness_run echoer work f w"
if [ "$(cat "$TMP/out")" = "ECHO work" ]; then pass "AC2: user harness runs"; else bad "AC2: user harness runs ($(head -c 200 "$TMP/out"))"; fi

# AC3: user file wins over built-in of the same name
mkdir -p "$TMP/h2" "$TMP/fakedir/harnesses.d"
echo 'harness_stub() { echo BUILTIN; }' > "$TMP/fakedir/harnesses.d/stub.sh"
echo 'harness_stub() { echo USER; }' > "$TMP/h2/stub.sh"
run "export HK_HARNESS_DIR='$TMP/h2'; HK_DIR='$TMP/fakedir'; harness_run stub work f w"
if [ "$(cat "$TMP/out")" = "USER" ]; then pass "AC3: user harness beats built-in"; else bad "AC3: user harness beats built-in ($(head -c 200 "$TMP/out"))"; fi

# AC4: bad name and unknown name
run 'harness_run "../x" work f w'; rc=$?
if [ $rc -ne 0 ] && grep -q 'bad harness name' "$TMP/out"; then pass "AC4: bad name dies"; else bad "AC4: bad name dies"; fi
run "export HK_HARNESS_DIR='$TMP/h1'; harness_run nope work f w"; rc=$?
if [ $rc -ne 0 ] && grep -q 'unknown harness: nope' "$TMP/out" && grep -q "$TMP/h1" "$TMP/out" && grep -q "$TMP/xdg/hk/harnesses.d" "$TMP/out"; then
  pass "AC4: unknown name dies naming folders"; else bad "AC4: unknown name dies naming folders ($(head -c 200 "$TMP/out"))"; fi

# AC5: no per-harness case arms left in lib.sh
if grep -Eq '^[[:space:]]*(pi|claude|opencode|stub|hermes)\)' "$WT/lib.sh"; then bad "AC5: no harness case arms in lib.sh"; else pass "AC5: no harness case arms in lib.sh"; fi

[ $fails -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "$fails failed"; exit 1; }
