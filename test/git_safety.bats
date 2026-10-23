#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_ai_test
}

@test "P0-24 unrelated uncommitted work is preserved and never staged" {
  printf 'private work\n' > unrelated.txt
  before="$(cat unrelated.txt)"

  run_cli upgrade --provider claude --goal 'Upgrade runtime'

  [ "$status" -ne 0 ]
  [ "$(cat unrelated.txt)" = "$before" ]
  [ -z "$(git diff --cached --name-only)" ]
  [ "$(git rev-parse HEAD)" = "$BASE_SHA" ]
}

@test "P1-03 failed atomic state write preserves previous complete file" {
  cli_ok init claude
  source_upgrader
  destination="$TEST_REPO/.upgrade/state.yml"
  before="$(file_hash "$destination")"
  TRUST_DIR="$TEST_ROOT/no-write"
  mkdir "$TRUST_DIR"
  chmod 500 "$TRUST_DIR"
  attempt_write() {
    printf 'truncated\n' | atomic_write "$destination"
  }

  run attempt_write

  [ "$status" -ne 0 ]
  [ "$(file_hash "$destination")" = "$before" ]
  chmod 700 "$TRUST_DIR"
}

@test "P1-04 an existing autonomous writer lock rejects a second writer" {
  cli_ok init claude
  cli_ok target runtime 2
  cli_ok plan
  mkdir .upgrade/tmp/upgrade.lock
  before="$(file_hash .upgrade/plan.yml)"

  run_cli upgrade --provider claude --goal 'Upgrade runtime'

  [ "$status" -ne 0 ]
  [[ "$output" == *"another autonomous upgrade is running"* ]]
  [ "$(file_hash .upgrade/plan.yml)" = "$before" ]
}

@test "P1-11 active Git index.lock is not removed" {
  cli_ok init claude
  cli_ok target runtime 2
  cli_ok plan
  cli_ok approve-plan
  cli_ok begin
  : > .git/index.lock

  run_cli run

  [ "$status" -ne 0 ]
  [ -f .git/index.lock ]
  [ "$(git rev-parse HEAD)" = "$BASE_SHA" ]
  rm .git/index.lock
}

@test "H-06 immutable base SHA is anchored outside canonical YAML" {
  prepare_runtime_milestone
  original="$(state_value BASE_SHA)"
  older='0000000000000000000000000000000000000000'
  awk -v old="$older" '
    $1=="BASE_SHA:" {$0="  BASE_SHA: \"" old "\""}
    {print}
  ' .upgrade/state.yml > state.tmp
  mv state.tmp .upgrade/state.yml

  run_cli status

  [ "$status" -ne 0 ]
  [[ "$output" == *"immutable BASE_SHA mismatch"* ]]
}
