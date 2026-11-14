#!/usr/bin/env bash
# hk lint runner. The git pre-commit hook calls it; `hk verify` checks may call it too.
#
# Usage: lint.sh [--staged|--changed|--all] [worktree]
#   --staged   files in the git index (default, what the pre-commit hook uses)
#   --changed  files that differ from HEAD, plus untracked files
#   --all      every tracked file
#
# Config: <worktree>/.hk/lint, tracked in the repo. One "<linter> [subdir]" per line.
# "#" starts a comment. subdir is where the linter's config and module root live (default ".").
# No .hk/lint file means no lint for that repo.
#
# Linters: gofmt, govet, golangci, ruff, eslint
# Escape hatch: HK_SKIP_LINT=1 skips this runner for one command.
set -uo pipefail

mode=staged; arg_wt=""
for a in "$@"; do
  case "$a" in
    --staged|--changed|--all) mode=${a#--} ;;
    *) arg_wt=$a ;;
  esac
done

wt=$(git -C "${arg_wt:-.}" rev-parse --show-toplevel 2>/dev/null) || exit 0
cfg="$wt/.hk/lint"
[ -f "$cfg" ] || exit 0
if [ "${HK_SKIP_LINT:-0}" = 1 ]; then echo "hk lint: skipped (HK_SKIP_LINT=1)" >&2; exit 0; fi
cd "$wt" || exit 0

case $mode in
  staged)  mapfile -d '' -t files < <(git diff --cached --name-only --diff-filter=ACMR -z) ;;
  changed) mapfile -d '' -t files < <({ git diff HEAD --name-only --diff-filter=ACMR -z; git ls-files -o --exclude-standard -z; }) ;;
  all)     mapfile -d '' -t files < <(git ls-files -z) ;;
esac

# pick <subdir> <ext-regex>: files under subdir matching the extension, paths relative to subdir.
pick() {
  local sub=$1 re=$2 f
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    [[ "$f" =~ $re ]] || continue
    if [ "$sub" = . ]; then printf '%s\0' "$f"
    elif [[ "$f" == "$sub"/* ]]; then printf '%s\0' "${f#"$sub"/}"; fi
  done
}

# pkg_dirs <file>...: unique "./dir" package paths for go files.
pkg_dirs() {
  local f d; declare -A seen=()
  for f in "$@"; do d=$(dirname "$f"); [ -n "${seen[$d]:-}" ] || { seen[$d]=1; printf './%s\n' "$d"; }; done
}

# find_eslint <subdir>: the project binary, else the base checkout's (worktrees have no node_modules).
find_eslint() {
  local sub=$1 base
  [ -x "$wt/$sub/node_modules/.bin/eslint" ] && { echo "$wt/$sub/node_modules/.bin/eslint"; return; }
  base=$(cd "$(git rev-parse --git-common-dir)/.." 2>/dev/null && pwd) || return 1
  [ -x "$base/$sub/node_modules/.bin/eslint" ] && echo "$base/$sub/node_modules/.bin/eslint"
}

fail=0; ran=0
while read -r name sub _; do
  case "$name" in ''|'#'*) continue ;; esac
  sub=${sub:-.}
  case "$name" in
    gofmt|govet|golangci) mapfile -d '' -t sel < <(pick "$sub" '\.go$') ;;
    ruff)                 mapfile -d '' -t sel < <(pick "$sub" '\.pyi?$') ;;
    eslint)               mapfile -d '' -t sel < <(pick "$sub" '\.tsx?$') ;;
    *) echo "hk lint: unknown linter '$name' in $cfg" >&2; fail=1; continue ;;
  esac
  [ "${#sel[@]}" -gt 0 ] || continue
  ran=$((ran + ${#sel[@]}))

  case "$name" in
    gofmt)
      command -v gofmt >/dev/null || { echo "hk lint: gofmt not found" >&2; fail=1; continue; }
      out=$(cd "$sub" && gofmt -l "${sel[@]}" 2>&1)
      [ -z "$out" ] || { echo "hk lint [gofmt] needs formatting (run gofmt -w):" >&2; echo "$out" >&2; fail=1; }
      ;;
    govet)
      command -v go >/dev/null || { echo "hk lint: go not found" >&2; fail=1; continue; }
      mapfile -t pk < <(pkg_dirs "${sel[@]}")
      (cd "$sub" && go vet "${pk[@]}") >&2 || { echo "hk lint [govet] failed" >&2; fail=1; }
      ;;
    golangci)
      if ! command -v golangci-lint >/dev/null; then
        echo "hk lint [golangci] SKIPPED: golangci-lint is not installed" >&2; continue
      fi
      mapfile -t pk < <(pkg_dirs "${sel[@]}")
      (cd "$sub" && golangci-lint run "${pk[@]}") >&2 || { echo "hk lint [golangci] failed" >&2; fail=1; }
      ;;
    ruff)
      if command -v ruff >/dev/null; then rc=(ruff)
      elif command -v uvx >/dev/null; then rc=(uvx ruff)
      else echo "hk lint: ruff not found (install ruff or uv)" >&2; fail=1; continue; fi
      (cd "$sub" && "${rc[@]}" check --force-exclude "${sel[@]}") >&2 || { echo "hk lint [ruff] failed" >&2; fail=1; }
      ;;
    eslint)
      bin=$(find_eslint "$sub") || { echo "hk lint [eslint] SKIPPED: no node_modules/.bin/eslint under $sub (run npm ci)" >&2; continue; }
      (cd "$sub" && "$bin" --max-warnings 0 --report-unused-disable-directives "${sel[@]}") >&2 || { echo "hk lint [eslint] failed" >&2; fail=1; }
      ;;
  esac
done < "$cfg"

if [ "$fail" -ne 0 ]; then
  echo "hk lint: BLOCK. Fix the findings above, or skip once with HK_SKIP_LINT=1." >&2
  exit 1
fi
[ "$ran" -gt 0 ] && echo "hk lint: ok ($ran file checks, mode $mode)" >&2
exit 0
