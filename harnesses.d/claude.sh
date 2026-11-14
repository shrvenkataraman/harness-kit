harness_claude() { local mode="$1" pf="$2" wt="$3"; local t="${HK_TIMEOUT:-900}"
  # A worker may edit. A reviewer never may, so it gets read tools only.
  if [ "$mode" = work ]; then
    timeout "$t" claude -p --model "${HK_CLAUDE_MODEL:-$HK_MODEL}" --permission-mode acceptEdits \
      --allowedTools Read Edit Write Bash --append-system-prompt-file "$pf" "Do the task now." </dev/null
  else
    timeout "$t" claude -p --model "${HK_CLAUDE_MODEL:-$HK_MODEL}" \
      --allowedTools Read Grep Glob --append-system-prompt-file "$pf" "Do the audit now." </dev/null
  fi
}
