#!/usr/bin/env bash
HERE=$(cd "$(dirname "$0")" && pwd)
# Layout test: base_dir, work_dir and archive_dir from policy.json drive every hk folder.
set -uo pipefail
HK=${HK:-$(realpath "$(dirname "$0")/../hk")}
TMP=$(mktemp -d /tmp/hk-layout.XXXXXX)
export HK_ROOT="$TMP/work"
export HK_DIR="${HK_DIR:-$(dirname "$HK")}"
export HK_POLICY="$TMP/policy.json"
cat > "$HK_POLICY" <<POLICY
{"root": "$HK_ROOT", "base_dir": "src", "work_dir": "wip", "archive_dir": "done",
 "path_shape": "wip/<task>/<repo>", "branch_prefixes": ["feat", "fix", "chore"],
 "branch_default_prefix": "feat", "shape_check": "block", "branch_check": "block"}
POLICY
export HK_STUB_CMD="echo 'STATUS: APPROVED'"
fails=0
pass() { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fails=$((fails+1)); }

mkdir -p "$HK_ROOT/src"
git init -q --bare "$TMP/remote.git"
git -C "$TMP/remote.git" symbolic-ref HEAD refs/heads/develop
git clone -q "$TMP/remote.git" "$HK_ROOT/src/app"
cd "$HK_ROOT/src/app" || exit 1
git config user.email t@t; git config user.name test
echo '# app' > README.md; git add README.md; git commit -qm init
git push -q origin develop
git remote set-head origin -a

"$HK" new --task t --repo app >"$TMP/new.out" 2>&1
if [ -f "$HK_ROOT/wip/t/app/.agent/contract.json" ]; then
  pass "AC2: hk new creates \$HK_ROOT/wip/t/app"
else
  bad "AC2: hk new creates \$HK_ROOT/wip/t/app"; tail -5 "$TMP/new.out"
fi
[ ! -e "$HK_ROOT/features" ] && pass "AC2: no fixed features/ folder made" || bad "AC2: no fixed features/ folder made"

"$HK" status >"$TMP/status.out" 2>&1
if grep -q 't' "$TMP/status.out" && grep -q 'wip/t' "$TMP/status.out"; then
  pass "AC2: hk status lists the task under wip"
else
  bad "AC2: hk status lists the task under wip"; tail -5 "$TMP/status.out"
fi

SRC=$(realpath "$HK_DIR")
if grep -nE '"\$HK_ROOT"/(repos|features|archives)' "$SRC/hk" "$SRC/lib.sh" >/dev/null; then
  bad "AC3: no fixed \$HK_ROOT/(repos|features|archives) in hk, lib.sh"
else
  pass "AC3: no fixed \$HK_ROOT/(repos|features|archives) in hk, lib.sh"
fi

# AC1: the main suite still passes with the default layout
if env -u HK_ROOT -u HK_POLICY -u HK_DIR -u HK_STUB_CMD -u HK_HARNESS_DIR bash "$HERE/run_tests.sh" >/dev/null 2>&1; then echo "PASS  AC1: run_tests.sh passes"; else echo "FAIL  AC1: run_tests.sh failed"; fails=$((fails+1)); fi

rm -rf "$TMP"
[ "$fails" -eq 0 ] && exit 0
printf '\n%d check(s) failed\n' "$fails"; exit 1
