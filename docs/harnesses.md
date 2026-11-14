# Writing a harness

A harness is one shell file that runs one model session for hk.

## File contract

Put `<name>.sh` in a harness folder. The file defines one function, `harness_<name>`. A `-` in the name becomes `_` in the function.

```bash
harness_<name> <mode> <prompt-file> <worktree>
```

- `mode` is `work` or `read`.
  - `work`: the session may edit files in the worktree.
  - `read`: the session must not edit anything. `hk review` uses this mode.
- `prompt-file` is a file with the task or audit prompt.
- `worktree` is the folder to work in.

The function writes its answer to stdout. Exit code 0 means the session finished. A non-zero code means failure; 124 means timeout. A `read` run that prints no verdict counts as no review.

The harness name may contain only `a-z`, `0-9`, `_` and `-`.

## Search order

`harness_dirs` in `lib.sh` gives the folders. hk uses the first folder that holds `<name>.sh`.

1. `$HK_HARNESS_DIR`, when set.
2. `${XDG_CONFIG_HOME:-$HOME/.config}/hk/harnesses.d`
3. `$HK_DIR/harnesses.d`, the built-in folder.

## Example

```bash
# ~/.config/hk/harnesses.d/mytool.sh
harness_mytool() { local mode="$1" pf="$2" wt="$3"; local t="${HK_TIMEOUT:-900}"
  cd "$wt" || return 1
  if [ "$mode" = read ]; then
    timeout "$t" mytool --read-only --prompt-file "$pf" </dev/null
  else
    timeout "$t" mytool --allow-edits --prompt-file "$pf" </dev/null
  fi
}
```

Run it with `hk worker --harness mytool` or `HK_REVIEWER=mytool hk review`.

## Built-in harnesses

- `pi`: Pi on the `local` provider. `read` mode uses read-only tools.
- `claude`: Claude Code in headless mode. Model from `HK_CLAUDE_MODEL`.
- `opencode`: opencode with the read-only `plan` agent. Default reviewer.
- `stub`: runs `HK_STUB_CMD`. For tests; makes no model call.
