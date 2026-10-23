# AI Upgrader v1.0.0

Language-agnostic upgrade orchestrator. Bash only. Discovers the stack, writes a YAML version matrix, then moves **one primary axis per milestone** with exact-SHA gates and an independent review.

**Current version:** 1.0.0  
**Providers:** `claude`, `codex`, `cursor` (`agent`), `manual`  
**Canonical state:** `.upgrade/*.yml`

---

## What it is and what it runs on

Upgrades an existing git project step by step (Node 18→20→22, TypeScript 5.3→5.9, Vue 3.4→3.5, Rails, Laravel, …), never "everything to latest".

1. Discovers the stack and writes a version plan.
2. Each **milestone** moves one axis (runtime, language, framework, frontend framework); all other axes stay locked.
3. An AI writes the change and commits it. The tool runs your gates on that exact commit, gets an independent AI review, then accepts and takes the next milestone.

The AI never marks PASS. Pass/fail comes from the Bash orchestrator: real exit codes, exact SHA, log hashes.

| Part | What |
|---|---|
| Orchestrator | one standalone Bash script, `ai-upgrader` |
| Behavior contract | Markdown skill `skills/universal-upgrade.md`, given to the AI |
| State | YAML in `.upgrade/` inside your repo (git-ignored) |
| AI providers | `claude`, `codex`, `cursor` (`agent`), `manual` |
| Requires | Bash, Git, awk, `sha256sum`/`shasum`, one authenticated provider CLI |

Flow: `init → plan → (target/lock → plan) → approve-plan → upgrade`, and per milestone `begin → run → gates → review → accept`.

---

## Quick start

```bash
unzip ai-upgrader-v1.0.0.zip && cd ai-upgrader-v1.0.0
./install.sh                      # then add ~/.local/bin to PATH if needed
ai-upgrader doctor                # checks git + provider CLI

cd /path/to/your/repo             # clean git working tree
ai-upgrader upgrade               # init → plan → approve → upgrade all milestones
ai-upgrader status                # progress, any time (other terminal)
```

Stopped or blocked? Read the last `ERROR:` / `BLOCKED` line, fix it in the repo, then `ai-upgrader resume`. Pause on purpose: `ai-upgrader stop`.

Want to check the plan before anything changes? `ai-upgrader init && ai-upgrader plan && ai-upgrader graph`, then `ai-upgrader approve-plan && ai-upgrader upgrade`.

---

## After `plan` — what to do next

You already have a draft plan. Nothing in the repository has been upgraded yet.

```bash
cd /path/to/your/git/project

# 1. Read the matrix
ai-upgrader graph
# or open:
#   .upgrade/plan.yml
#   .upgrade/manifest.yml
#   .upgrade/gates.yml

# 2. If the versions are wrong, set targets and replan (plan wipes and rebuilds)
ai-upgrader target vue_framework 3.6
ai-upgrader lock typescript_lang 5.3.0
ai-upgrader plan

# 3. Freeze the gate commands (required before any writer)
ai-upgrader approve-plan

# 4. Run the upgrade
ai-upgrader upgrade
```

`upgrade` after an approved plan does **not** replan. It walks `begin → run → gates → review → accept` until every milestone is `ACCEPTED` or something blocks.

Manual equivalent of step 4:

```bash
ai-upgrader begin
ai-upgrader run
ai-upgrader gates
ai-upgrader review
ai-upgrader accept
# repeat until status says COMPLETE / no eligible milestone
```

Inspect anytime:

```bash
ai-upgrader status
ai-upgrader stop      # do not start the next stage
ai-upgrader resume    # clear stop and continue the same plan
```

---

## Install

Requires Bash, Git, awk, and `sha256sum` or `shasum`. Autonomous mode needs an authenticated `claude`, `codex`, or Cursor `agent`.

```bash
unzip ai-upgrader-v1.0.0.zip
cd ai-upgrader-v1.0.0
./install.sh
```

Installs:

| What | Where |
|---|---|
| executable | `~/.local/bin/ai-upgrader` |
| skill + docs | `~/.local/share/ai-upgrader/` |

Add `~/.local/bin` to `PATH` if needed. Override prefixes with `AI_UPGRADER_PREFIX` and `AI_UPGRADER_HOME`.

Help:

```bash
ai-upgrader help
ai-upgrader --help
```

---

## Two ways to work

### A. One command (autonomous)

```bash
cd /path/to/clean/git/repo
ai-upgrader upgrade
ai-upgrader upgrade --provider claude --goal 'Upgrade Node and TypeScript'
ai-upgrader upgrade --target node_runtime=22 --lock vue_framework
```

On a new repo this does init, plan, restricted auto-approve, then the milestone loop. On an existing approved plan it keeps the plan and executes.

### B. Step by step (after you already planned)

```text
plan → graph → (optional target/lock + plan) → approve-plan → upgrade
```

or fully manual: `begin` `run` `gates` `review` `accept`.

Worktree must be clean for plan approval, begin, gates, review, and accept.

---

## Global option

| Option | Values | Where | Effect |
|---|---|---|---|
| `--provider` | `claude` `codex` `cursor` | Before or after the command name, every command | Pin the AI CLI. Auto-detect order: claude, then codex, then cursor `agent`. |

```bash
ai-upgrader --provider cursor plan
ai-upgrader plan --provider claude
ai-upgrader --provider claude upgrade --goal 'Upgrade Node'
```

`init` also accepts the provider as a positional argument: `ai-upgrader init claude`.

---

## Bot notifications (`ai-upgrader-watch`)

A separate watcher polls `.upgrade/state.yml` and posts events to the Grok bot webhook. `install.sh` installs it as `ai-upgrader-watch`. `ai-upgrader upgrade` starts it automatically in the background when `watch.env` has both `WEBHOOK_URL` and `WEBHOOK_AUTH_HEADER` filled (pid in `.upgrade/watch.pid`, log in `.upgrade/watch.log`; a second `upgrade` reuses a running one). Disable with `AI_UPGRADER_NO_WATCH=1`. Manual start/other commands: below.

```bash
cp ~/.config/ai-upgrader/watch.env.example ~/.config/ai-upgrader/watch.env
chmod 600 ~/.config/ai-upgrader/watch.env   # fill WEBHOOK_URL and WEBHOOK_AUTH_HEADER
ai-upgrader-watch /path/to/repo             # manual start (only needed for commands other than `upgrade`)
```

- Without a filled config the watcher exits with `ERROR: setup bot webhook: …` (code 2).
- Events (`kind`): `start`, `progress` (phase / milestone / status / review changed), `status` (heartbeat every `STATUS_SEC`, default 600 s: milestones accepted n/m, phase, gates, last activity), `blocker`, `stalled` (no activity for `STALL_SEC`), `died` (process gone), `stopped`, `done`.
- Payload: `{source, repo, kind, text}`, header from `WEBHOOK_AUTH_HEADER`. Events are also appended to `.upgrade/events.log`.
- `watch.env.example` holds the Grok bot prompt in its comments.
- Needs `.upgrade/state.yml`. It exits itself on `COMPLETE`; on `BLOCKED`/`STOPPED` it keeps running so you get `resume` events. Stop it with `kill $(cat .upgrade/watch.pid)`.

---

## Command reference

### `init [claude\|codex\|cursor\|manual]`

Creates `.upgrade/`, writes empty YAML, records HEAD, excludes `.upgrade/` via `.git/info/exclude`.

- With existing `state.yml`, **wipes** `.upgrade/` and starts over.
- `manual` cannot call the model; use `plan --import` and `review --import`.
- Does not change the git repository besides the exclude file.

### `target <component> <version>`

Authorize an upgrade axis. Written only through this command (or `upgrade --target`). Direct edits to `targets.yml` are rejected.

```bash
ai-upgrader target node_runtime 22
ai-upgrader target vue_framework 3.6
```

Invalidates any previous `approve-plan`. Re-run `plan` after changing targets. Cannot change targets during an active milestone.

### `lock <component> [version]`

Keep an axis still. Omitted version means `CURRENT` (whatever discovery finds).

```bash
ai-upgrader lock vue_framework
ai-upgrader lock typescript_lang 5.3.0
```

Same rules as `target`: CLI only, replan after, blocked during an active milestone.

### `unlock <component>`

Remove that row from the operator registry. Discovery may still lock or upgrade it on the next plan.

### `targets`

Print the operator registry (TSV adapter derived from `targets.yml`). Empty registry is not a lock.

### `plan [--provider …] [--import <file>]`

Read-only discovery. Wipes previous plan YAML, keeps operator targets and provider, asks the model, validates TSV blocks, writes canonical YAML.

```bash
ai-upgrader plan
ai-upgrader plan --provider claude
ai-upgrader plan --import /path/to/plan.md
```

- Does **not** modify project source.
- `--import` is required for `manual`.
- Failed model output is kept as `.upgrade/archive/plan.failed.md`.
- If fetch tools work, the model should open official release pages. If they do not, it must still build the matrix from knowledge and put official URLs in `research.yml` — it must **not** lock an axis only because a page was not opened.
- Lock only for: explicit `lock`, already on the current safe target, no next official step, or a real incompatibility **in this repository**.
- After the plan is validated, the tool runs `git grep -w` for each `upgrade` axis's current version (dotted versions only, e.g. `20.19.4`) and **automatically adds** every tracked file that still contains it and is not in any axis's `source_of_truth` (CI, Dockerfiles, scripts, README). Files of other axes are skipped; if more than 30 files match, nothing is added and a warning is printed (`AI_UPGRADER_AUTOPIN_MAX`). Added paths show in the plan's `Axes` table. Disable with `AI_UPGRADER_NO_AUTOPIN=1`.
- Official latest is the research ceiling. A milestone is only a step this repo can install and gate now. If repo-invoked tools cannot take the next official version, stop at the last installable version and record `blocked_at`. Do not put a doomed step in the plan.

### `graph`

Dump `targets.yml`, `manifest.yml`, `research.yml`, `constraints.yml`, `plan.yml`, `gates.yml`, `state.yml` to stdout.

### `approve-plan`

Operator (or autonomous `upgrade`) freezes the current YAML-derived plan hash. After this, gate commands are executable. HEAD must match the plan baseline; tree must be clean; phase must be `PLANNED`.

Does not re-import `plan.raw.md`. Approves the YAML already on disk.

### `auto-approve`

Used by `upgrade`. Same freeze, but every required gate command must match the restricted no-shell allow-list (`make test`, `npm test`, `bundle exec rspec`, …). Unknown or `sha-success` remote CI commands **block** instead of auto-approving.

### `begin`

Select the next eligible DAG milestone (dependencies `ACCEPTED`, not already accepted). Records immutable `BASE_SHA = HEAD`. If a milestone is already active, prints it and returns.

### `run`

One writer call for the active milestone. Model may change only that axis’s `source_of_truth` files and must commit. Dirty unrelated paths fail. Locked axis pins must not move; shared manifests/lockfiles may change if those pins stay.

This is **one** writer step. The loop is `upgrade`.

### `gate <fast_gate\|milestone_gate\|full_ci\|smoke>`

Run one gate from `gates.yml` at the exact current HEAD. Writes log + evidence under `.upgrade/archive/`. Required gates must exit 0, leave a clean tree, and not move HEAD. `sha-success` also needs:

```text
CI_SHA=<40-char head>
CI_STATUS=success
```

Disabled gates (`required: false`) print `NOT_REQUIRED` and return 0.

### `gates`

Run all four gates for the active milestone; skips those that are not required.

### `review [--import <file>]`

Read-only whole-milestone review of `BASE_SHA...HEAD`. Import is only for `manual`. PASS requires the exact line `MILESTONE REVIEW: PASS` and no BLOCKER/HIGH/MEDIUM. Report is stored in `.upgrade/archive/reviews/review.md` and `review.yml`.

### `accept`

Accept the active milestone if gates and review PASS for this exact HEAD, locked axes did not move, and the tree is clean. Marks the milestone `ACCEPTED` in `plan.yml`.

### `upgrade [options] [goal…]`

Autonomous loop.

| Option | Argument | Meaning |
|---|---|---|
| `--provider` | `claude` `codex` `cursor` | Model CLI |
| `--goal` | string | Operator intent (one line) |
| `--target` | `axis=version` | Same as `target`, must be before planning |
| `--lock` | `axis` | Same as `lock` to `CURRENT`, must be before planning |
| `--` | rest of argv | Remaining words become the goal |

```bash
ai-upgrader upgrade
ai-upgrader upgrade --goal 'Upgrade Node, keep Vue locked'
ai-upgrader upgrade --target node_runtime=24 --lock vue_framework
ai-upgrader upgrade -- Upgrade Node to current LTS
```

Behavior:

1. If `plan.yml` + `state.yml` exist, keep them; otherwise plan from scratch.
2. `--target` / `--lock` only while phase is `DISCOVER` (before a plan). After a plan, change targets with `target`/`lock` and `plan` again.
3. Auto-approves only restricted gate commands.
4. For each milestone: writer (up to 3 attempts), required gates, review, accept.
5. Stops on blocker, unsafe gate, locked-axis drift, missing evidence, dirty tree, or `stop`.
6. Empty milestone list (everything already current) completes as a no-op.

### `status`

Progress bar with per-milestone marks, then phase, milestone, HEAD, gates, review, blocker, next action. Reads YAML (tmp adapter is disposable).

```text
Progress [██████████░░░░░░░░░░] 2/4 milestones (50%)
  ✓ m1  node_runtime 18 -> 20  [ACCEPTED]
  ✓ m2  node_runtime 20 -> 22  [ACCEPTED]
  ✗ m3  typescript_lang 5.3 -> 5.9  [BLOCKED]
  ▶ m4  vue 3.4 -> 3.5  [ACTIVE]
```

`✓` accepted, `▶` active, `✗` blocked, `·` pending. `upgrade` prints the one-line bar before every stage. While a step runs it prints `still running (Ns)` every 15 s and, every 10 minutes, a status line (`STATUS: <step> running Nm | milestone … | Progress […]`; change with `AI_UPGRADER_STATUS_SEC`).

### `stop`

Sets `STOP_REQUESTED=1`. A running local gate finishes; the loop will not start the next stage. Prints a handoff cursor.

### `resume`

Clears the stop flag. If `AUTO_MODE=1`, continues `upgrade` with the same frozen goal and plan. Otherwise runs one `run`.

### `skill [cat]`

Show the active universal skill path and SHA256. `skill cat` prints the full skill.

### `doctor`

Print git / provider / `gh` / `claude` / `codex` / `agent` availability. Does not call a model.

---

## What a plan contains

Canonical files (same YAML for you, the agent, and the orchestrator):

```text
.upgrade/manifest.yml      discovered axes: current, target, policy, source_of_truth
.upgrade/targets.yml       operator target/lock registry (CLI only)
.upgrade/research.yml      official https URLs (`opened` live lookup; model_knowledge cannot lock)
.upgrade/constraints.yml   compatibility edges
.upgrade/plan.yml          milestone DAG (one primary axis per row)
.upgrade/gates.yml         gate commands, results, SHAs, log hashes
.upgrade/state.yml         resume cursor
.upgrade/review.yml        last independent review
.upgrade/archive/          durable gate logs and review body
.upgrade/tmp/              ephemeral TSV adapter; safe to delete
```

`.upgrade/` is gitignored via `.git/info/exclude`.

**Primary axes:** language, runtime, framework, frontend_framework, plus anything you `target`/`lock`.  
**Not axes:** gems, npm packages, linters, Vite unless you explicitly target it, CSS kits, CI actions as their own tracks. They ride along as cargo only when they can consume the active step.

**Monorepos:** a bare manifest name in `source_of_truth` (`package.json`, `package-lock.json`, `tsconfig.json`, …) covers that file at any depth, e.g. `lambdas/x/package.json`. Entries with a `/` match exactly or as a glob (`lambdas/*/package.json`). `node_modules/` and `vendor/` are never covered.

**CI workflow files:** they are updated when listed in that axis’s `source_of_truth` (typical for `node_runtime`: `.github/workflows/*.yml`). That is file edits. Running GitHub Actions as a gate is separate: only if `full_ci` is `required: true` and approved.

---

## How versions are chosen

- Official docs / LTS pages decide candidate steps (for example Node 14→20→22).
- Minors can move (TypeScript 5.3→5.9) when that is the current stable line.
- A step goes into the plan only if this repository can take it now. Official latest alone is not enough.
- A framework already on its current major is often **locked**. Force a move with `target`.
- Explicit `target` / `lock` always win over discovery.

---

## Safety (what will not happen)

- Silent upgrade of a locked axis
- Fake `PASS` written by the model into state
- Gate evidence for the wrong SHA
- `git reset --hard`, `git clean -fd`, `git add -A`, force-push
- Weakening or deleting tests to get green
- New work after `stop` until `resume`
- Direct `targets.yml` edits counting as authorization

Autonomous gates are argv-exec’d, not `bash -c`. Manual `approve-plan` still allows inspected shell commands.

---

## Typical Node + Vue session

```bash
cd /path/to/your/git/project
ai-upgrader init claude
ai-upgrader plan
ai-upgrader graph
# optional: ai-upgrader target vue_framework 3.6 && ai-upgrader plan
ai-upgrader approve-plan
ai-upgrader upgrade
ai-upgrader status
```

---

## Axis model

| Kind | Examples |
|---|---|
| runtime | Node, Ruby, Python, JVM |
| language | TypeScript, Java language level |
| framework | Rails, Django, Laravel, Vue (if it is the app framework) |
| frontend_framework | Vue/React layer when separate from the backend framework |

Package managers, Vite, linters, test libraries are cargo unless you `target` them.

If you set some targets, untargeted primaries default to locked. If you set none, `plan`/`upgrade` may open primaries with a real current→target gap.

---

## Milestone state machine and gates

```text
PENDING → begin (BASE_SHA frozen) → run (commit) → gates (exact HEAD) → review (BASE...HEAD) → accept
```

Red stays on the same milestone (repair writer, re-gate, re-review); a failed edge never starts another axis. `BASE_SHA` never moves; a new HEAD invalidates old gate/review evidence.

| Gate | Typical use | May be NOT_REQUIRED |
|---|---|---|
| `fast_gate` | type-check / cheap tests | no |
| `milestone_gate` | real checkpoint tests | no |
| `full_ci` | repo-wide / remote CI | yes |
| `smoke` | e2e / smoke | yes |

PASS = exit 0, clean tree, unchanged HEAD, matching log hash and approval hash. Remote: `pass_condition=sha-success` plus `CI_SHA` / `CI_STATUS=success` for that SHA. Review: exact line `MILESTONE REVIEW: PASS`; BLOCKER/HIGH/MEDIUM always blocks. `source_of_truth` is the allow-list of paths the writer may change (manifest + companion lockfile; CI workflow files only when listed).

---

## When it stops

The process never asks questions. It prints `ERROR:` / `BLOCKED` and exits; that last line is the reason. `status` only shows the cursor. Gate logs: `.upgrade/archive/logs/`; failed plan: `.upgrade/archive/plan.failed.md`; review: `.upgrade/archive/reviews/review.md`. While running it prints `[upgrade] …` and `still running (Ns)` every ~15 s.

| What you see | What to do | Then |
|---|---|---|
| `ERROR:` / `BLOCKED` | Read that line first | `ai-upgrader status` |
| plan / TSV / hash invalid | Inspect `.upgrade/plan.yml` or `plan.failed.md`; change `target`/`lock` if needed | `ai-upgrader plan` |
| `working tree is dirty` | Commit or discard unrelated files | `resume` or `upgrade` |
| gate FAIL | Open the log in `.upgrade/archive/logs/`, fix code/tests, commit | `resume` |
| locked axis pin changed | Revert the pin (do not silently `unlock`); shared lockfile churn is not a move | `resume` |
| `unrelated path … changed during milestone` | Writer touched a path outside `source_of_truth`; revert it or drop the commit | `resume` |
| writer returned without a commit | If `.upgrade/tmp/logs/last-writer.out` says `MILESTONE EDGE: BLOCKED`, it is a compatibility stop (recorded, loop continues). Otherwise inspect the log | `resume` |
| review FAIL | Read `review.md`, fix, re-run gates | `resume` |
| you ran `stop` | Nothing to repair | `resume` |

Three writer attempts per milestone, then block. If the loop died mid-step: `status`, then `run` → `gates` → `review` → `accept` → `upgrade`.

---

## Do not rewrite history during a run

Between `begin` and `COMPLETE` do not `rebase`, `amend`, `filter-branch` or otherwise change SHAs of milestone commits. The tool binds everything to exact SHAs: `BASE_SHA`/`HEAD_SHA` in `.upgrade/state.yml`, gate evidence in `gates.yml`, and an anchor ref `refs/ai-upgrader/<milestone-id>/base`. After a rewrite you get `ERROR: BASE_SHA is not an ancestor of HEAD` or `immutable BASE_SHA mismatch`. Stop first (`ai-upgrader stop`), let the run finish, then rewrite.

Commit messages: the writer is told not to add `Co-Authored-By`, `Signed-off-by` or any AI attribution, and the `claude` writer runs with attribution disabled. Commits use the repository's git identity.

Recovery if you already rewrote (only when the rewrite changed messages, not content):

```bash
# 1. old and new commits must have identical trees
git rev-parse OLD^{tree} NEW^{tree}
# 2. in .upgrade/state.yml replace every old SHA with the new one
#    (BASE_SHA, HEAD_SHA, LAST_KNOWN_GOOD_SHA, CURRENT_BUILD_SHA); keep a copy first
# 3. move the anchor of the active (and any rewritten) milestone
git update-ref refs/ai-upgrader/<milestone-id>/base NEW OLD
ai-upgrader status      # must show recorded HEAD == actual HEAD
ai-upgrader resume
```

If the content changed, do not remap: restore the old commits (`git reflog`) or replan.

---

## Limitations

- Remote CI polling / cancel / handoff are not implemented. A remote adapter must print exact-SHA `sha-success`.
- Plan quality depends on the model. Fetch may still fail; then it uses training knowledge.
- Live multi-stack certification is not claimed by the bundled offline tests.
- `upgrade` will not auto-approve unknown shell or remote CI; it stops.

See also: [POLICY.md](POLICY.md), [MATRIX-SCHEMA.md](MATRIX-SCHEMA.md), [GRACEFUL-STOP-CONTRACT.md](GRACEFUL-STOP-CONTRACT.md), `skills/universal-upgrade.md`.
