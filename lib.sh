#!/usr/bin/env bash
# hk shared functions. Sourced by `hk` and by the installed git hook.
# Layout standard (this machine):
#   root         base folder of everything below (policy key, env HK_ROOT wins)
#   base_dir     default repos/      <repo>  default branch checkout, read-only for agents
#   work_dir     default features/   <task>  worktree with the agent branch
#   archive_dir  default archives/   <task>  worktree after the branch is merged and synced
# Nothing here writes outside the worktree except `hk close --sync` and `hk archive --apply`.

HK_ROOT="${HK_ROOT:-$HOME/Work}"
HK_VERSION="1"
HK_DIR="${HK_DIR:-$HK_ROOT/scripts/harness}"

die() { printf 'hk ERROR: %s\n' "$*" >&2; exit 1; }
say() { printf 'hk: %s\n' "$*"; }
ok()  { printf 'hk OK: %s\n' "$*"; }

need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

# ---------- ticket parsing (grill-to-local ticket template) ----------
# Reads **Key:** lines. Keys: Repo, Edit, Read, Check, Test, Status.
ticket_field() { # ticket_field <file> <key>
  sed -n "s/^\*\*$2:\*\* *//p" "$1" | head -1
}

ticket_checks() { # one check command per ticket; empty when the ticket has none
  local c; c=$(ticket_field "${1:-/dev/null}" Check)
  [ -n "$c" ] && printf '%s\n' "$c"
  return 0
}

# comma separated list -> one item per line
csv_to_lines() { tr ',' '\n' | sed 's/^ *//; s/ *$//; /^$/d'; }

# ---------- paths ----------
task_id_from() { # ticket file path -> short task id
  local b; b=$(basename "$1"); b=${b%.md}
  printf '%s\n' "$b"
}

repo_dir()  { printf '%s\n' "$(hk_root)/$(policy base_dir repos)/$1"; }

# current worktree root, or fail
require_worktree() {
  local top; top=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git worktree: $PWD"
  printf '%s\n' "$top"
}

contract_of() { printf '%s/.agent/contract.json\n' "$1"; }
receipt_of()  { printf '%s/.agent/receipt.json\n'  "$1"; }
review_of()   { printf '%s/.agent/review.json\n'   "$1"; }

require_contract() {
  local wt="$1" f; f=$(contract_of "$wt")
  [ -f "$f" ] || die "no contract at $f. Run: hk new <ticket.md>"
  printf '%s\n' "$f"
}

jqr() { jq -r "$1" "$2" 2>/dev/null; }

# ---------- base ref, per repo, never assumed ----------
# Order: explicit --base, $HK_BASE_REF, ticket **Base:**, origin/HEAD, the branch
# repos/<repo> sits on (unless it is an agent branch), else fail with a hint.
base_ref_for() { # base_ref_for <repo-dir> [explicit]
  local rd="$1" explicit="${2:-}" ref cur
  for ref in "$explicit" "${HK_BASE_REF:-}"; do
    [ -n "$ref" ] && { printf '%s\n' "$ref"; return 0; }
  done
  if ref=$(git -C "$rd" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null); then
    printf '%s\n' "${ref#origin/}"; return 0
  fi
  cur=$(git -C "$rd" branch --show-current 2>/dev/null)
  case "$cur" in ''|agent/*) : ;; *) printf '%s\n' "$cur"; return 0 ;; esac
  die "no base ref for $rd. Set one: git -C $rd remote set-head origin -a, or pass --base <branch>"
}


# ---------- policy (the standard, in one file) ----------
# ~/.config/hk/policy.json holds the layout and branch rules. Change it, not the code.
HK_POLICY="${HK_POLICY:-$HOME/.config/hk/policy.json}"

# The environment wins over the file, so tests and other checkouts can point hk elsewhere.
hk_root() { printf '%s
' "${HK_ROOT_OVERRIDE:-${HK_ROOT:-$(policy root "$HOME/Work")}}"; }

policy() { # policy <key> [default]
  local k="$1" d="${2:-}" v=""
  [ -f "$HK_POLICY" ] && v=$(jq -r --arg k "$k" '.[$k] // empty' "$HK_POLICY" 2>/dev/null)
  if [ -n "$v" ]; then printf '%s\n' "$v"; else printf '%s\n' "$d"; fi
}

policy_list() { # policy_list <key> -> one item per line
  jq -r ".[\"$1\"][]? // empty" "$HK_POLICY" 2>/dev/null
}

branch_prefixes() { policy_list branch_prefixes | tr '\n' ' '; }

branch_prefix_allowed() { # branch_prefix_allowed <branch>
  local b="${1:-}" pre p
  pre="${b%%/*}"
  [ "$pre" = "$b" ] && return 1
  for p in $(branch_prefixes); do [ "$pre" = "$p" ] && return 0; done
  return 1
}

branch_for() { # branch_for <task> [explicit] -> <type>/<slug>, validated against the policy
  local task="$1" explicit="${2:-}"
  if [ -n "$explicit" ]; then
    branch_prefix_allowed "$explicit" \
      || die "branch '$explicit' must start with one of: $(branch_prefixes)"
    printf '%s\n' "$explicit"; return 0
  fi
  # Read the type from the task name: "fix/162-x", "fix-162-x", "chore-3-x", else the default.
  # A digit after the dash marks a ticket number, so "fixed-bug" stays feat/fixed-bug.
  local pre slug
  pre=$(policy branch_default_prefix feat); slug="$task"
  case "$task" in
    */*)  local p=${task%%/*}; slug=${task#*/}
          case "$p" in feat|fix|chore) pre=$p ;; *) slug="$task" ;; esac ;;
    fix-[0-9]*)   pre=fix; slug=${task#fix-} ;;
    fix_[0-9]*)   pre=fix; slug=${task#fix_} ;;
    chore-[0-9]*) pre=chore; slug=${task#chore-} ;;
  esac
  printf '%s/%s\n' "$pre" "$slug"
}

worktree_path() { # worktree_path <task> <repo> -> <root>/features/<task>/<repo>
  printf '%s/%s/%s\n' "$(hk_root)/$(policy work_dir features)" "$1" "$2"
}

archive_path() { # archive_path <task> <repo> -> <root>/archives/<task>/<repo>
  printf '%s/%s/%s\n' "$(hk_root)/$(policy archive_dir archives)" "$1" "$2"
}

shape_ok() { # shape_ok <worktree> -> 0 when the path is <root>/{features|archives}/<task>/<repo>
  local wt="$1" root wd ad rel
  root=$(hk_root); wd=$(policy work_dir features); ad=$(policy archive_dir archives)
  # archives hold finished history, so their depth is not checked
  case "$wt" in
    "$root/$ad"/*) [ "${wt#"$root/$ad/"}" != "$wt" ] && return 0 ;;
  esac
  case "$wt" in
    "$root/$wd"/*/*) rel=${wt#"$root/$wd/"} ;;
    *) return 1 ;;
  esac
  case "$rel" in */*/*) return 1 ;; *) return 0 ;; esac
}

policy_check() { # policy_check <worktree> -> prints the reason; exit 1 only when the policy says block
  local wt="$1" b reason="" bad=0 ms mb
  b=$(git -C "$wt" branch --show-current 2>/dev/null)
  shape_ok "$wt" || { bad=1; reason="path '$wt' is not $(policy root "$HK_ROOT")/$(policy work_dir features)/<task>/<repo>"; }
  if [ -n "$b" ] && ! branch_prefix_allowed "$b"; then
    bad=1; reason="$reason${reason:+; }branch '$b' does not start with $(branch_prefixes)"
  fi
  [ "$bad" -eq 0 ] && return 0
  printf 'hk policy: %s\n' "$reason"
  ms=$(policy shape_check warn); mb=$(policy branch_check warn)
  if [ "$ms" = block ] || [ "$mb" = block ]; then
    printf 'hk policy: fix it with hk repair <task>, or let it pass with hk policy set %s warn\n' \
      "$([ "$ms" = block ] && echo shape_check || echo branch_check)"
    return 1
  fi
  return 0
}

# ---------- default check per repo ----------
# Order: ~/.config/hk/repos.json entry, package.json test script, pytest, go test, else nothing.
default_check_for() { # default_check_for <repo-dir>
  local rd="$1" name; name=$(basename "$rd")
  local cfg="$HOME/.config/hk/repos.json" line
  if [ -f "$cfg" ]; then
    line=$(jq -r --arg n "$name" '.[$n] // empty' "$cfg" 2>/dev/null)
    [ -n "$line" ] && { printf '%s\n' "$line"; return 0; }
  fi
  [ -f "$rd/package.json" ] && jq -e '.scripts.test' "$rd/package.json" >/dev/null 2>&1 \
    && { printf 'npm test\n'; return 0; }
  { [ -d "$rd/tests" ] || [ -f "$rd/pytest.ini" ] || [ -f "$rd/pyproject.toml" ]; } \
    && [ -f "$rd/requirements.txt" -o -f "$rd/pyproject.toml" ] && { printf 'pytest -q\n'; return 0; }
  [ -f "$rd/go.mod" ] && { printf 'go test ./...\n'; return 0; }
  return 0
}

# ---------- diff and hash ----------
# Untracked files are folded in with `git add -N`, so a new file is never invisible.
stage_intent() { git -C "$1" add -N . >/dev/null 2>&1 || true; }

diff_hash() { # content-only identity of all pending changes
  local wt="$1" base="$2"
  stage_intent "$wt"
  { git -C "$wt" diff --binary "HEAD" 2>/dev/null
    git -C "$wt" rev-parse HEAD 2>/dev/null
  } | sha256sum | awk '{print $1}'
}

scope_stats() { # "<files> <lines>"
  local wt="$1"; stage_intent "$wt"
  local stat; stat=$(git -C "$wt" diff --numstat HEAD 2>/dev/null)
  [ -z "$stat" ] && { printf '0 0\n'; return 0; }
  local files lines
  files=$(printf '%s\n' "$stat" | wc -l)
  lines=$(printf '%s\n' "$stat" | awk '{s+=$1+$2} END {print s+0}')
  printf '%s %s\n' "$files" "$lines"
}

changed_files() { local wt="$1"; stage_intent "$wt"; git -C "$wt" diff --name-only HEAD 2>/dev/null; }

# ---------- .agent/ must never pollute a diff ----------
exclude_agent_dir() { # idempotent append to the repo's shared exclude file
  local wt="$1" common
  common=$(git -C "$wt" rev-parse --git-common-dir 2>/dev/null) || return 0
  case "$common" in /*) : ;; *) common="$wt/$common" ;; esac
  mkdir -p "$common/info" 2>/dev/null || return 0
  grep -qx '.agent/' "$common/info/exclude" 2>/dev/null || printf '.agent/\n' >> "$common/info/exclude"
}

# ---------- harness spawning ----------
# Each harness is ONE line. hk_review and hk_worker pick from these.
# The prompt goes over as a file, never as its text: Linux caps one command-line argument
# at 131072 bytes, and a large branch digest passes that. pi takes a path in
# --append-system-prompt (docs/cli.md: text or file contents) and claude has
# --append-system-prompt-file. Both keep the prompt's system-prompt role.
harness_dirs() { # search order: $HK_HARNESS_DIR, user dir, built-in
  [ -n "${HK_HARNESS_DIR:-}" ] && printf '%s\n' "$HK_HARNESS_DIR"
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/hk/harnesses.d" "$HK_DIR/harnesses.d"
}
harness_run() { # harness_run <harness> <mode> <prompt-file> <worktree>
  local h="$1" d
  case "$h" in *[!a-z0-9_-]*|'') die "bad harness name: $h" ;; esac
  for d in $(harness_dirs); do
    if [ -f "$d/$h.sh" ]; then . "$d/$h.sh"; "harness_${h//-/_}" "$2" "$3" "$4"; return; fi
  done
  die "unknown harness: $h (looked in: $(harness_dirs | tr '\n' ' '))"
}

harness_reviewer() { # default: opencode on qwen3.8-flash-next; HK_REVIEWER overrides; tests set HK_STUB_CMD
  . "$HK_DIR/harnesses.d/opencode.sh"
  if [ -n "${HK_STUB_CMD:-}" ]; then printf 'stub\n'; return 0; fi
  if [ -n "${HK_REVIEWER:-}" ]; then printf '%s\n' "$HK_REVIEWER"; return 0; fi
  opencode_bin >/dev/null 2>&1 && { printf 'opencode\n'; return 0; }
  command -v pi >/dev/null 2>&1 && { printf 'pi\n'; return 0; }
  return 1
}

json_escape() { python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'; }
