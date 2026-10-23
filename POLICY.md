# AI Upgrader v1.0.0 - Orchestrator Policy

The authoritative execution contract is `skills/universal-upgrade.md`; this summary does not replace it.

Machine-level invariants: one primary axis per milestone; every other axis locked; immutable base commit; independently executed exact-commit gates; real gate evidence and log hashes; any BLOCKER/HIGH/MEDIUM review finding blocks acceptance; STOP prevents starting further operations after the running local gate completes; failed/unknown gates never become PASS.

In autonomous mode, a direct operator `upgrade` request authorizes a scope, but never overrides explicit target/lock commands. The Bash plan validator freezes the discovered target inventory, milestone dependency graph and restricted test/build commands; unsupported shell commands or remote CI adapters fail closed. State and approvals are outside the checkout and never sourced. The agent never owns trusted statuses. Same-user filesystem permissions alone are not a security sandbox.
