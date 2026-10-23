PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
UPGRADER="$PROJECT_ROOT/ai-upgrader"
# shellcheck disable=SC1091
source "$BATS_TEST_DIRNAME/helpers/mocks.bash"
# shellcheck disable=SC1091
source "$BATS_TEST_DIRNAME/helpers/yaml.bash"

setup_ai_test() {
  export TEST_ROOT="$BATS_TEST_TMPDIR/case"
  export TEST_REPO="$TEST_ROOT/repo"
  export TEST_HOME="$TEST_ROOT/home"
  export MOCK_BIN="$TEST_ROOT/bin"
  export MOCK_PLAN="$TEST_ROOT/plan.response"
  export MOCK_REVIEW="$TEST_ROOT/review.response"
  export MOCK_CALLS="$TEST_ROOT/mock.calls"
  export MOCK_WRITER_MODE="${MOCK_WRITER_MODE:-runtime}"
  export AI_UPGRADER_FAST_WAIT=1
  export HOME="$TEST_HOME"
  # /usr/bin/git on macOS is an xcrun shim (~10x slower per call); prefer the real binary.
  : "${AI_TEST_GIT_DIR:=$(dirname "$(xcrun -f git 2>/dev/null || command -v git)")}"
  export PATH="$MOCK_BIN:$AI_TEST_GIT_DIR:$PATH"
  mkdir -p "$TEST_REPO" "$TEST_HOME" "$MOCK_BIN"
  : > "$MOCK_CALLS"
  install_provider_mock
  init_test_repo
}

# Build the baseline repo once per bats run and copy it per test (mocked repo).
build_baseline_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.name "AI Upgrader Test"
  git -C "$dir" config user.email "test@example.invalid"
  printf 'runtime 1\n' > "$dir/runtime.txt"
  printf 'framework 1\n' > "$dir/framework.txt"
  cat > "$dir/Makefile" <<'MAKE'
.PHONY: runtime-fast runtime-milestone framework-fast framework-milestone slow-gate
runtime-fast:
	@grep -qx 'runtime 2' runtime.txt
runtime-milestone:
	@grep -qx 'runtime 2' runtime.txt
framework-fast:
	@grep -qx 'framework 2' framework.txt
framework-milestone:
	@grep -qx 'framework 2' framework.txt
slow-gate:
	@printf 'done\n'
MAKE
  git -C "$dir" add runtime.txt framework.txt Makefile
  git -C "$dir" commit -qm baseline
}

init_test_repo() {
  local tpl="${BATS_RUN_TMPDIR:-${TMPDIR:-/tmp}}/baseline-repo" i
  if mkdir "$tpl.lock" 2>/dev/null; then
    build_baseline_repo "$tpl.build" && mv "$tpl.build" "$tpl"
  else
    for i in $(seq 1 300); do [ -d "$tpl" ] && break; sleep 0.1; done
  fi
  if [ -d "$tpl" ]; then
    cp -R "$tpl/." "$TEST_REPO/"
  else
    build_baseline_repo "$TEST_REPO"
  fi
  export BASE_SHA
  BASE_SHA="$(git -C "$TEST_REPO" rev-parse HEAD)"
  write_standard_plan
  printf 'MILESTONE REVIEW: PASS\n' > "$MOCK_REVIEW"
  cd "$TEST_REPO" || return
}

run_cli() {
  run "$UPGRADER" "$@"
}

cli_ok() {
  "$UPGRADER" "$@" >/dev/null
}

state_value() {
  local key="$1"
  awk -v key="$key" '
    $1 == key ":" {
      $1=""
      sub(/^ +/, "")
      gsub(/^"/, "")
      gsub(/"$/, "")
      print
      exit
    }
  ' "$TEST_REPO/.upgrade/state.yml"
}

set_state_value() {
  local key="$1" value="$2"
  awk -v key="$key" -v value="$value" '
    $1 == key ":" { print "  " key ": \"" value "\""; next }
    { print }
  ' "$TEST_REPO/.upgrade/state.yml" > "$TEST_REPO/.upgrade/state.yml.tmp"
  mv "$TEST_REPO/.upgrade/state.yml.tmp" "$TEST_REPO/.upgrade/state.yml"
}

file_hash() {
  shasum -a 256 "$1" | awk '{print $1}'
}

source_upgrader() {
  export AI_UPGRADER_TEST_SOURCE_ONLY=1
  # shellcheck disable=SC1090
  source "$UPGRADER"
  unset AI_UPGRADER_TEST_SOURCE_ONLY
  # setup_paths consumes this global after the production file is sourced.
  # shellcheck disable=SC2034
  ROOT="$TEST_REPO"
  setup_paths
}

prepare_runtime_milestone() {
  cli_ok init claude
  cli_ok target runtime 2
  cli_ok plan --import "$MOCK_PLAN"
  cli_ok approve-plan
  cli_ok begin
}

commit_runtime() {
  printf 'runtime 2\n' > "$TEST_REPO/runtime.txt"
  git -C "$TEST_REPO" add runtime.txt
  git -C "$TEST_REPO" commit -qm runtime-upgrade
}

commit_empty() {
  git -C "$TEST_REPO" commit --allow-empty -qm moved-head
}

assert_clean() {
  [ -z "$(git -C "$TEST_REPO" status --porcelain --untracked-files=normal)" ]
}
