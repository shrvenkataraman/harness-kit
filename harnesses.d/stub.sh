harness_stub() { local mode="$1" pf="$2" wt="$3"; local t="${HK_TIMEOUT:-900}"
  # Tests only. Lets the whole flow run without spending a model call.
  eval "${HK_STUB_CMD:-echo 'STATUS: APPROVED'}"
}
