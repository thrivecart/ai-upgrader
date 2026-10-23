#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_ai_test
  prepare_runtime_milestone
  commit_runtime
  cli_ok gates
}

@test "P0-20 HIGH reviewer finding blocks and persists" {
  printf 'HIGH: runtime migration is unsafe\nMILESTONE REVIEW: PASS\n' > "$MOCK_REVIEW"

  run_cli review

  [ "$status" -ne 0 ]
  [ "$(state_value REVIEW_STATUS)" = FAIL ]
  grep -q 'HIGH: runtime migration is unsafe' .upgrade/archive/reviews/review.md

  run_cli accept
  [ "$status" -ne 0 ]
}

@test "review prompt contains complete labeled cumulative Git evidence" {
  run_cli review

  [ "$status" -eq 0 ]
  [ "$(state_value REVIEW_STATUS)" = PASS ]
  [ "$(mock_call_count review)" -eq 1 ]
  ! [[ "$output" == *"printf: --: invalid option"* ]]
}

@test "P1-14 dirty reviewer mutation is detected before certification" {
  export MOCK_REVIEW_MUTATION=dirty

  run_cli review

  [ "$status" -ne 0 ]
  [[ "$output" == *"reviewer modified the working tree"* ]]
  [ "$(state_value REVIEW_STATUS)" != PASS ]
  [ -f reviewer-owned.txt ]
}

@test "P1-14 committed reviewer mutation invalidates exact-SHA gates" {
  export MOCK_REVIEW_MUTATION=commit
  old_head="$(state_value HEAD_SHA)"

  run_cli review

  [ "$status" -ne 0 ]
  [[ "$output" == *"reviewer changed HEAD"* ]]
  [ "$(state_value HEAD_SHA)" != "$old_head" ]
  [ "$(state_value FAST_GATE)" = NOT_RUN ]
  [ "$(state_value REVIEW_STATUS)" = NOT_RUN ]
}

@test "additional missing review evidence blocks acceptance" {
  cli_ok review
  rm .upgrade/archive/reviews/review.md

  run_cli accept

  [ "$status" -ne 0 ]
  [[ "$output" == *"missing independent review evidence"* ]]
}
