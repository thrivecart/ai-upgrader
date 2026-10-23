#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_ai_test
}

setup_sha_gate() {
  local mode="${1:-correct}"
  if [ "$mode" = correct ]; then
    cat > ci-check.sh <<'CHECK'
#!/usr/bin/env bash
printf 'CI_SHA=%s\n' "$AI_UPGRADER_EXPECTED_SHA"
printf 'CI_STATUS=success\n'
CHECK
  else
    cat > ci-check.sh <<CHECK
#!/usr/bin/env bash
printf 'CI_SHA=%s\n' '$BASE_SHA'
printf 'CI_STATUS=success\n'
CHECK
  fi
  chmod +x ci-check.sh
  git add ci-check.sh
  git commit -qm ci-fixture
  replace_plan_text 'make runtime-fast' './ci-check.sh'
  replace_plan_text $'./ci-check.sh\texit:0' $'./ci-check.sh\tsha-success'
}

prepare_committed_candidate() {
  cli_ok init claude
  cli_ok target runtime 2
  cli_ok plan
  cli_ok approve-plan
  cli_ok begin
  commit_runtime
}

@test "P0-17 exact candidate SHA terminal success passes" {
  setup_sha_gate correct
  prepare_committed_candidate
  candidate="$(git rev-parse HEAD)"

  run_cli gate fast_gate

  [ "$status" -eq 0 ]
  [ "$(state_value FAST_GATE)" = PASS ]
  grep -q "sha: \"$candidate\"" .upgrade/gates.yml
}

@test "P0-18 wrong-SHA success is rejected" {
  setup_sha_gate wrong
  prepare_committed_candidate

  run_cli gate fast_gate

  [ "$status" -ne 0 ]
  [ "$(state_value FAST_GATE)" = FAIL ]
  [ "$(git rev-parse HEAD)" != "$BASE_SHA" ]
}

@test "P0-19 non-PASS evidence statuses cannot satisfy acceptance" {
  prepare_committed_candidate
  cli_ok gates
  cli_ok review
  cp .upgrade/gates.yml gates.good

  for bad in FAIL RUNNING CANCELLED MISSING UNKNOWN; do
    awk -v bad="$bad" '
      $0 ~ /^  - milestone_id:/ {entry++}
      entry==1 && $0 ~ /^    result:/ {$2=bad}
      {print}
    ' gates.good > .upgrade/gates.yml
    run_cli accept
    [ "$status" -ne 0 ]
    [ "$(state_value MILESTONE_STATUS_VALUE)" != ACCEPTED ]
  done
}

@test "P0-21 moving HEAD invalidates prior gates and review" {
  prepare_committed_candidate
  cli_ok gates
  cli_ok review
  reviewed="$(state_value REVIEW_SHA)"
  commit_empty

  run_cli accept

  [ "$status" -ne 0 ]
  [ "$(git rev-parse HEAD)" != "$reviewed" ]
  [ "$(state_value REVIEW_STATUS)" = NOT_RUN ]
}

@test "H-04 changing the approved check identity invalidates approval" {
  prepare_committed_candidate
  awk '{if ($0 ~ /command: "make runtime-fast"/) sub(/runtime-fast/, "runtime-fast-copy")}1' \
    .upgrade/gates.yml > gates.tmp
  mv gates.tmp .upgrade/gates.yml

  run_cli gate fast_gate

  [ "$status" -ne 0 ]
  [[ "$output" == *"approved plan/targets/gates changed"* ]]
}

@test "H-07 green gate evidence becomes stale after HEAD changes" {
  prepare_committed_candidate
  cli_ok gates
  cli_ok review
  commit_empty

  run_cli accept

  [ "$status" -ne 0 ]
  [ "$(state_value FAST_GATE)" = NOT_RUN ]
  [ "$(state_value MILESTONE_GATE)" = NOT_RUN ]
}

@test "H-10 disabling a required gate after approval is detected" {
  cli_ok init claude
  cli_ok target runtime 2
  cli_ok plan
  cli_ok approve-plan
  awk '
    $0 ~ /^    gate: fast_gate/ {fast=1}
    fast && $0 ~ /^    required: true/ {sub(/true/, "false"); fast=0}
    {print}
  ' .upgrade/gates.yml > gates.tmp
  mv gates.tmp .upgrade/gates.yml

  run_cli begin

  [ "$status" -ne 0 ]
  [[ "$output" == *"approved plan/targets/gates changed"* ]]
}
