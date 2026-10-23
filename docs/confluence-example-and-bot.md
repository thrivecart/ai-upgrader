## Example run (real output, Node + Vue repo)

```text
$ ai-upgrader upgrade
No plan; planning from scratch
[upgrade] plan
  streaming model output
  still running (15s) … (75s)
  plan payload ready (77s)
Plan ready
Axes:
node_runtime   runtime            20.19.4 -> 24.22.1  upgrade
vue            frontend_framework  3.5.25 -> 3.5.44   upgrade
typescript     language             5.4.5 (locked)
Milestones:
node-22      node_runtime  20.19.4 -> 22.23.4
node-24      node_runtime  22.23.4 -> 24.22.1   (depends on node-22)
vue-3.5.44   vue            3.5.25 -> 3.5.44
Gates (per milestone):
fast_gate        npm run lint                              required
milestone_gate   npm run test:unit -- --run && npm run build  required
full_ci / smoke  not required
Progress [░░░░░░░░░░░░░░░░░░░░] 0/3 milestones (0%)
[upgrade] approve
Autonomous plan approved by the upgrade command under restricted gate policy.
[upgrade] begin
Active milestone: node-22; immutable BASE_SHA=af2ba32c…
[upgrade] writer
Writer done HEAD=892aff3b…
[upgrade] fast_gate
fast_gate: PASS for 892aff3b… (exit=0)
[upgrade] milestone_gate
```

How to read it:

| Output | Meaning |
|---|---|
| `[upgrade] plan` … `plan payload ready` | The AI is discovering the stack and writing the plan (about 1–2 min). No progress bar yet. |
| `Plan ready` + tables | Axes, milestones and gate commands. Review them. `locked` axes will not move. |
| `[upgrade] approve` | The tool freezes the plan and gate commands. Only known test/build commands are auto-approved. |
| `Progress [░░░] n/m` | Printed before every stage. Fills as milestones are `ACCEPTED`. |
| `begin` → `writer` → `fast_gate` → `milestone_gate` → `review` → `accept` | One milestone. `PASS for <sha>` means the gate ran on exactly that commit. |
| `still running (Ns)` | Heartbeat every 15 s while a step runs. |
| `STATUS: <step> running Nm \| milestone … \| Progress […]` | Every 10 min: what it is working on now (`AI_UPGRADER_STATUS_SEC` to change). |

At any time, in another terminal: `ai-upgrader status`.

## Bot status (Grok bot)

`ai-upgrader upgrade` starts the watcher (`ai-upgrader-watch`) automatically in the background when the config below is filled. The watcher reads `.upgrade/state.yml` every 15 s and posts events to the bot webhook. Without the config nothing is sent and the bot stays empty.

**What to give the bot / config**

1. In the bot automation create a webhook trigger and copy its **URL** and the **auth header** it expects (for example `Authorization: Bearer <key>`).
2. Put them on the machine that runs the upgrade:

```bash
mkdir -p ~/.config/ai-upgrader
cp ~/.config/ai-upgrader/watch.env.example ~/.config/ai-upgrader/watch.env   # created by install.sh
chmod 600 ~/.config/ai-upgrader/watch.env
# edit watch.env:
WEBHOOK_URL='https://…'
WEBHOOK_AUTH_HEADER='Authorization: Bearer …'
POLL=15          # seconds between checks
STALL_SEC=900    # no activity this long = "stalled"
STATUS_SEC=600   # heartbeat to the bot
```

3. Paste the **bot prompt** (it is in the comments of `watch.env.example`) into the bot automation so it posts one status line per event:

```text
You receive webhook events from ai-upgrader, a tool that upgrades a repo's
stack milestone by milestone. Each event is JSON: {source, repo, kind, text}.
Post one short message to this chat for EVERY event, and do nothing else.
- start, progress: ▶️ then the text
- status: 🔄 then the text (heartbeat every 10 min)
- done: ✅ then the text
- blocker, stalled, died, stopped: 🚨 URGENT then the text, plus one line on what to check
Rules: one message per event, no summaries; skip a duplicate (same kind and text)
within 10 minutes; do not run commands or change anything. Only report.
```

**Events the bot receives**

| kind | When |
|---|---|
| `start` | watcher started (phase, milestone) |
| `progress` | phase, milestone, milestone status or review changed |
| `status` | heartbeat every `STATUS_SEC` (10 min): milestones accepted n/m, phase, gates, last activity |
| `blocker` | the run stopped with a blocker |
| `stalled` | no activity in `.upgrade/` for `STALL_SEC` while the process runs |
| `died` | the `ai-upgrader` process is gone and phase is not COMPLETE |
| `stopped` | `ai-upgrader stop` was requested |
| `done` | all milestones accepted |

Payload: `{"source":"ai-upgrader","repo":"<repo name>","kind":"progress","text":"[ai-upgrader:<repo>] progress: phase=… milestone=… status=… review=…"}`.

**Check it works**

```bash
cat .upgrade/watch.log     # watcher output, "webhook send failed" = wrong URL/header
cat .upgrade/events.log    # every event that was sent
```

Opt out: `AI_UPGRADER_NO_WATCH=1 ai-upgrader upgrade`. Manual start (other commands): `ai-upgrader-watch <repo>`. Stop: `kill $(cat .upgrade/watch.pid)`.
