harness_pi() { local mode="$1" pf="$2" wt="$3"; local t="${HK_TIMEOUT:-900}"
  # A reviewer never edits, and always runs on the local provider (localhost:9090/v1).
  if [ "$mode" = read ]; then
    # The reviewer model is explicit: the default model (HK_MODEL) unless HK_REVIEW_MODEL says otherwise.
    timeout "$t" pi -p --provider local --model "${HK_REVIEW_MODEL:-$HK_MODEL}" \
      --thinking "${HK_REVIEW_THINKING:-low}" --no-session --no-skills --no-extensions --no-mcp \
      --tools read,grep,find,ls --append-system-prompt "$pf" "Do the audit now." </dev/null
    return
  fi
  local pm=(); [ -n "${HK_PI_MODEL:-}" ] && pm=(--model "$HK_PI_MODEL")   # unset: pi's own default model
  timeout "$t" pi -p --provider "${HK_PI_PROVIDER:-local}" "${pm[@]}" \
    --thinking "${HK_PI_THINKING:-low}" --no-session --no-skills --no-extensions \
    --tools read,edit,write,bash --append-system-prompt "$pf" "Do the task now." </dev/null
}
