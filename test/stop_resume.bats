#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_ai_test
  export AI_UPGRADER_CLI="$UPGRADER"
}

install_stopping_fast_gate() {
  local terminal="${1:-pass}"
  cat > Makefile <<MAKE
.PHONY: runtime-fast runtime-milestone
runtime-fast:
	@if [ "\$\${STOP_IN_GATE:-0}" = 1 ]; then "\$\$AI_UPGRADER_CLI" stop >/dev/null; fi
	@$([ "$terminal" = pass ] && printf "grep -qx 'runtime 2' runtime.txt" || printf 'false')
runtime-milestone:
	@grep -qx 'runtime 2' runtime.txt
MAKE
  git add Makefile
  git commit -qm stop-fixture
}

@test "P0-22 STOP during a gate records only that terminal gate and starts nothing else" {
  install_stopping_fast_gate pass
  export STOP_IN_GATE=1

  run_cli upgrade --provider claude --goal 'Upgrade runtime'

  [ "$status" -eq 0 ]
  [ "$(state_value STOP_REQUESTED)" = 1 ]
  [ "$(state_value FAST_GATE)" = PASS ]
  [ "$(state_value MILESTONE_GATE)" != PASS ]
  [ "$(state_value MILESTONE_STATUS_VALUE)" != ACCEPTED ]
  [ "$(mock_call_count writer:runtime)" -eq 1 ]
}

@test "P0-23 resume restores milestone cursor and does not duplicate completed gate" {
  install_stopping_fast_gate pass
  export STOP_IN_GATE=1
  cli_ok upgrade --provider claude --goal 'Upgrade runtime'
  saved_base="$(state_value BASE_SHA)"
  saved_head="$(state_value HEAD_SHA)"
  saved_good="$(state_value LAST_KNOWN_GOOD_SHA)"
  fast_log_count="$(find .upgrade/archive/logs -name '*.fast_gate.*' | wc -l | tr -d ' ')"
  unset STOP_IN_GATE

  run_cli resume

  [ "$status" -eq 0 ]
  [ "$(state_value PHASE)" = COMPLETE ]
  [ "$(state_value BASE_SHA)" = "$saved_base" ]
  [ "$(state_value HEAD_SHA)" = "$saved_head" ]
  [ "$saved_good" = "$BASE_SHA" ] || [ -n "$saved_good" ]
  [ "$(find .upgrade/archive/logs -name '*.fast_gate.*' | wc -l | tr -d ' ')" = "$fast_log_count" ]
  [ "$(mock_call_count writer:runtime)" -eq 1 ]
}

@test "P1-12 repeated resume creates no duplicate commit gate or provider call" {
  cli_ok upgrade --provider claude --goal 'Upgrade runtime'
  commits="$(git rev-list --count "$BASE_SHA"..HEAD)"
  calls="$(wc -l < "$MOCK_CALLS" | tr -d ' ')"
  logs="$(find .upgrade/archive/logs -type f | wc -l | tr -d ' ')"

  cli_ok resume
  run_cli resume

  [ "$status" -eq 0 ]
  [ "$(git rev-list --count "$BASE_SHA"..HEAD)" = "$commits" ]
  [ "$(wc -l < "$MOCK_CALLS" | tr -d ' ')" = "$calls" ]
  [ "$(find .upgrade/archive/logs -type f | wc -l | tr -d ' ')" = "$logs" ]
}

@test "P1-13 STOP followed by terminal FAIL records failure without a fix loop" {
  install_stopping_fast_gate fail
  export STOP_IN_GATE=1

  run_cli upgrade --provider claude --goal 'Upgrade runtime'

  [ "$status" -eq 0 ]
  [ "$(state_value STOP_REQUESTED)" = 1 ]
  [ "$(state_value FAST_GATE)" = FAIL ]
  [ "$(mock_call_count writer:runtime)" -eq 1 ]
  [ "$(state_value MILESTONE_STATUS_VALUE)" != ACCEPTED ]
}

@test "additional STOP is idempotent" {
  cli_ok init claude
  cli_ok stop
  first="$(file_hash .upgrade/state.yml)"

  run_cli stop

  [ "$status" -eq 0 ]
  [ "$(state_value STOP_REQUESTED)" = 1 ]
  [ "$(state_value PHASE)" = STOPPED ]
  [ "$(file_hash .upgrade/state.yml)" = "$first" ]
}

@test "resume re-runs a stale FAIL gate instead of printing an empty ERROR" {
  prepare_runtime_milestone
  commit_runtime
  cli_ok gate fast_gate
  set_state_value PHASE BLOCKED
  set_state_value MILESTONE_GATE FAIL
  set_state_value AUTO_ATTEMPTS 3
  set_state_value CURRENT_BLOCKER ""
  set_state_value AUTO_MODE 1
  set_state_value UPGRADE_GOAL "Upgrade runtime"

  run_cli resume

  [ "$status" -eq 0 ]
  [[ "$output" != $'ERROR:\n'* ]]
  [[ "$output" != *"circuit breaker"* ]]
  [ "$(state_value PHASE)" = COMPLETE ]
  [ "$(state_value MILESTONE_GATE)" = PASS ]
  [ "$(mock_call_count writer:runtime)" -eq 0 ]
}

@test "resume prints circuit breaker when a failed gate stays failed" {
  cat > Makefile <<'MAKE'
.PHONY: runtime-fast runtime-milestone
runtime-fast:
	@true
runtime-milestone:
	@false
MAKE
  git add Makefile
  git commit -qm fail-milestone
  prepare_runtime_milestone
  commit_empty
  set_state_value PHASE BLOCKED
  set_state_value FAST_GATE PASS
  set_state_value MILESTONE_GATE FAIL
  set_state_value AUTO_ATTEMPTS 3
  set_state_value CURRENT_BLOCKER ""
  set_state_value AUTO_MODE 1
  set_state_value UPGRADE_GOAL "Upgrade runtime"

  run_cli resume

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: circuit breaker: three writer attempts exhausted"* ]]
  [ "$(state_value PHASE)" = BLOCKED ]
  [ "$(state_value CURRENT_BLOCKER)" = "circuit breaker: three writer attempts exhausted for runtime-1" ]
  [ "$(mock_call_count writer:runtime)" -eq 0 ]
}

@test "additional YAML-only resume works after deleting ephemeral adapters" {
  install_stopping_fast_gate pass
  export STOP_IN_GATE=1
  cli_ok upgrade --provider claude --goal 'Upgrade runtime'
  rm -rf .upgrade/tmp
  unset STOP_IN_GATE

  run_cli resume

  [ "$status" -eq 0 ]
  [ "$(state_value PHASE)" = COMPLETE ]
}
