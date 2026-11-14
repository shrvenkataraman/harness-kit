#!/usr/bin/env bash
# Ticket 28: one default-model variable (HK_MODEL) in hk.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
WT=$(dirname "$HERE")
T=$(mktemp -d /tmp/hk-model.XXXXXX)
trap 'rm -rf "$T"' EXIT
fails=0
pass() { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fails=$((fails+1)); }

mkdir -p "$T/bin"
for b in pi opencode; do
  printf '#!/bin/sh\necho "ARGV: $*"\n' > "$T/bin/$b"; chmod +x "$T/bin/$b"
done
echo "prompt" > "$T/prompt.md"
echo '{"model":"m3"}' > "$T/policy_m3.json"
echo '{}' > "$T/policy_empty.json"

# Run harness_run pi read in a clean env; extra args are env assignments.
run_pi() { # run_pi <policyfile> [VAR=val ...]
  local pol="$1"; shift
  env -u HK_ROOT -u HK_POLICY -u HK_DIR -u HK_STUB_CMD -u HK_HARNESS_DIR -u HK_MODEL -u HK_REVIEW_MODEL \
    PATH="$T/bin:$PATH" HK_ROOT="$T/root" HK_DIR="$WT" HK_POLICY="$pol" "$@" \
    bash -c '. "$HK_DIR/lib.sh"; harness_run pi read "$1" "$2"' _ "$T/prompt.md" "$T" 2>&1
}

# AC1
if env -u HK_ROOT -u HK_POLICY -u HK_DIR -u HK_STUB_CMD -u HK_HARNESS_DIR bash "$HERE/run_tests.sh" >"$T/rt.out" 2>&1; then
  pass "AC1 run_tests.sh passes"; else bad "AC1 run_tests.sh passes"; tail -5 "$T/rt.out"; fi

# AC2
n=$(cd "$WT" && cat lib.sh hk harnesses.d/*.sh | grep -o 'qwen3.8-flash-next' | wc -l)
[ "$n" -eq 1 ] && pass "AC2 qwen3.8-flash-next appears once ($n)" || bad "AC2 expected 1 occurrence, got $n"

# AC3
out=$(run_pi "$T/policy_empty.json" HK_MODEL=m1)
case "$out" in *"--model m1"*) pass "AC3a HK_MODEL=m1 gives --model m1";; *) bad "AC3a got: $out";; esac
out=$(run_pi "$T/policy_empty.json" HK_MODEL=m1 HK_REVIEW_MODEL=m2)
case "$out" in *"--model m2"*) pass "AC3b HK_REVIEW_MODEL=m2 wins";; *) bad "AC3b got: $out";; esac
case "$out" in *"--model m1"*) bad "AC3b m1 leaked: $out";; *) pass "AC3b m1 absent when m2 set";; esac

# AC4
out=$(run_pi "$T/policy_m3.json")
case "$out" in *"--model m3"*) pass "AC4a policy model m3 used";; *) bad "AC4a got: $out";; esac
out=$(run_pi "$T/policy_m3.json" HK_MODEL=m1)
case "$out" in *"--model m1"*) pass "AC4b env HK_MODEL beats policy";; *) bad "AC4b got: $out";; esac

[ "$fails" -eq 0 ] || { echo "$fails failure(s)"; exit 1; }
echo "all passed"
