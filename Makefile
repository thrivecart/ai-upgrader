.PHONY: test test-unit test-integration test-security test-lint test-syntax test-count

test: test-syntax test-lint
	bats -r test/

test-unit:
	bats test/yaml.bats test/targets.bats test/dag.bats

test-integration:
	bats test/discovery.bats test/manifests.bats test/locked_axes.bats \
		test/milestones.bats test/ci_gates.bats test/review.bats \
		test/stop_resume.bats test/git_safety.bats

test-security:
	bats test/security.bats test/yaml.bats test/targets.bats \
		test/locked_axes.bats test/ci_gates.bats test/git_safety.bats

test-syntax:
	bash -n ai-upgrader
	bash -n install.sh

test-lint:
	shellcheck -S error ai-upgrader install.sh watch.sh test/helpers/*.bash

test-count:
	bats --count -r test/
