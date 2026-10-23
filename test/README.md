# Deterministic Bats suite

This suite tests AI Upgrader itself. It creates only disposable Git repositories
under `BATS_TEST_TMPDIR`; it does not create or upgrade an application.

All provider behavior is supplied by `helpers/mocks.bash`. The mock records each
plan, writer, and review call. Tests use real Git inside the disposable
repository and never call a network, remote CI, or a real AI provider.

Coverage:

- `yaml.bats`: P0-01..05, P1-01..02, H-01.
- `discovery.bats`: P0-06..07, P1-09, opened-source lock rules.
- `manifests.bats`: synthetic package.json, Composer, Gemfile, go.mod, Cargo.toml, pyproject.toml, mix.exs.
- `targets.bats`: P0-08..09, P1-05, H-05.
- `locked_axes.bats`: P0-10..12, P1-06..07/10, H-02/H-09.
- `synthetic_upgrades.sh`: full `init → plan --import → upgrade` loops on generated npm/composer/docker repos (fat lockfile, one-line JSON, stolen pins, workflow, Laravel). Not part of `make test`.
- `dag.bats`: P0-13..16, P1-08, disconnected DAG.
- `ci_gates.bats`: P0-17..19/21, H-04/H-07/H-10.
- `review.bats`: P0-20, P1-14, missing review evidence.
- `stop_resume.bats`: P0-22..23, P1-12..13, idempotent stop, resume re-runs stale FAIL gates.
- `git_safety.bats`: P0-24, P1-03..04/11, H-06.
- `security.bats`: H-03/H-08 and provider boundary probes.
- `milestones.bats`: state-machine and fresh-upgrade regressions.

Commands:

```sh
make test
make test-unit
make test-integration
make test-security
make test-lint
bats --filter 'locked axis' test/locked_axes.bats
bash test/synthetic_upgrades.sh
bats --timing -r test/
bats --formatter junit -r test/
```

When a test fails, rerun the exact named test, classify the failure as
`PRODUCTION_BUG`, `TEST_BUG`, `FIXTURE_BUG`, `MOCK_BUG`,
`ENVIRONMENT_FAILURE`, `UNSUPPORTED_CONTRACT`, or `FLAKY_TEST`, then rerun its
file before the complete suite. Assertions must not be weakened to obtain green.
