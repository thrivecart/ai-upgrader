#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_ai_test
}

@test "P0-01 valid canonical YAML reloads without mutation" {
  cli_ok init claude
  cli_ok target runtime 2
  cli_ok plan
  before="$(file_hash .upgrade/plan.yml)"
  rm -rf .upgrade/tmp

  run_cli status

  [ "$status" -eq 0 ]
  [ "$(file_hash .upgrade/plan.yml)" = "$before" ]
  [ -f .upgrade/manifest.yml ]
  [ -f .upgrade/gates.yml ]
}

@test "P0-02 malformed YAML fails explicitly without execution" {
  cli_ok init claude
  before="$(git rev-parse HEAD)"
  printf 'schema_version:\t1\n' > .upgrade/state.yml
  malformed="$(file_hash .upgrade/state.yml)"

  run_cli status

  [ "$status" -ne 0 ]
  [[ "$output" == *"unsafe YAML"* ]]
  [ "$(file_hash .upgrade/state.yml)" = "$malformed" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "P0-03 missing required state field is rejected" {
  cli_ok init claude
  awk '$1!="HEAD_SHA:"' .upgrade/state.yml > state.tmp
  mv state.tmp .upgrade/state.yml

  run_cli status

  [ "$status" -ne 0 ]
  [[ "$output" == *"missing trusted state key: HEAD_SHA"* ]]
  [ "$(git rev-parse HEAD)" = "$BASE_SHA" ]
}

@test "P0-04 unknown security-critical state field is rejected" {
  cli_ok init claude
  printf '  AUTHORIZATION_OVERRIDE: "1"\n' >> .upgrade/state.yml

  run_cli status

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown trusted state key: AUTHORIZATION_OVERRIDE"* ]]
}

@test "P0-05 duplicate YAML keys are rejected" {
  cli_ok init claude
  printf '  PROVIDER: "cursor"\n' >> .upgrade/state.yml

  run_cli status

  [ "$status" -ne 0 ]
  [[ "$output" == *"duplicate trusted state key: PROVIDER"* ]]
}

@test "P1-01 empty YAML fails and does not become a baseline" {
  cli_ok init claude
  : > .upgrade/state.yml

  run_cli status

  [ "$status" -ne 0 ]
  [[ "$output" == *"trusted state missing"* || "$output" == *"missing trusted state key"* ]]
  [ "$(git rev-parse HEAD)" = "$BASE_SHA" ]
}

@test "P1-02 corrupted state does not silently restart" {
  cli_ok init claude
  printf 'schema_version: 1\nstate:\n  PHASE: "COMPLETE\n' > .upgrade/state.yml

  run_cli resume

  [ "$status" -ne 0 ]
  [ "$(git rev-parse HEAD)" = "$BASE_SHA" ]
  [ "$(mock_call_count plan)" -eq 0 ]
}

@test "H-01 unsafe YAML tags and aliases are rejected" {
  cli_ok init claude
  printf '!!python/object/apply:os.system ["touch escaped"]\n' > .upgrade/state.yml

  run_cli status

  [ "$status" -ne 0 ]
  [ ! -e escaped ]
}
