#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_ai_test
}

track_fixture() {
  local path="$1" content="$2"
  printf '%s\n' "$content" > "$path"
  git add "$path"
  git commit -qm "fixture-$path"
}

@test "P0-06a Node and frontend framework are persisted from repository evidence" {
  track_fixture package.json '{"engines":{"node":"22"},"dependencies":{"vue":"3"}}'
  replace_plan_text runtime.txt package.json
  replace_plan_text framework.txt package.json
  replace_plan_text runtime node_runtime
  replace_plan_text framework vue
  replace_plan_text $'node_runtime\tnode_runtime\t' $'node_runtime\truntime\t'
  replace_plan_text $'vue\tvue\t' $'vue\tframework\t'
  cli_ok init claude

  run_cli plan

  [ "$status" -eq 0 ]
  grep -q 'id: node_runtime' .upgrade/manifest.yml
  grep -q 'id: vue' .upgrade/manifest.yml
  grep -q 'package.json' .upgrade/manifest.yml
}

@test "P0-06b Ruby and Rails are persisted without Node assumptions" {
  track_fixture Gemfile.lock $'RUBY VERSION\n   ruby 3.3\nrails (7.2)'
  replace_plan_text runtime.txt Gemfile.lock
  replace_plan_text framework.txt Gemfile.lock
  replace_plan_text runtime ruby
  replace_plan_text framework rails
  replace_plan_text $'ruby\truby\t' $'ruby\truntime\t'
  replace_plan_text $'rails\trails\t' $'rails\tframework\t'
  cli_ok init claude

  run_cli plan

  [ "$status" -eq 0 ]
  grep -q 'id: ruby' .upgrade/manifest.yml
  grep -q 'id: rails' .upgrade/manifest.yml
  ! grep -q 'node_runtime' .upgrade/manifest.yml
}

@test "P0-06c Python and Django are persisted without imaginary technologies" {
  track_fixture pyproject.toml $'[project]\nrequires-python = ">=3.11"\ndependencies = ["django==5.1"]'
  replace_plan_text runtime.txt pyproject.toml
  replace_plan_text framework.txt pyproject.toml
  replace_plan_text runtime python
  replace_plan_text framework django
  replace_plan_text $'python\tpython\t' $'python\truntime\t'
  replace_plan_text $'django\tdjango\t' $'django\tframework\t'
  cli_ok init claude

  run_cli plan

  [ "$status" -eq 0 ]
  grep -q 'id: python' .upgrade/manifest.yml
  grep -q 'id: django' .upgrade/manifest.yml
  ! grep -Eq 'node_runtime|rails' .upgrade/manifest.yml
}

@test "P0-07 declared range is not rewritten as an exact resolved version" {
  track_fixture package.json '{"engines":{"node":">=22"}}'
  replace_plan_text runtime.txt package.json
  replace_plan_text runtime node_runtime
  replace_plan_text $'node_runtime\tnode_runtime\t' $'node_runtime\truntime\t'
  replace_plan_text $'node_runtime\truntime\t1\t2\tupgrade' \
    $'node_runtime\truntime\tUNKNOWN\t24\tupgrade'
  awk '
    /END_AI_UPGRADER_CONSTRAINTS_TSV/ {
      print "node_runtime\tdeclared_constraint\t>=22\tpackage.json; resolved version unknown"
    }
    {print}
  ' "$MOCK_PLAN" > plan.tmp
  mv plan.tmp "$MOCK_PLAN"
  replace_plan_text $'node_runtime-1\tnode_runtime\truntime\t1\t2' \
    $'node_runtime-1\tnode_runtime\truntime\tUNKNOWN\t24'
  cli_ok init claude

  run_cli plan

  [ "$status" -eq 0 ]
  grep -q 'current: "UNKNOWN"' .upgrade/manifest.yml
  grep -q 'requirement: "declared_constraint"' .upgrade/constraints.yml
  grep -q '>=22' .upgrade/constraints.yml
}

@test "P1-09 upgrade axis without research source cannot validate" {
  awk '$0 !~ /^runtime\thttps:/' "$MOCK_PLAN" > plan.tmp
  mv plan.tmp "$MOCK_PLAN"
  cli_ok init claude

  run_cli plan

  [ "$status" -ne 0 ]
  [[ "$output" == *"axis has no official SOURCES"* ]]
}

@test "already-current lock without an opened official source is rejected" {
  awk '$0 !~ /^framework\thttps:/' "$MOCK_PLAN" > plan.tmp
  mv plan.tmp "$MOCK_PLAN"
  cli_ok init claude

  run_cli plan

  [ "$status" -ne 0 ]
  [[ "$output" == *"axis has no official SOURCES https URL: framework"* ]]
}

@test "model_knowledge cannot lock an axis as already current" {
  replace_plan_text $'framework\thttps://example.invalid/framework\topened: framework 1 is current official target' \
    $'framework\thttps://example.invalid/framework\tmodel_knowledge: framework 1 is current'
  cli_ok init claude

  run_cli plan

  [ "$status" -ne 0 ]
  [[ "$output" == *"no opened official source"* ]]
}

@test "operator lock does not require an opened source" {
  awk '$0 !~ /^framework\thttps:/' "$MOCK_PLAN" > plan.tmp
  mv plan.tmp "$MOCK_PLAN"
  cli_ok init claude
  cli_ok lock framework

  run_cli plan

  [ "$status" -eq 0 ]
  grep -q 'policy: locked' .upgrade/manifest.yml
}

@test "a single official hop may cross a missing major" {
  replace_plan_text $'runtime\truntime\t1\t2\tupgrade\truntime.txt' $'runtime\tlanguage\t1.0\t3.0\tupgrade\truntime.txt'
  replace_plan_text $'runtime-1\truntime\truntime\t1\t2\t-\ttrue' $'runtime-1\truntime\tlanguage\t1.0\t3.0\t-\ttrue'
  cli_ok init claude

  run_cli plan

  [ "$status" -eq 0 ]
  [ "$(state_value PHASE)" = PLANNED ]
}

@test "same-version upgrade axis is rejected without a fake milestone" {
  replace_plan_text $'framework\tframework\t1\t1\tlocked' $'framework\tframework\t1\t1\tupgrade'
  cli_ok init claude

  run_cli plan

  [ "$status" -ne 0 ]
  [[ "$output" == *"upgrade axis has no version gap: framework"* ]]
}

@test "opened without a colon is not live official proof" {
  replace_plan_text $'framework\thttps://example.invalid/framework\topened: framework 1 is current official target' \
    $'framework\thttps://example.invalid/framework\topened fetch denied after invoke'
  cli_ok init claude

  run_cli plan

  [ "$status" -ne 0 ]
  [[ "$output" == *"no opened official source"* ]]
}

@test "plan stops as soon as TSV blocks are complete" {
  unset AI_UPGRADER_FAST_WAIT
  export AI_UPGRADER_PLAN_TIMEOUT=20
  cat > "$MOCK_BIN/claude" <<'MOCK'
#!/usr/bin/env bash
cat "$MOCK_PLAN"
sleep 30
MOCK
  chmod +x "$MOCK_BIN/claude"
  cli_ok init claude

  run_cli plan

  [ "$status" -eq 0 ]
  [[ "$output" == *"plan payload ready"* ]]
  [ "$(state_value PHASE)" = PLANNED ]
}

@test "duplicate streamed TSV blocks keep the first complete AXES payload" {
  cat "$MOCK_PLAN" "$MOCK_PLAN" "$MOCK_PLAN" > "$MOCK_PLAN.dup"
  mv "$MOCK_PLAN.dup" "$MOCK_PLAN"
  cli_ok init claude

  run_cli plan

  [ "$status" -eq 0 ]
  [ "$(state_value PHASE)" = PLANNED ]
  grep -q 'id: runtime' .upgrade/manifest.yml
}

@test "plan times out instead of hanging" {
  unset AI_UPGRADER_FAST_WAIT
  export AI_UPGRADER_PLAN_TIMEOUT=1
  cat > "$MOCK_BIN/claude" <<'MOCK'
#!/usr/bin/env bash
sleep 30
MOCK
  chmod +x "$MOCK_BIN/claude"
  cli_ok init claude

  run_cli plan

  [ "$status" -ne 0 ]
  [[ "$output" == *"plan exceeded 1s"* ]]
}

@test "opened official source may lock an already-current axis" {
  cli_ok init claude

  run_cli plan

  [ "$status" -eq 0 ]
  grep -q 'what: "opened: runtime 2 is current official target"' .upgrade/research.yml
  grep -q 'what: "opened: framework 1 is current official target"' .upgrade/research.yml
  [ "$(mock_call_count plan)" -eq 1 ]
}

@test "planner prompt forbids a milestone this repository cannot take" {
  grep -q 'A milestone means this step is expected to land in this repository' "$UPGRADER"
  grep -q 'Official latest is research, not permission to emit a runnable milestone' "$UPGRADER"
}

@test "plan may stop before official latest when this repo cannot take the next step" {
  write_incompatible_next_step_plan
  cli_ok init claude

  run_cli plan --import "$MOCK_PLAN"

  [ "$status" -eq 0 ]
  grep -q 'blocked_at' .upgrade/constraints.yml
  grep -q 'requirement: "blocked_at"' .upgrade/constraints.yml
  grep -q 'policy: locked' .upgrade/manifest.yml
  ! grep -q 'runtime-1' .upgrade/plan.yml
}

@test "upgrade axis auto-adds tracked files that still pin its current version" {
  track_fixture runtime.txt 'node 20.19.4'
  track_fixture Dockerfile 'FROM node:20.19.4-slim'
  track_fixture cypress.sh 'nvm use 20.19.4'
  track_fixture framework.txt 'framework 1.0.0 (node 20.19.4 builds)'
  track_fixture notes.md 'unrelated 120.19.4 text'
  write_stack_plan runtime runtime 20.19.4 22.23.4 runtime.txt framework framework 1.0.0 1.0.0 framework.txt
  cli_ok init claude

  run_cli plan

  [ "$status" -eq 0 ]
  grep -q 'Dockerfile' .upgrade/manifest.yml
  grep -q 'cypress.sh' .upgrade/manifest.yml
  ! grep -q 'notes.md' .upgrade/manifest.yml
  awk '/id: runtime/{r=1} /id: framework/{r=0} r && /framework.txt/{bad=1} END{exit bad}' .upgrade/manifest.yml
}
