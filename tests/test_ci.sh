#!/usr/bin/env bash
HERE=$(cd "$(dirname "$0")" && pwd)
CI="$HERE/../.github/workflows/ci.yml"
fail=0
check() { # label, pattern
  if [ -f "$CI" ] && grep -Eq -- "$2" "$CI"; then echo "PASS $1"; else echo "FAIL $1"; fail=1; fi
}
check "AC1: for loop over tests/*.sh" 'for t in tests/\*\.sh; do bash "\$t" \|\| exit 1; done'
check "AC1: jq install" 'sudo apt-get install -y jq'
check "AC1: checkout v4" 'actions/checkout@v4'
check "AC1: git identity" 'git config --global user.email ci@example.com && git config --global user.name ci'
check "AC1: job test on ubuntu-latest" 'runs-on: ubuntu-latest'
check "AC2: trigger push" '^on:.*\bpush\b|^[[:space:]]+push:|^[[:space:]]*-[[:space:]]*push\b'
check "AC2: trigger pull_request" '^on:.*pull_request|^[[:space:]]+pull_request:|^[[:space:]]*-[[:space:]]*pull_request\b'
exit $fail
