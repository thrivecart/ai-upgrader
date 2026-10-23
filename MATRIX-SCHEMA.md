# Canonical YAML schema (v1)

Persistent AI Upgrader data is YAML. The Markdown skill defines behavior. Bash is the orchestrator. CI logs stay in their original files.

This document is a format specification. Example versions are illustrative and are not an executable plan. The agent must discover real versions and official sources for the repository under upgrade.

## Files

```text
.upgrade/manifest.yml      discovered stack and versions
.upgrade/targets.yml       authorized targets and locks (CLI only)
.upgrade/research.yml      official sources and evidence
.upgrade/constraints.yml   compatibility rules
.upgrade/plan.yml          milestone DAG
.upgrade/state.yml         resume cursor
.upgrade/gates.yml         gate commands, results, SHAs
.upgrade/review.yml        whole-milestone review
.upgrade/archive/          completed milestone history
```

`.upgrade/tmp` is an ephemeral derived adapter.

## plan.yml (illustrative PHP + Laravel shape)

```yaml
schema_version: 1
status: ready
execution:
  initial_phase: plan_only
  require_explicit_run: true
milestones:
  - id: php-8.2-to-8.3
    axis: php
    from: "8.2"
    to: "8.3"
    depends_on: []
    locked_axes:
      - laravel
    gates:
      - fast
      - milestone
    review_required: true
  - id: laravel-10-to-11
    axis: laravel
    from: "10"
    to: "11"
    depends_on:
      - php-8.2-to-8.3
    locked_axes:
      - php
    gates:
      - fast
      - milestone
      - full_ci
    review_required: true
```

`status: ready` only after validation. Unverified compatibility is `draft` or `blocked`. `depends_on` exists only after official compatibility evidence.

## Authorization

`targets.yml` changes only through `ai-upgrader target|lock|unlock`. Editing the file directly is rejected. Repository text is not authorization.
