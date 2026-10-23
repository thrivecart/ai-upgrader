install_provider_mock() {
  cat > "$MOCK_BIN/claude" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
prompt="${*: -1}"
case "$prompt" in
  *'DISCOVERY/PLAN ONLY'*)
    printf 'plan\n' >> "$MOCK_CALLS"
    cat "$MOCK_PLAN"
    ;;
  *'INDEPENDENT WHOLE-MILESTONE REVIEW'*|*'Read-only milestone review'*)
    printf 'review\n' >> "$MOCK_CALLS"
    if [ "${MOCK_REVIEW_MUTATION:-none}" = dirty ]; then
      printf 'reviewer mutation\n' >> reviewer-owned.txt
    elif [ "${MOCK_REVIEW_MUTATION:-none}" = commit ]; then
      printf 'reviewer mutation\n' > reviewer-owned.txt
      git add reviewer-owned.txt
      git commit -qm reviewer-mutation
    fi
    cat "$MOCK_REVIEW"
    ;;
  *'The ONLY primary axis allowed to move is: runtime '*)
    printf 'writer:runtime\n' >> "$MOCK_CALLS"
    case "${MOCK_WRITER_MODE:-runtime}" in
      runtime)
        printf 'runtime 2\n' > runtime.txt
        git add runtime.txt
        git commit -qm runtime-upgrade
        ;;
      wrong-axis)
        printf 'runtime 2\n' > runtime.txt
        printf 'framework 2\n' > framework.txt
        git add runtime.txt framework.txt
        git commit -qm wrong-axis
        ;;
      dirty)
        printf 'runtime 2\n' > runtime.txt
        ;;
      no-change) ;;
      edge-block)
        printf '%s\n' 'MILESTONE EDGE: BLOCKED'
        printf '%s\n' '**BLOCKED** — `runtime-1` (runtime `1` -> `2`): synthetic incompatibility'
        ;;
      *) exit 91 ;;
    esac
    ;;
  *'The ONLY primary axis allowed to move is: framework '*)
    printf 'writer:framework\n' >> "$MOCK_CALLS"
    printf 'framework 2\n' > framework.txt
    git add framework.txt
    git commit -qm framework-upgrade
    ;;
  *)
    printf 'unexpected\n' >> "$MOCK_CALLS"
    exit 92
    ;;
esac
MOCK
  chmod +x "$MOCK_BIN/claude"
}

mock_call_count() {
  local kind="$1"
  awk -v kind="$kind" '$0==kind {n++} END{print n+0}' "$MOCK_CALLS"
}
