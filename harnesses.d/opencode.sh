opencode_bin() { # HK_OPENCODE_BIN wins; then PATH; then the newest mise install
  [ -n "${HK_OPENCODE_BIN:-}" ] && { printf '%s\n' "$HK_OPENCODE_BIN"; return 0; }
  command -v opencode >/dev/null 2>&1 && { command -v opencode; return 0; }
  local newest
  newest=$(ls -d "$HOME"/.local/share/mise/installs/opencode/*/node_modules/.bin/opencode 2>/dev/null | sort -V | tail -1)
  [ -n "$newest" ] && { printf '%s\n' "$newest"; return 0; }
  return 1
}

harness_opencode() { local mode="$1" pf="$2" wt="$3"; local t="${HK_TIMEOUT:-900}"
  # A reviewer never edits: the plan agent is read-only. The default model is opencode-hosted
  # (llama-swap/qwen3.8-flash-next), the one local model.
  # opencode has no system-prompt flag, so the prompt file is read from disk by the agent.
  local obin; obin=$(opencode_bin) || die "opencode is not installed (HK_OPENCODE_BIN points to it)"
  local oa=plan; [ "$mode" = work ] && oa=build
  timeout "$t" "$obin" run --agent "$oa" \
    -m "${HK_OPENCODE_MODEL:-llama-swap/qwen3.8-flash-next}" --auto --archived \
    "Read the file $pf. It is your full task. Follow it exactly, then answer." </dev/null
}
