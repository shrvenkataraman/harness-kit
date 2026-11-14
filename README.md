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

## Install

```
git clone <repo-url> "$HK_ROOT/scripts/harness"
ln -s "$HK_ROOT/scripts/harness/hk" ~/.local/bin/hk     # any folder on PATH
hk install --all --apply                                 # write the git pre-commit hook
```

`hk` needs `git`, `jq` and `python3`. Set `$HK_ROOT` to the folder that holds `repos/`, `features/` and `archives/`.

## Policy keys

`~/.config/hk/policy.json` holds the standard. Read a key with `hk policy get <key>`. Change one with `hk policy set <key> <value>`. A key that is not set uses its default. When a check says `block`, a bad path or branch stops the commit.

| Key | Default | Meaning |
| --- | --- | --- |
| `root` | `~/Work` | Base folder of all checkouts. `HK_ROOT` wins when set. |
| `base_dir` | `repos` | Folder under the root for base checkouts. |
| `work_dir` | `features` | Folder under the root for task worktrees. |
| `archive_dir` | `archives` | Folder under the root for finished worktrees. |
| `branch_default_prefix` | `feat` | Branch prefix when the task name has none. |
| `shape_check` | `warn` | `warn` or `block` when a worktree is not `<work_dir>/<task>/<repo>`. |
| `branch_check` | `warn` | `warn` or `block` when a branch prefix is not `feat`, `fix` or `chore`. |
| `max_lines` | `150` | Default diff line limit written to a new contract. |
| `max_files` | `5` | Default changed-file limit written to a new contract. |
| `model` | `qwen3.8-flash-next` | Default model for all harnesses (`HK_MODEL`). |

## Environment variables

Every `HK_*` variable that `hk`, `lib.sh` and `harnesses.d/*.sh` read:

| Variable | Default | Meaning |
| --- | --- | --- |
| `HK_ROOT` | `~/Work` | Base folder of `repos/`, `features/`, `archives/`. |
| `HK_ROOT_OVERRIDE` | unset | Replaces the root for layout paths; used by tests. |
| `HK_DIR` | `$HK_ROOT/scripts/harness` | Folder that holds `hk`, `lib.sh`, `harnesses.d` and `hooks`. |
| `HK_BIN` | real path of `hk` | Set by `hk` itself; the path of the running script. |
| `HK_VERSION` | `1` | Contract schema version written by `hk`. |
| `HK_POLICY` | `~/.config/hk/policy.json` | Path of the policy file. |
| `HK_BASE_REF` | unset | Base ref used when `--base` is absent. |
| `HK_MODEL` | policy `model` | Default model for every harness. |
| `HK_TIMEOUT` | `900` | Seconds before a harness run stops. |
| `HK_MAX_LINES` | `150` | Diff line limit for a new contract. |
| `HK_MAX_FILES` | `5` | Changed-file limit for a new contract. |
| `HK_PI_MODEL` | unset | Model for Pi in `work` mode. |
| `HK_PI_PROVIDER` | `local` | Pi provider in `work` mode. |
| `HK_PI_THINKING` | `low` | Pi thinking level in `work` mode. |
| `HK_CLAUDE_MODEL` | `HK_MODEL` | Model for the `claude` harness. |
| `HK_REVIEW_MODEL` | `HK_MODEL` | Model for Pi in `read` mode and the review fallback. |
| `HK_REVIEW_THINKING` | `low` | Pi thinking level in `read` mode. |
| `HK_REVIEWER` | auto | Review harness: `opencode`, `pi` or `claude`. |
| `HK_OPENCODE_MODEL` | `llama-swap/$HK_MODEL` | Model for the `opencode` harness. |
| `HK_OPENCODE_BIN` | PATH, then newest mise install | Path of the `opencode` binary. |
| `HK_HARNESS_DIR` | unset | Extra harness folder, searched first. See `docs/harnesses.md`. |
| `HK_STUB_CMD` | `echo 'STATUS: APPROVED'` | Command the `stub` harness runs; tests only. |
| `HK_ALLOW_COMMIT` | unset | `1` skips the commit check for one commit. |
| `HK_DISABLE` | unset | `1` turns the check off for a command. |

Harness details: `docs/harnesses.md`. Contributing: `CONTRIBUTING.md`.

## License

MIT. See `LICENSE`.
