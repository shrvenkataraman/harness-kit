# hk — harness kit

One tool that holds the four rules for every harness on this machine: pi, Claude Code, Hermes,
Orca, and anything installed tomorrow. The rules live in files, in git, and in this tool, not
inside one harness's config.

## The four rules

1. A written task limit before any code: `.agent/contract.json`.
2. A separate checkout per task: `$HK_ROOT/features/<task>`.
3. Only command output proves the work: `hk verify` runs the check commands itself.
4. A separate session checks the diff: `hk review` starts a different harness.

## Commands

| Command | What it does |
| --- | --- |
| `hk new <ticket.md> [--repo R] [--base B]` | Writes the contract, makes the worktree, prints the next step |
| `hk worker [ticket.md] [--harness pi]` | One headless session in the worktree, then verify |
| `hk verify` | Runs every check command, checks the write list and the size, writes `receipt.json` |
| `hk review` | A harness beside the writer attacks the diff, writes `review.json` |
| `hk close [--commit] [--push] [--sync]` | Re-verify, compare the diff hash, then act |
| `hk archive <task> [--apply]` | `git worktree move` into `archives/`, only after the branch is merged and synced |
| `hk install --repo R|--all [--apply] [--refresh]` | Write or refresh the git hook, print harness hooks |
| `hk adopt [worktree]` | Write a contract for a worktree made outside hk, then report the standard |
| `hk audit` | Every worktree that breaks the folder shape or the branch prefix |
| `hk repair <task> [--apply]` | Move a worktree to `features/<task>/<repo>` and rename its branch |
| `hk policy [get <k>\|set <k> <v>]` | Read or change the standard in `~/.config/hk/policy.json` |
| `hk check [worktree]` | The single rule the hooks run: fresh receipt + fresh review + matching hash |
| `hk status` | Verdicts for every contract under `features/` |

## Layout standard

```
$HK_ROOT/repos/<repo>             base checkout, the branch you merge into
$HK_ROOT/features/<task>/<repo>   the worktree an agent edits
$HK_ROOT/archives/<task>/<repo>   after the merge, the origin update and the local sync
```

Branch prefixes are `feat`, `fix` and `chore`. Both rules live in `~/.config/hk/policy.json`, where
`shape_check` and `branch_check` take `warn` or `block`. `hk new` reads the prefix from the task
name, so `fix-162-x` becomes branch `fix/162-x`.

`hk` reads the base ref per repo. It uses `--base`, then `$HK_BASE_REF`, then `origin/HEAD`,
then the branch `repos/<repo>` sits on. It never assumes `develop`, because `arxiv-digest` sits
on `master`.

## Trust rules

- `hk verify` runs the commands. A file a model wrote proves nothing, so a model-written receipt
  is not read.
- `hk review` always runs Pi on the `local` provider (`http://127.0.0.1:9090/v1`) with read-only tools, and records the harness.
- `receipt.json` stores `diff_hash`, the identity of the pending change. `hk close` and both hooks
  recompute it, so an approval from an older diff cannot unlock a new commit.
- `.agent/` is added to the repo's exclude file, so state files never enter a diff.

## Enforcement levels, strongest first

1. **git**: `$HK_ROOT/repos/<repo>/.git/hooks/pre-commit`, written by `hk install --apply`.
   Your global dispatcher at `~/.git-hooks` runs it and passes the exit code, so it covers every
   worktree of that repo and every harness.
2. **files**: `.agent/contract.json`, `receipt.json`, `review.json`.
3. **harness hooks**: `hooks/claude-pretool.sh` (exit code 2 blocks, JSON on stdin) and
   `hooks/pi-hk.ts` (`tool_call` returns `{ block: true, reason }`). Advisory only. Hermes has no
   hook point here.

`git commit --no-verify` skips level 1, and `--dangerously-skip-permissions` skips level 3, so run
`hk close` before a push, and let CI or the merge check run the tests again.

## Escape hatches

`HK_ALLOW_COMMIT=1` skips the check for one commit. `HK_DISABLE=1` turns it off for a command.

## Tests

```
tests/run_tests.sh      # 40 checks, a throwaway repository under /tmp, nothing outside it touched
```

## Settings

`HK_ROOT` (default `~/Work`), `HK_TIMEOUT` (900), `HK_MAX_LINES` (150), `HK_MAX_FILES` (5),
`HK_PI_MODEL` (`qwen3.8-flash-next`), `HK_CLAUDE_MODEL` (`qwen3.8-flash-next`), `HK_REVIEW_MODEL` (`qwen3.8-flash-next`), `HK_REVIEW_THINKING` (`low`).
`HK_REVIEWER` (`opencode`) picks the review harness: `opencode`, `pi` or `claude`.
The default reviewer runs `llama-swap/qwen3.8-flash-next` with the read-only `plan` agent. `HK_OPENCODE_MODEL` overrides the model,
`HK_OPENCODE_BIN` the binary (default: PATH, else the newest mise install). Backup: when the first reviewer
returns no verdict (missing binary, offline, expired auth), `hk review` re-runs on pi with
`HK_REVIEW_MODEL` (`qwen3.8-flash-next`) and records that harness in `review.json`.
A `stub` harness exists for tests, so the suite runs with no model call.
