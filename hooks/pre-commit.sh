#!/usr/bin/env bash
# hk pre-commit check. Installed into <repo>/.git/hooks/pre-commit by `hk install --apply`.
# Your global dispatcher at ~/.git-hooks runs this file and passes its exit code through,
# so one install covers every worktree of that repo, whatever harness made the change.
# Escape hatches, in order of honesty: HK_ALLOW_COMMIT=1 (this commit only),
# HK_DISABLE=1, then `git commit --no-verify` (skips every git hook, so keep hk close before a push).
set -uo pipefail

[ "${HK_ALLOW_COMMIT:-0}" = 1 ] && exit 0
[ "${HK_DISABLE:-0}" = 1 ] && exit 0

HK_DIR="${HK_DIR:-$HOME/Work/scripts/harness}"
[ -x "$HK_DIR/hk" ] || { printf 'hk hook: %s/hk missing, allowing the commit\n' "$HK_DIR" >&2; exit 0; }

wt=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# The layout and branch standard runs even without a contract.
if ! msg=$("$HK_DIR/hk" policy-check "$wt" 2>&1); then
  printf '%s\n' "$msg" >&2
  printf 'hk BLOCK: repair with: hk repair <task> --apply, or allow with: hk policy set shape_check warn\n' >&2
  exit 1
fi
[ -n "$msg" ] && printf '%s\n' "$msg" >&2

# Lint staged files when the repo opts in with a tracked .hk/lint file. Runs with or without a contract.
if [ -f "$wt/.hk/lint" ]; then
  "$HK_DIR/hooks/lint.sh" --staged "$wt" || exit 1
fi

[ -f "$wt/.agent/contract.json" ] || exit 0      # plain work, no contract, no receipt rule

if ! msg=$("$HK_DIR/hk" check "$wt" 2>&1); then
  printf 'hk BLOCK: %s\n' "$msg" >&2
  printf 'hk BLOCK: fix it, then run: cd %s && hk verify && hk review\n' "$wt" >&2
  exit 1
fi
exit 0
