#!/usr/bin/env bash
# End-to-end synthetic upgrades against the real orchestrator.
# Planner is imported (deterministic). Writer/reviewer are mocked to apply
# the fixture patch, then `ai-upgrader upgrade` runs begin → run → gates → review → accept.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
UPGRADER="${UPGRADER:-$ROOT_DIR/ai-upgrader}"
WORKDIR="${WORKDIR:-${TMPDIR:-/tmp}/ai-upgrader-synth}"
ORIG_PATH="$PATH"
PASS=0
FAIL=0
RESULTS=()

die() { printf 'FATAL: %s\n' "$*" >&2; exit 1; }
[ -x "$UPGRADER" ] || [ -f "$UPGRADER" ] || die "missing upgrader: $UPGRADER"

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

write_fat_lock() {
  local ts_ver="$1" extra="${2:-}"
  local i
  {
    printf '%s\n' '{'
    printf '%s\n' '  "lockfileVersion": 3,'
    printf '%s\n' '  "packages": {'
    printf '%s\n' '    "": { "engines": { "node": ">=24" } },'
    printf '%s\n' "    \"node_modules/typescript\": { \"version\": \"$ts_ver\" },"
    printf '%s\n' '    "node_modules/vue": { "version": "3.5.24" },'
    for i in $(seq 0 199); do
      printf '    "node_modules/pkg-%s": { "version": "1.0.%s", "engines": { "node": ">=18" } },\n' "$i" "$i"
    done
    if [ -n "$extra" ]; then
      printf '    "node_modules/%s": { "version": "9.9.9", "engines": { "node": ">=16" } }\n' "$extra"
    else
      printf '    "node_modules/pkg-tail": { "version": "0.0.1" }\n'
    fi
    printf '%s\n' '  }'
    printf '%s\n' '}'
  }
}

write_pkg() {
  local ts_ver="$1" node_pin="${2:->=24}"
  cat <<JSON
{
  "name": "synth-app",
  "engines": { "node": "$node_pin" },
  "dependencies": { "vue": "3.5.24" },
  "devDependencies": { "typescript": "$ts_ver" }
}
JSON
}

write_workflow() {
  local node_ver="$1"
  mkdir -p .github/workflows
  cat > .github/workflows/ci.yml <<YML
name: ci
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: $node_ver
      - run: npm ci
YML
}

write_plan() {
  local file="$1"
  shift
  local uid="$1" ukind="$2" ufrom="$3" uto="$4" upaths="$5"
  shift 5
  local srcf
  srcf="$(mktemp "${TMPDIR:-/tmp}/synth-src.XXXXXX")"
  printf '%s\thttps://example.invalid/%s\topened: current official target\n' "$uid" "$uid" > "$srcf"
  {
    printf '%s\n' 'BEGIN_AI_UPGRADER_AXES_TSV'
    printf '%s\n' $'id\tkind\tcurrent\ttarget\tpolicy\tsource_of_truth'
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$uid" "$ukind" "$ufrom" "$uto" upgrade "$upaths"
    while [ $# -ge 5 ]; do
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" locked "$5"
      printf '%s\thttps://example.invalid/%s\topened: current official target\n' "$1" "$1" >> "$srcf"
      shift 5
    done
    printf '%s\n' 'END_AI_UPGRADER_AXES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' $'left\trelation\tright\tevidence'
    printf '%s\n' 'END_AI_UPGRADER_CONSTRAINTS_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_MILESTONES_TSV'
    printf '%s\n' $'id\taxis\tkind\tfrom\tto\tdepends_on\treview_required'
    printf '%s-1\t%s\t%s\t%s\t%s\t-\ttrue\n' "$uid" "$uid" "$ukind" "$ufrom" "$uto"
    printf '%s\n' 'END_AI_UPGRADER_MILESTONES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_GATES_TSV'
    printf '%s\n' $'milestone_id\tgate\trequired\tcwd\tcommand\tpass_condition'
    printf '%s-1\tfast_gate\ttrue\t.\tmake runtime-fast\texit:0\n' "$uid"
    printf '%s-1\tmilestone_gate\ttrue\t.\tmake runtime-milestone\texit:0\n' "$uid"
    printf '%s-1\tfull_ci\tfalse\t-\t-\t-\n' "$uid"
    printf '%s-1\tsmoke\tfalse\t-\t-\t-\n' "$uid"
    printf '%s\n' 'END_AI_UPGRADER_GATES_TSV'
    printf '%s\n' 'BEGIN_AI_UPGRADER_SOURCES_TSV'
    printf '%s\n' $'axis\turl\twhat'
    cat "$srcf"
    printf '%s\n' 'END_AI_UPGRADER_SOURCES_TSV'
  } > "$file"
  rm -f "$srcf"
}

install_mock() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/claude" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
prompt="${*: -1}"
case "$prompt" in
  *'DISCOVERY/PLAN ONLY'*)
    cat "$SYNTH_PLAN"
    ;;
  *'INDEPENDENT WHOLE-MILESTONE REVIEW'*|*'Read-only milestone review'*)
    printf 'MILESTONE REVIEW: PASS\n'
    ;;
  *'The ONLY primary axis allowed to move is:'*)
    case "${SYNTH_CASE:-}" in
      npm_ts_fat_lockfile_pass|npm_vue_locked_ts_pass)
        sed -i.bak 's/"typescript": "5.9.3"/"typescript": "6.0.2"/' package.json
        sed -i.bak 's/"version": "5.9.3"/"version": "6.0.2"/' package-lock.json
        rm -f package.json.bak package-lock.json.bak
        git add package.json package-lock.json
        git commit -qm 'upgrade(typescript): 5.9.3 -> 6.0.2'
        ;;
      npm_oneline_json_pass)
        printf '%s\n' '{"name":"synth-app","engines":{"node":">=24"},"devDependencies":{"typescript":"6.0.2"}}' > package.json
        printf '%s\n' '{"packages":{"":{"engines":{"node":">=24"}},"node_modules/typescript":{"version":"6.0.2"},"node_modules/other":{"version":"1.0.0"}}}' > package-lock.json
        git add package.json package-lock.json
        git commit -qm 'upgrade(typescript): oneline'
        ;;
      npm_node_pin_stolen_block)
        sed -i.bak 's/"typescript": "5.9.3"/"typescript": "6.0.2"/; s/"node": ">=24"/"node": ">=22"/' package.json
        sed -i.bak 's/"version": "5.9.3"/"version": "6.0.2"/; s/"node": ">=24"/"node": ">=22"/' package-lock.json
        rm -f package.json.bak package-lock.json.bak
        git add package.json package-lock.json
        git commit -qm 'upgrade(typescript): also moved node pin'
        ;;
      npm_workflow_pass)
        sed -i.bak 's/"typescript": "5.9.3"/"typescript": "6.0.2"/' package.json
        sed -i.bak 's/"version": "5.9.3"/"version": "6.0.2"/' package-lock.json
        rm -f package.json.bak package-lock.json.bak
        git add package.json package-lock.json
        git commit -qm 'upgrade(typescript): workflow node-version stays'
        ;;
      npm_workflow_stolen_block)
        sed -i.bak 's/"typescript": "5.9.3"/"typescript": "6.0.2"/' package.json
        sed -i.bak 's/"version": "5.9.3"/"version": "6.0.2"/' package-lock.json
        sed -i.bak 's/node-version: 24/node-version: 22/' .github/workflows/ci.yml
        rm -f package.json.bak package-lock.json.bak .github/workflows/ci.yml.bak
        git add package.json package-lock.json .github/workflows/ci.yml
        git commit -qm 'upgrade(typescript): stole node-version'
        ;;
      composer_laravel_pass)
        sed -i.bak 's/"laravel\/framework": "10.48.0"/"laravel\/framework": "11.0.0"/' composer.json
        sed -i.bak 's/"version": "10.48.0"/"version": "11.0.0"/' composer.lock
        rm -f composer.json.bak composer.lock.bak
        git add composer.json composer.lock
        git commit -qm 'upgrade(laravel): 10.48.0 -> 11.0.0'
        ;;
      docker_framework_stolen_block)
        printf 'runtime 2\n' > runtime.txt
        printf 'FROM example/framework:2\n' > Dockerfile
        git add runtime.txt Dockerfile
        git commit -qm 'upgrade(runtime): also moved framework image'
        ;;
      *)
        printf 'unexpected writer case %s\n' "${SYNTH_CASE:-unset}" >&2
        exit 92
        ;;
    esac
    ;;
  *)
    printf 'unexpected prompt\n' >&2
    exit 92
    ;;
esac
MOCK
  chmod +x "$bin/claude"
}

init_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.name 'Synth Test'
  git -C "$dir" config user.email 'synth@example.invalid'
}

write_make_grep() {
  local needle="$1"
  cat > Makefile <<MAKE
.PHONY: runtime-fast runtime-milestone
runtime-fast:
	@grep -F -q '$needle' $2
runtime-milestone:
	@grep -F -q '$needle' $2
MAKE
}

run_upgrade() {
  local name="$1" expect="$2" repo="$3" plan="$4" target_axis="$5" target_ver="$6" needle="$7"
  local home="$WORKDIR/$name.home"
  local bin="$home/bin"
  local log="$WORKDIR/$name.log"
  mkdir -p "$home/.local/share/ai-upgrader/skills" "$bin"
  cp "$ROOT_DIR/skills/universal-upgrade.md" "$home/.local/share/ai-upgrader/skills/universal-upgrade.md"
  install_mock "$bin"
  export HOME="$home"
  export AI_UPGRADER_HOME="$home/.local/share/ai-upgrader"
  export AI_UPGRADER_FAST_WAIT=1
  export SYNTH_CASE="$name"
  export SYNTH_PLAN="$plan"
  export PATH="$bin:$ORIG_PATH"
  local rc=0
  set +e
  (
    echo "=== $name expect=$expect ==="
    cd "$repo"
    bash "$UPGRADER" init claude
    bash "$UPGRADER" target "$target_axis" "$target_ver"
    bash "$UPGRADER" plan --import "$plan"
    bash "$UPGRADER" upgrade --provider claude --goal "Upgrade $target_axis"
    echo "upgrade_exit=$?"
    bash "$UPGRADER" status || true
  ) >"$log" 2>&1
  set -e
  rc="$(awk -F= '/^upgrade_exit=/{print $2; exit}' "$log" 2>/dev/null || echo 1)"
  local status_line blocker
  status_line="$(awk '$1=="Milestone"{print; exit}' "$log" || true)"
  blocker="$(grep -E 'ERROR:|BLOCKER:|locked axis' "$log" | tail -n 5 || true)"
  if [ "$expect" = pass ]; then
    if grep -q 'Upgrade complete: all milestones accepted' "$log" && grep -q 'Milestone status: ACCEPTED' "$log"; then
      if [ -n "$needle" ]; then
        if ! grep -F -q "$needle" "$repo"/* "$repo"/.github/workflows/* 2>/dev/null && ! grep -F -rq "$needle" "$repo" --include='package.json' --include='composer.json' --include='runtime.txt'; then
          RESULTS+=("FAIL $name: accepted but needle $needle missing")
          FAIL=$((FAIL+1))
          return
        fi
      fi
      RESULTS+=("PASS $name")
      PASS=$((PASS+1))
    else
      RESULTS+=("FAIL $name: expected accept; rc=$rc")
      FAIL=$((FAIL+1))
      tail -n 40 "$log" >> "$WORKDIR/failures.txt" || true
      printf '\n----- %s -----\n' "$name" >> "$WORKDIR/failures.txt"
      cat "$log" >> "$WORKDIR/failures.txt"
    fi
  else
    if grep -Eq 'locked axis|BLOCKER:|NOT VERIFIED|unrelated path' "$log" && [ "$rc" -ne 0 ]; then
      RESULTS+=("PASS $name (blocked as required)")
      PASS=$((PASS+1))
    else
      RESULTS+=("FAIL $name: expected locked-axis block; rc=$rc")
      FAIL=$((FAIL+1))
      printf '\n----- %s -----\n' "$name" >> "$WORKDIR/failures.txt"
      cat "$log" >> "$WORKDIR/failures.txt"
    fi
  fi
}

# --- fixtures ---

# 1. Fat lockfile: typescript moves, node+vue pins stay
repo="$WORKDIR/npm_ts_fat_lockfile_pass"
init_repo "$repo"
(
  cd "$repo"
  write_pkg 5.9.3 > package.json
  write_fat_lock 5.9.3 > package-lock.json
  write_make_grep '6.0.2' package.json
  git add package.json package-lock.json Makefile
  git commit -qm baseline
)
write_plan "$WORKDIR/npm_ts_fat_lockfile_pass.plan" \
  typescript language 5.9.3 6.0.2 'package.json|package-lock.json' \
  node runtime 24 24 'package.json|package-lock.json' \
  vue framework 3.5.24 3.5.24 'package.json|package-lock.json'
run_upgrade npm_ts_fat_lockfile_pass pass "$repo" "$WORKDIR/npm_ts_fat_lockfile_pass.plan" typescript 6.0.2 '6.0.2'

# 2. One-line package.json (the greedy whole-file slice case)
repo="$WORKDIR/npm_oneline_json_pass"
init_repo "$repo"
(
  cd "$repo"
  printf '%s\n' '{"name":"synth-app","engines":{"node":">=24"},"devDependencies":{"typescript":"5.9.3"}}' > package.json
  printf '%s\n' '{"packages":{"":{"engines":{"node":">=24"}},"node_modules/typescript":{"version":"5.9.3"}}}' > package-lock.json
  write_make_grep '6.0.2' package.json
  git add package.json package-lock.json Makefile
  git commit -qm baseline
)
write_plan "$WORKDIR/npm_oneline_json_pass.plan" \
  typescript language 5.9.3 6.0.2 'package.json|package-lock.json' \
  node runtime 24 24 'package.json|package-lock.json'
run_upgrade npm_oneline_json_pass pass "$repo" "$WORKDIR/npm_oneline_json_pass.plan" typescript 6.0.2 '6.0.2'

# 3. Writer also moves engines.node — must BLOCK
repo="$WORKDIR/npm_node_pin_stolen_block"
init_repo "$repo"
(
  cd "$repo"
  write_pkg 5.9.3 '>=24' > package.json
  write_fat_lock 5.9.3 > package-lock.json
  write_make_grep '6.0.2' package.json
  git add package.json package-lock.json Makefile
  git commit -qm baseline
)
write_plan "$WORKDIR/npm_node_pin_stolen_block.plan" \
  typescript language 5.9.3 6.0.2 'package.json|package-lock.json' \
  node runtime 24 24 'package.json|package-lock.json'
run_upgrade npm_node_pin_stolen_block block "$repo" "$WORKDIR/npm_node_pin_stolen_block.plan" typescript 6.0.2 ''

# 4. GitHub workflow node-version stays
repo="$WORKDIR/npm_workflow_pass"
init_repo "$repo"
(
  cd "$repo"
  write_pkg 5.9.3 > package.json
  write_fat_lock 5.9.3 > package-lock.json
  write_workflow 24
  write_make_grep '6.0.2' package.json
  git add package.json package-lock.json Makefile .github
  git commit -qm baseline
)
write_plan "$WORKDIR/npm_workflow_pass.plan" \
  typescript language 5.9.3 6.0.2 'package.json|package-lock.json' \
  node runtime 24 24 'package.json|package-lock.json|.github/workflows/ci.yml'
run_upgrade npm_workflow_pass pass "$repo" "$WORKDIR/npm_workflow_pass.plan" typescript 6.0.2 '6.0.2'

# 5. Workflow node-version stolen — must BLOCK
repo="$WORKDIR/npm_workflow_stolen_block"
init_repo "$repo"
(
  cd "$repo"
  write_pkg 5.9.3 > package.json
  write_fat_lock 5.9.3 > package-lock.json
  write_workflow 24
  write_make_grep '6.0.2' package.json
  git add package.json package-lock.json Makefile .github
  git commit -qm baseline
)
write_plan "$WORKDIR/npm_workflow_stolen_block.plan" \
  typescript language 5.9.3 6.0.2 'package.json|package-lock.json' \
  node runtime 24 24 'package.json|package-lock.json|.github/workflows/ci.yml'
run_upgrade npm_workflow_stolen_block block "$repo" "$WORKDIR/npm_workflow_stolen_block.plan" typescript 6.0.2 ''

# 6. Composer: laravel moves, php pin stays, lockfile churns
repo="$WORKDIR/composer_laravel_pass"
init_repo "$repo"
(
  cd "$repo"
  cat > composer.json <<'JSON'
{
  "name": "synth/app",
  "require": {
    "php": ">=8.2",
    "laravel/framework": "10.48.0"
  }
}
JSON
  cat > composer.lock <<'JSON'
{
  "content-hash": "aaa",
  "packages": [
    { "name": "laravel/framework", "version": "10.48.0" }
  ]
}
JSON
  write_make_grep '11.0.0' composer.json
  git add composer.json composer.lock Makefile
  git commit -qm baseline
)
write_plan "$WORKDIR/composer_laravel_pass.plan" \
  laravel framework 10.48.0 11.0.0 'composer.json|composer.lock' \
  php runtime 8.2 8.2 'composer.json|composer.lock'
run_upgrade composer_laravel_pass pass "$repo" "$WORKDIR/composer_laravel_pass.plan" laravel 11.0.0 '11.0.0'

# 7. Docker FROM tag of a locked framework moves during runtime upgrade — BLOCK
repo="$WORKDIR/docker_framework_stolen_block"
init_repo "$repo"
(
  cd "$repo"
  printf 'runtime 1\n' > runtime.txt
  printf 'FROM example/framework:1\n' > Dockerfile
  cat > Makefile <<'MAKE'
.PHONY: runtime-fast runtime-milestone
runtime-fast:
	@grep -qx 'runtime 2' runtime.txt
runtime-milestone:
	@grep -qx 'runtime 2' runtime.txt
MAKE
  git add runtime.txt Dockerfile Makefile
  git commit -qm baseline
)
write_plan "$WORKDIR/docker_framework_stolen_block.plan" \
  runtime runtime 1 2 runtime.txt \
  framework framework 1 1 Dockerfile
run_upgrade docker_framework_stolen_block block "$repo" "$WORKDIR/docker_framework_stolen_block.plan" runtime 2 ''

# 8. Same-file vue lock + ts upgrade (piktochart shape)
repo="$WORKDIR/npm_vue_locked_ts_pass"
init_repo "$repo"
(
  cd "$repo"
  write_pkg 5.9.3 > package.json
  write_fat_lock 5.9.3 > package-lock.json
  write_make_grep '6.0.2' package.json
  git add package.json package-lock.json Makefile
  git commit -qm baseline
)
write_plan "$WORKDIR/npm_vue_locked_ts_pass.plan" \
  typescript language 5.9.3 6.0.2 'package.json|package-lock.json' \
  node runtime 24 24 'package.json|package-lock.json' \
  vue framework 3.5.24 3.5.24 'package.json|package-lock.json'
run_upgrade npm_vue_locked_ts_pass pass "$repo" "$WORKDIR/npm_vue_locked_ts_pass.plan" typescript 6.0.2 '6.0.2'

printf '\n========== synthetic upgrades ==========\n'
printf '%s\n' "${RESULTS[@]}"
printf 'pass=%s fail=%s logs=%s\n' "$PASS" "$FAIL" "$WORKDIR"
[ "$FAIL" -eq 0 ]
