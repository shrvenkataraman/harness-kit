#!/usr/bin/env bash
# Early warning for Claude Code. Claude Code sends hook input as JSON on standard input,
# and exit code 2 blocks the tool call. Any other code only shows the text to the user.
# Register it in ~/.claude/settings.json (hk install prints the snippet):
#   {"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command",
#     "command":"~/Work/scripts/harness/hooks/claude-pretool.sh","timeout":5}]}]}}
# This is advisory. The git hook is the rule, because --dangerously-skip-permissions
# switches these hooks off.
set -uo pipefail
HK_DIR="${HK_DIR:-$HOME/Work/scripts/harness}"

payload=$(cat)
tool=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty')

[ "$tool" = "Bash" ] || exit 0
case "$cmd" in *"git commit"*|*"git push"*) : ;; *) exit 0 ;; esac

wt=$(cd "${cwd:-$PWD}" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null) || exit 0
"$HK_DIR/hk" policy-check "$wt" >/dev/null 2>&1 || {
  printf 'hk: this worktree breaks the standard: %s/%s/<task>/<repo> with a feat, fix or chore branch.\n' \
    "$(cd "$HK_DIR" && . ./lib.sh && policy root)" "$(cd "$HK_DIR" && . ./lib.sh && policy work_dir)" >&2
  exit 2
}
[ -f "$wt/.agent/contract.json" ] || exit 0
"$HK_DIR/hk" check "$wt" >/dev/null 2>&1 && exit 0

printf 'hk: no fresh receipt and review for this diff. Run: cd %s && hk verify && hk review\n' "$wt" >&2
exit 2
