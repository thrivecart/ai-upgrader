#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_ai_test
}

setup_shared_repo() {
  printf 'runtime 10\nframework 7.2\n' > shared.txt
  cat > Makefile <<'MAKE'
.PHONY: runtime-fast runtime-milestone
runtime-fast:
	@grep -q '^runtime 20$$' shared.txt
runtime-milestone:
	@grep -q '^runtime 20$$' shared.txt
MAKE
  git add shared.txt Makefile
  git commit -qm shared-fixture
}

@test "P0-10 changing a locked framework blocks autonomous execution" {
  export MOCK_WRITER_MODE=wrong-axis

  run_cli upgrade --provider claude --goal 'Upgrade runtime'

  [ "$status" -ne 0 ]
  [ "$(state_value MILESTONE_STATUS_VALUE)" != ACCEPTED ]
  [[ "$output" == *"locked axis framework changed"* || "$output" == *"BLOCKER"* ]]
}

@test "P0-11 shared source file may change when locked slice is verified unchanged" {
  setup_shared_repo
  write_shared_plan framework 7.2
  cli_ok init claude
  cli_ok target runtime 20
  cli_ok plan --import "$MOCK_PLAN"
  cli_ok approve-plan
  cli_ok begin
  printf 'runtime 20\nframework 7.2\n' > shared.txt
  git add shared.txt
  git commit -qm shared-runtime

  run_cli gates

  [ "$status" -eq 0 ]
  cli_ok review
  cli_ok accept
  [ "$(state_value MILESTONE_STATUS_VALUE)" = ACCEPTED ]
}

@test "axis_slice ignores node_modules and version-only lockfile noise" {
  source_upgrader
  printf '%s\n' '{"packages":{"node_modules/typescript":{"version":"6.0.2"},"node_modules/other":{"version":"24"}}}' > lock.json
  git add lock.json
  git commit -qm lock-noise
  sha="$(git rev-parse HEAD)"

  [ -z "$(axis_slice "$sha" lock.json node 24)" ]
}

@test "axis_slice keeps a node pin on a one-line package.json when typescript moves" {
  source_upgrader
  printf '%s\n' '{"engines":{"node":">=24"},"devDependencies":{"typescript":"5.9.3","@types/node":"24.0.0"}}' > package.json
  git add package.json
  git commit -qm pkg-before
  before="$(git rev-parse HEAD)"
  printf '%s\n' '{"engines":{"node":">=24"},"devDependencies":{"typescript":"6.0.2","@types/node":"24.0.0"}}' > package.json
  git add package.json
  git commit -qm pkg-after
  after="$(git rev-parse HEAD)"

  [ "$(axis_slice "$before" package.json node 24)" = "$(axis_slice "$after" package.json node 24)" ]
  [ "$(axis_slice "$before" package.json typescript 5.9.3)" != "$(axis_slice "$after" package.json typescript 6.0.2)" ]
  [[ "$(axis_slice "$after" package.json node 24)" == *'"node":">=24"'* ]]
}

@test "axis_slice matches namespaced composer package keys" {
  source_upgrader
  printf '%s\n' '{"require":{"php":">=8.2","laravel/framework":"10.48.0"}}' > composer.json
  git add composer.json
  git commit -qm composer-before
  before="$(git rev-parse HEAD)"
  printf '%s\n' '{"require":{"php":">=8.2","laravel/framework":"11.0.0"}}' > composer.json
  git add composer.json
  git commit -qm composer-after
  after="$(git rev-parse HEAD)"

  [ "$(axis_slice "$before" composer.json php 8.2)" = "$(axis_slice "$after" composer.json php 8.2)" ]
  [ "$(axis_slice "$before" composer.json laravel 10.48.0)" != "$(axis_slice "$after" composer.json laravel 11.0.0)" ]
  [[ "$(axis_slice "$after" composer.json laravel 11.0.0)" == *'"laravel/framework":"11.0.0"'* ]]
}

@test "shared companion lockfile may change when locked node pin stays" {
  printf '%s\n' '{"engines":{"node":">=24"},"devDependencies":{"typescript":"5.9.3"}}' > package.json
  printf '%s\n' '{"packages":{"":{"engines":{"node":">=24"}},"node_modules/typescript":{"version":"5.9.3"}}}' > package-lock.json
  cat > Makefile <<'MAKE'
.PHONY: runtime-fast runtime-milestone
runtime-fast:
	@true
runtime-milestone:
	@true
MAKE
  git add package.json package-lock.json Makefile
  git commit -qm npm-lock-fixture
  write_stack_plan language language 5.9.3 6.0.2 'package.json|package-lock.json' \
    node runtime 24 24 'package.json|package-lock.json'
  cli_ok init claude
  cli_ok target language 6.0.2
  cli_ok plan --import "$MOCK_PLAN"
  cli_ok approve-plan
  cli_ok begin
  printf '%s\n' '{"engines":{"node":">=24"},"devDependencies":{"typescript":"6.0.2"}}' > package.json
  printf '%s\n' '{"packages":{"":{"engines":{"node":">=24"}},"node_modules/typescript":{"version":"6.0.2"},"node_modules/other":{"version":"1.0.0"}}}' > package-lock.json
  git add package.json package-lock.json
  git commit -qm language-lock-churn

  run_cli gate fast_gate

  [ "$status" -eq 0 ]
}

@test "locked node pin change in shared package.json still blocks" {
  printf '%s\n' '{"engines":{"node":">=22"},"devDependencies":{"typescript":"5.9.3"}}' > package.json
  printf '%s\n' '{"packages":{"":{"engines":{"node":">=22"}}}}' > package-lock.json
  cat > Makefile <<'MAKE'
.PHONY: runtime-fast runtime-milestone
runtime-fast:
	@true
runtime-milestone:
	@true
MAKE
  git add package.json package-lock.json Makefile
  git commit -qm npm-pin-fixture
  write_stack_plan language language 5.9.3 6.0.2 'package.json|package-lock.json' \
    node runtime 22 22 'package.json|package-lock.json'
  cli_ok init claude
  cli_ok target language 6.0.2
  cli_ok plan --import "$MOCK_PLAN"
  cli_ok approve-plan
  cli_ok begin
  printf '%s\n' '{"engines":{"node":">=24"},"devDependencies":{"typescript":"6.0.2"}}' > package.json
  printf '%s\n' '{"packages":{"":{"engines":{"node":">=24"}}}}' > package-lock.json
  git add package.json package-lock.json
  git commit -qm language-and-node

  run_cli gate fast_gate

  [ "$status" -ne 0 ]
  [[ "$output" == *"locked axis node dependency changed in shared file package.json"* ]]
}

@test "P0-12 inconclusive shared lock verification is never PASS" {
  printf 'runtime 10\nfw 7.2\n' > shared.txt
  git add shared.txt
  git commit -qm inconclusive-fixture
  write_shared_plan rails UNKNOWN
  cli_ok init claude
  cli_ok target runtime 20
  cli_ok plan --import "$MOCK_PLAN"
  cli_ok approve-plan
  cli_ok begin
  printf 'runtime 20\nfw 7.2\n' > shared.txt
  git add shared.txt
  git commit -qm shared-runtime

  run_cli gate fast_gate

  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT VERIFIED"* ]]
  [ "$(state_value FAST_GATE)" != PASS ]
}

@test "P1-06 deleting a locked source-of-truth blocks verification" {
  prepare_runtime_milestone
  printf 'runtime 2\n' > runtime.txt
  rm framework.txt
  git add runtime.txt framework.txt
  git commit -qm missing-locked-source

  run_cli gate fast_gate

  [ "$status" -ne 0 ]
  [[ "$output" == *"locked axis framework changed"* ]]
}

@test "P1-07 hidden locked version change in Dockerfile is detected" {
  printf 'FROM example/framework:1\n' > Dockerfile
  git add Dockerfile
  git commit -qm docker-fixture
  replace_plan_text framework.txt Dockerfile
  cli_ok init claude
  cli_ok target runtime 2
  cli_ok plan --import "$MOCK_PLAN"
  cli_ok approve-plan
  cli_ok begin
  printf 'runtime 2\n' > runtime.txt
  printf 'FROM example/framework:2\n' > Dockerfile
  git add runtime.txt Dockerfile
  git commit -qm hidden-locked-change

  run_cli gate fast_gate

  [ "$status" -ne 0 ]
  [[ "$output" == *"locked axis framework changed at Dockerfile"* ]]
}

@test "P1-10 unrelated compatibility patch is not silently accepted" {
  prepare_runtime_milestone
  printf 'runtime 2\n' > runtime.txt
  printf 'causal patch requiring disposition\n' > compatibility.txt
  git add runtime.txt compatibility.txt
  git commit -qm compatibility-patch

  run_cli gate fast_gate

  [ "$status" -ne 0 ]
  [[ "$output" == *"unrelated path compatibility.txt changed"* ]]
}

@test "H-02 traversal source path is rejected without outside mutation" {
  replace_plan_text runtime.txt ../../outside-repository
  cli_ok init claude
  cli_ok target runtime 2

  run_cli plan --import "$MOCK_PLAN"

  [ "$status" -ne 0 ]
  [[ "$output" == *"untracked/unsafe source_of_truth"* ]]
  [ ! -e "$TEST_ROOT/outside-repository" ]
}

@test "H-09 tracked symlink source cannot escape the repository" {
  printf 'outside\n' > "$TEST_ROOT/outside.txt"
  ln -s "$TEST_ROOT/outside.txt" escaped.txt
  git add escaped.txt
  git commit -qm symlink-fixture
  replace_plan_text runtime.txt escaped.txt
  cli_ok init claude
  cli_ok target runtime 2

  run_cli plan --import "$MOCK_PLAN"

  [ "$status" -ne 0 ]
  [[ "$output" == *"untracked/unsafe source_of_truth"* ]]
  [ "$(cat "$TEST_ROOT/outside.txt")" = outside ]
}
