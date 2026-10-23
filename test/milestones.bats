#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_ai_test
}

@test "regression fresh upgrade cannot approve initialization scaffolding" {
  printf 'malformed provider response\n' > "$MOCK_PLAN"

  run_cli upgrade --provider claude --goal 'Upgrade runtime'

  [ "$status" -ne 0 ]
  [ "$(mock_call_count plan)" -eq 1 ]
  [ "$(git rev-parse HEAD)" = "$BASE_SHA" ]
  [ "$(state_value PHASE)" = BLOCKED ]
  [[ "$output" != *"Upgrade complete"* ]]
}

@test "validated empty plan is an explicit successful no-op" {
  write_empty_plan

  run_cli upgrade --provider claude --goal 'Inspect already-current stack'

  [ "$status" -eq 0 ]
  [ "$(state_value PHASE)" = COMPLETE ]
  [ "$(mock_call_count plan)" -eq 1 ]
  [ "$(mock_call_count writer:runtime)" -eq 0 ]
  [ "$(git rev-parse HEAD)" = "$BASE_SHA" ]
}

@test "milestone state machine reaches acceptance only through all stages" {
  cli_ok init claude
  cli_ok target runtime 2
  cli_ok plan
  [ "$(state_value PHASE)" = PLANNED ]
  cli_ok approve-plan
  cli_ok begin
  [ "$(state_value PHASE)" = ACTIVE ]
  commit_runtime
  cli_ok gates
  [ "$(state_value FAST_GATE)" = PASS ]
  [ "$(state_value MILESTONE_GATE)" = PASS ]
  cli_ok review
  [ "$(state_value PHASE)" = REVIEWED ]

  run_cli accept

  [ "$status" -eq 0 ]
  [ "$(state_value PHASE)" = ACCEPTED ]
  [ "$(state_value MILESTONE_STATUS_VALUE)" = ACCEPTED ]
}

@test "additional missing gate evidence prevents milestone acceptance" {
  prepare_runtime_milestone
  commit_runtime
  cli_ok gates
  cli_ok review
  rm -f .upgrade/archive/evidence/runtime-1.fast_gate.tsv \
    .upgrade/tmp/evidence/runtime-1.fast_gate.tsv
  awk '
    $0 ~ /^  - milestone_id:/ {mid=1; gate=0}
    mid && $0 ~ /^    gate: fast_gate/ {gate=1}
    gate && $0 ~ /^    result:/ {$0="    result: NOT_RUN"}
    gate && $0 ~ /^    sha:/ {$0="    sha: \"\""}
    gate && $0 ~ /^    log_hash:/ {$0="    log_hash: \"\""}
    {print}
  ' .upgrade/gates.yml > gates.tmp
  mv gates.tmp .upgrade/gates.yml

  run_cli accept

  [ "$status" -ne 0 ]
  [[ "$output" == *"missing gate evidence: fast_gate"* ]]
}

@test "additional provider is called for fresh planning before any completion" {
  run_cli upgrade --provider claude --goal 'Upgrade runtime'

  [ "$status" -eq 0 ]
  [ "$(mock_call_count plan)" -eq 1 ]
  [ "$(mock_call_count writer:runtime)" -eq 1 ]
  [ "$(state_value PHASE)" = COMPLETE ]
}

@test "writer compatibility stop without commit blocks that edge and continues" {
  export MOCK_WRITER_MODE=edge-block
  write_independent_two_axis_plan
  cli_ok init claude
  cli_ok target runtime 2
  cli_ok target framework 2
  cli_ok plan --import "$MOCK_PLAN"

  run_cli upgrade --provider claude --goal 'Upgrade runtime and framework'

  [ "$status" -eq 0 ]
  [[ "$output" == *"Upgrade complete (partial)"* ]]
  [ "$(awk -F '\t' '$1=="runtime-1"{print $2}' .upgrade/tmp/milestone-status.tsv)" = BLOCKED ]
  [ "$(awk -F '\t' '$1=="framework-1"{print $2}' .upgrade/tmp/milestone-status.tsv)" = ACCEPTED ]
  [ "$(git rev-parse HEAD)" != "$BASE_SHA" ]
  grep -q 'runtime 1' runtime.txt
  grep -qx 'framework 2' framework.txt
}

@test "writer silence without commit is still a failure" {
  export MOCK_WRITER_MODE=no-change
  cli_ok init claude
  cli_ok target runtime 2
  cli_ok plan --import "$MOCK_PLAN"
  cli_ok approve-plan
  cli_ok begin

  run_cli run

  [ "$status" -ne 0 ]
  [[ "$output" == *"writer returned without a milestone commit"* ]]
  [ "$(git rev-parse HEAD)" = "$(state_value BASE_SHA)" ]
}
