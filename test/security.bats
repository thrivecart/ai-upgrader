#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_ai_test
}

@test "H-03 autonomous gate command injection is rejected before execution" {
  replace_plan_text 'make runtime-fast' 'make runtime-fast; touch injected-marker'

  run_cli upgrade --provider claude --goal 'Upgrade runtime'

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe/unrecognized autonomous gate"* ]]
  [ ! -e injected-marker ]
  [ "$(git rev-parse HEAD)" = "$BASE_SHA" ]
}

@test "H-08 canonical YAML wins over stale legacy adapters without restart" {
  cli_ok init claude
  mkdir -p .upgrade/agent
  printf 'FORMAT\t6\nPHASE\tCOMPLETE\n' > .upgrade/agent/state.tsv
  canonical="$(file_hash .upgrade/state.yml)"

  run_cli status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Phase: DISCOVER"* ]]
  [ "$(file_hash .upgrade/state.yml)" = "$canonical" ]
  [ -f .upgrade/agent/state.tsv ]
}

@test "security malformed provider response cannot execute embedded text" {
  cat > "$MOCK_PLAN" <<'PLAN'
$(touch provider-injected)
BEGIN_AI_UPGRADER_AXES_TSV
id	kind	current	target	policy	source_of_truth
END_AI_UPGRADER_AXES_TSV
PLAN
  cli_ok init claude

  run_cli plan

  [ "$status" -ne 0 ]
  [ ! -e provider-injected ]
}

@test "security manual mode cannot invoke an autonomous writer" {
  cli_ok init manual

  run_cli upgrade --goal 'Upgrade runtime'

  [ "$status" -ne 0 ]
  [[ "$output" == *"autonomous upgrade requires an AI provider"* || "$output" == *"manual provider"* ]]
  [ "$(mock_call_count plan)" -eq 0 ]
}
