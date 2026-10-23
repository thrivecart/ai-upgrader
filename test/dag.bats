#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_ai_test
  write_two_axis_plan
}

authorize_two_axes() {
  cli_ok init claude
  cli_ok target runtime 2
  cli_ok target framework 2
}

@test "P0-13 valid DAG respects prerequisite order" {
  authorize_two_axes
  cli_ok plan
  cli_ok approve-plan
  cli_ok begin
  [ "$(state_value MILESTONE_ID)" = runtime-1 ]

  run_cli begin
  [ "$status" -eq 0 ]
  [[ "$output" == *"Already active: runtime-1"* ]]

  commit_runtime
  cli_ok gates
  cli_ok review
  cli_ok accept
  cli_ok begin
  [ "$(state_value MILESTONE_ID)" = framework-1 ]
}

@test "P0-14 dependency cycle rejects the plan" {
  replace_plan_text $'runtime-1\truntime\truntime\t1\t2\t-\ttrue' \
    $'runtime-1\truntime\truntime\t1\t2\tframework-1\ttrue'
  authorize_two_axes

  run_cli plan

  [ "$status" -ne 0 ]
  [[ "$output" == *"milestone dependency cycle"* ]]
  [ "$(git rev-parse HEAD)" = "$BASE_SHA" ]
}

@test "P0-15 missing dependency reference rejects the plan" {
  replace_plan_text $'runtime-1\truntime\truntime\t1\t2\t-\ttrue' \
    $'runtime-1\truntime\truntime\t1\t2\tmissing-1\ttrue'
  authorize_two_axes

  run_cli plan

  [ "$status" -ne 0 ]
  [[ "$output" == *"milestone references unknown dependency"* ]]
}

@test "P0-16 a milestone cannot name multiple primary axes" {
  replace_plan_text $'runtime-1\truntime\truntime\t1\t2\t-\ttrue' \
    $'runtime-1\truntime,framework\truntime\t1\t2\t-\ttrue'
  authorize_two_axes

  run_cli plan

  [ "$status" -ne 0 ]
  [[ "$output" == *"multiple or unknown primary axes"* || "$output" == *"locked/unknown axis"* ]]
}

@test "P1-08 duplicate milestone IDs are rejected" {
  awk '
    /END_AI_UPGRADER_MILESTONES_TSV/ {
      print "runtime-1\tframework\tframework\t1\t2\truntime-1\ttrue"
    }
    {print}
  ' "$MOCK_PLAN" > plan.tmp
  mv plan.tmp "$MOCK_PLAN"
  authorize_two_axes

  run_cli plan

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid milestones"* ]]
}

@test "additional disconnected axes retain no fabricated dependency" {
  replace_plan_text $'framework-1\tframework\tframework\t1\t2\truntime-1\ttrue' \
    $'framework-1\tframework\tframework\t1\t2\t-\ttrue'
  authorize_two_axes

  run_cli plan

  [ "$status" -eq 0 ]
  [ "$(grep -c 'depends_on: \[\]' .upgrade/plan.yml)" -eq 2 ]
}
