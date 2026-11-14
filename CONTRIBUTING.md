# Contributing

## Run the tests

```
bash tests/run_tests.sh
```

The suite uses a throwaway repository under `/tmp` and makes no model call. All checks must pass before a PR.

## Shellcheck

Run `shellcheck hk lib.sh harnesses.d/*.sh hooks/*.sh tests/*.sh`. Fix each warning, or add a `# shellcheck disable=SCxxxx` comment with a reason.

## Add a test

1. Add `tests/test_<topic>.sh`. Use `pass` and `bad` helpers as in `tests/test_docs.sh`.
2. Exit 0 when all checks pass, non-zero otherwise.
3. Use the `stub` harness (`HK_STUB_CMD`) instead of a real model.
4. Run `bash tests/run_tests.sh` and confirm the new test runs.

## Docs

Every new subcommand, `HK_*` variable and policy key needs a line in `README.md`. `tests/test_docs.sh` fails without it.

## Pull requests

- Branch name starts with `feat/`, `fix/` or `chore/`.
- One change per PR, small diff, with a test.
- Describe the change and the test result in the PR text.
