#!/usr/bin/env bash
# hk test suite. Builds a throwaway repository under /tmp, then walks the whole flow.
# Nothing outside the temp folder is touched. Run: tests/run_tests.sh
set -uo pipefail

HK=${HK:-$(realpath "$(dirname "$0")/../hk")}
TMP=$(mktemp -d /tmp/hk-test.XXXXXX)
export HK_ROOT="$TMP/work"
export HK_DIR="${HK_DIR:-$(dirname "$HK")}"
# A fixed policy, so the suite never reads the user's ~/.config/hk/policy.json.
export HK_POLICY="$TMP/policy.json"
cat > "$HK_POLICY" <<POLICY
{"root": "$HK_ROOT", "base_dir": "repos", "work_dir": "features", "archive_dir": "archives",
 "path_shape": "features/<task>/<repo>", "branch_prefixes": ["feat", "fix", "chore"],
 "branch_default_prefix": "feat", "shape_check": "block", "branch_check": "block"}
POLICY
export HK_STUB_CMD="echo 'STATUS: APPROVED'; echo 'checked concurrency and empty input'"
fails=0

step() { printf '\n== %s\n' "$*"; }
pass() { printf 'PASS  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fails=$((fails+1)); }
# Commands are strings so they can cd into a worktree.
ok_c()   { if bash -c "$1" >/tmp/hk-out 2>&1; then pass "$1"; else bad "$1"; tail -6 /tmp/hk-out; fi; }
no_c()   { if bash -c "$1" >/tmp/hk-out 2>&1; then bad "should have failed: $1"; tail -6 /tmp/hk-out; else pass "$1"; fi; }
has()    { grep -qE "$2" /tmp/hk-out && pass "$1" || { bad "$1"; tail -6 /tmp/hk-out; }; }

# ---------- fixture: bare remote, base checkout on develop, one ticket ----------
mkdir -p "$TMP/tickets" "$HK_ROOT/repos"
git init -q --bare "$TMP/remote.git"
git -C "$TMP/remote.git" symbolic-ref HEAD refs/heads/develop
git clone -q "$TMP/remote.git" "$HK_ROOT/repos/app"
cd "$HK_ROOT/repos/app" || exit 1
git config user.email t@t; git config user.name test
echo '# app' > README.md; git add README.md; git commit -qm init
git push -q origin develop
git remote set-head origin -a

cat > "$TMP/tickets/01-marker.md" <<'EOF'
# 01: marker file exists

**Status:** ready-for-local
**Repo:** app
**Edit:** done.txt
**Read:** README.md
**Test:** none
**Check:** test -f done.txt

## Goal
A file named done.txt exists in the worktree.

## Done when
- The Check above exits 0.

## Out of scope
README.md
EOF

WT="$HK_ROOT/features/01-marker/app"
HOOK="$HK_ROOT/repos/app/.git/hooks/pre-commit"

step "hk new writes the contract and makes the worktree"
ok_c "$HK new $TMP/tickets/01-marker.md"
[ -f "$WT/.agent/contract.json" ] && pass "contract written" || bad "contract missing"
[ "$(git -C "$WT" branch --show-current)" = "feat/01-marker" ] && pass "branch is feat/01-marker" || bad "wrong branch"
grep -qx '.agent/' "$HK_ROOT/repos/app/.git/info/exclude" && pass ".agent/ never enters a diff" || bad ".agent/ not excluded"
[ "$(jq -r '.base_ref' "$WT/.agent/contract.json")" = develop ] && pass "base ref read from origin/HEAD" || bad "base ref wrong"

step "hk install writes the git hook for that repo"
ok_c "$HK install --repo app --apply"
[ -x "$HOOK" ] && pass "hook is executable" || bad "hook missing or not executable"

step "red: an empty worktree must not pass"
no_c "cd $WT && $HK verify"; has "receipt says red" 'receipt red'

step "red: the hook blocks a commit with no receipt"
no_c "cd $WT && git commit -qm premature"
has "hook blocked it" 'hk BLOCK'

step "green after the work, but no review yet"
( cd "$WT" && echo done > done.txt )
ok_c "cd $WT && $HK verify"; has "receipt says green" 'receipt green'
jq -e '.checks_passed == 1 and .verdict == "green"' "$WT/.agent/receipt.json" >/dev/null \
  && pass "receipt stores the check result" || bad "receipt fields wrong"
no_c "cd $WT && git add done.txt && git commit -qm no-review"
has "hook asked for a review" 'no review.json'

step "hk review uses a harness beside the writer"
ok_c "cd $WT && $HK review"
[ "$(jq -r '.status' "$WT/.agent/review.json")" = APPROVED ] && pass "review approved" || bad "review not approved"
[ "$(jq -r '.reviewer_harness' "$WT/.agent/review.json")" = stub ] && pass "review names its harness" || bad "reviewer harness missing"

step "reviewer backup: a first harness with no verdict falls back to pi"
mkdir -p "$TMP/fakebin"
printf '#!/bin/sh\necho "STATUS: APPROVED"\n' > "$TMP/fakebin/pi"; chmod +x "$TMP/fakebin/pi"
ok_c "cd $WT && env -u HK_STUB_CMD HK_REVIEWER=hermes PATH=$TMP/fakebin:$PATH $HK review"
[ "$(jq -r '.reviewer_harness' "$WT/.agent/review.json")" = pi ] && pass "the fallback named pi" || bad "fallback did not name pi"
[ "$(jq -r '.status' "$WT/.agent/review.json")" = APPROVED ] && pass "the fallback recorded a verdict" || bad "fallback status wrong"
has "said it fell back" 'falling back to pi'
ok_c "cd $WT && git add done.txt && git commit -qm add-marker"

step "freshness: a changed diff voids the old receipt"
( cd "$WT" && echo more >> done.txt )
no_c "cd $WT && git commit -qm stale"
has "hook caught the stale receipt" 'changed after the receipt'

step "hk close re-verifies, compares the hash, then commits"
ok_c "cd $WT && $HK verify"
ok_c "cd $WT && $HK review"
ok_c "cd $WT && $HK close"; has "close matched the diff" 'receipt and review both match'
ok_c "cd $WT && $HK close --commit"
[ "$(git -C "$WT" rev-list --count HEAD)" = 3 ] && pass "the close commit landed" || bad "unexpected commit count"

step "hk archive refuses before the branch reaches origin"
no_c "$HK archive 01-marker --apply"; has "refused: not merged" 'is not in origin/develop'

step "after merge and sync, archive moves the worktree and git still knows it"
git -C "$HK_ROOT/repos/app" merge -q --no-ff feat/01-marker -m 'merge 01'
git -C "$HK_ROOT/repos/app" push -q origin develop
ok_c "$HK archive 01-marker --apply"
[ -d "$HK_ROOT/archives/01-marker/app" ] && pass "folder now under archives/<task>/<repo>" || bad "not archived"
[ ! -e "$WT" ] && pass "features/ folder is gone" || bad "features/ folder still there"
git -C "$HK_ROOT/repos/app" worktree list | grep -q "$HK_ROOT/archives/01-marker" \
  && pass "worktree registration survived the move" || bad "registration broken"

step "scope: an edit outside the write list makes the receipt red"
cat > "$TMP/tickets/02-scope.md" <<'EOF'
# 02: touches the wrong file

**Status:** ready-for-local
**Repo:** app
**Edit:** done.txt
**Read:** README.md
**Test:** none
**Check:** test -f done.txt

## Goal
Proof that hk flags an edit outside the write list.

## Done when
- The Check above exits 0.

## Out of scope
README.md
EOF
ok_c "$HK new $TMP/tickets/02-scope.md"
WT2="$HK_ROOT/features/02-scope/app"
( cd "$WT2" && echo x >> README.md && echo y > done.txt )
no_c "cd $WT2 && $HK verify"; has "hk flagged README.md" 'outside the write list'

step "the harness hook blocks a commit in a worktree with a red receipt"
rc=0
printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"},"cwd":"%s"}' "$WT2" \
  | "$HK_DIR/hooks/claude-pretool.sh" >/tmp/hk-out 2>&1 || rc=$?
[ "$rc" -eq 2 ] && pass "claude hook returned exit 2, which blocks the call" || bad "claude hook exit was $rc, expected 2"
rc=0
printf '{"tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"%s"}' "$WT2" \
  | "$HK_DIR/hooks/claude-pretool.sh" >/tmp/hk-out 2>&1 || rc=$?
[ "$rc" -eq 0 ] && pass "claude hook ignores a command that is not a commit" || bad "claude hook blocked a plain command"
rc=0
"$HK" check "$WT2" >/tmp/hk-out 2>&1 || rc=$?
[ "$rc" -ne 0 ] && has "hk check names the reason" 'outside|verdict' ; true

step "the standard: hk new reads the folder shape and the branch prefix from policy.json"
grep -q '"path_shape"' "$HK_DIR/../policy.json" 2>/dev/null || true
[ "$(jq -r '.path_shape' "${HK_POLICY:-$HOME/.config/hk/policy.json}")" = "features/<task>/<repo>" ] \
  && pass "policy names the shape" || bad "policy shape missing"
[ "$(jq -r '.branch_prefixes | join(",")' "${HK_POLICY:-$HOME/.config/hk/policy.json}")" = "feat,fix,chore" ] \
  && pass "policy names feat, fix, chore" || bad "policy prefixes wrong"

step "hk audit finds a worktree that breaks the standard"
git -C "$HK_ROOT/repos/app" worktree add -q -b feature/bad-shape "$HK_ROOT/features/badshape" develop
ok_c "$HK audit"
grep -q "features/badshape" /tmp/hk-out && pass "audit listed the bad worktree" || bad "audit missed it"
grep -q "feature/bad-shape" /tmp/hk-out && pass "audit named the bad branch" || bad "audit missed the branch"

step "hk repair moves it and renames the branch"
ok_c "$HK repair badshape --apply"
[ -d "$HK_ROOT/features/badshape/app" ] && pass "now under features/<task>/<repo>" || bad "repair did not move it"
# The name part survives; only the prefix is swapped.
[ "$(git -C "$HK_ROOT/features/badshape/app" branch --show-current)" = "feat/bad-shape" ] \
  && pass "branch prefix swapped, name kept" || bad "branch not renamed correctly"
"$HK" audit >/tmp/hk-out 2>&1; grep -q "features/badshape \[" /tmp/hk-out && bad "still listed as a violation" || pass "no longer a violation"

step "hk adopt writes a contract for a worktree made without hk"
git -C "$HK_ROOT/repos/app" worktree add -q -b fix/7-note "$HK_ROOT/features/7-note/app" develop
ok_c "cd $HK_ROOT/features/7-note/app && $HK adopt"
[ -f "$HK_ROOT/features/7-note/app/.agent/contract.json" ] && pass "contract written by adopt" || bad "no contract"
[ "$(jq -r '.branch' "$HK_ROOT/features/7-note/app/.agent/contract.json")" = "fix/7-note" ] \
  && pass "contract records the branch" || bad "branch not recorded"
"$HK" audit >/tmp/hk-out 2>&1; grep -q "features/7-note" /tmp/hk-out && bad "adopted worktree still a violation" || pass "adopted worktree follows the standard"


step "block mode stops a commit on a branch outside feat, fix, chore"
git -C "$HK_ROOT/repos/app" worktree add -q -b feature/blockme "$HK_ROOT/features/blockme" develop
"$HK" policy set shape_check block >/dev/null 2>&1; "$HK" policy set branch_check block >/dev/null 2>&1
( cd "$HK_ROOT/features/blockme" && echo x > note.txt && git add note.txt && git commit -qm blocked ) >/tmp/hk-out 2>&1 \
  && bad "commit went through in block mode" || pass "block mode stopped the commit"
has "hook named the branch rule" "does not start with feat fix chore"
"$HK" policy set shape_check warn >/dev/null 2>&1; "$HK" policy set branch_check warn >/dev/null 2>&1


step "a prompt over 128 KiB reaches the harness without one huge argument"
. "$HK_DIR/lib.sh"   # harness_run lives in lib.sh; the suite otherwise drives hk only
# Linux caps one command-line argument at 131072 bytes. harness_run must not put the
# prompt text in an argument. A fake claude and pi record the longest argument they got.
mkdir -p "$TMP/shim"
for tool in claude pi; do
  cat > "$TMP/shim/$tool" <<'SHIM'
#!/usr/bin/env bash
max=0
for a in "$@"; do [ ${#a} -gt "$max" ] && max=${#a}; done
printf 'argv_count=%s argv_max=%s\n' "$#" "$max" > "$SHIM_OUT"
echo "STATUS: APPROVED"
SHIM
  chmod +x "$TMP/shim/$tool"
done
dd if=/dev/zero bs=1 count=200000 2>/dev/null | tr '\0' 'x' > "$TMP/big-prompt.txt"
export SHIM_OUT="$TMP/shim-out"
for tool in claude pi; do
  PATH="$TMP/shim:$PATH" harness_run "$tool" read "$TMP/big-prompt.txt" "$HK_ROOT/repos/app" >/tmp/hk-out 2>&1 \
    && pass "$tool took the oversized prompt" || { bad "$tool failed on a 200000 byte prompt"; tail -4 /tmp/hk-out; }
  max=$(sed -n 's/.* argv_max=\([0-9]*\).*/\1/p' "$SHIM_OUT" 2>/dev/null)
  [ -n "$max" ] && [ "$max" -lt 131072 ] \
    && pass "$tool longest argument is $max bytes, under 131072" \
    || bad "$tool got one argument of ${max:-unknown} bytes"
done

rm -rf "$TMP"
printf '\nhk tests: %s failure(s)\n' "$fails"
[ "$fails" -eq 0 ]
