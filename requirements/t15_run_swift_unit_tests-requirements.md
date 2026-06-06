# t15 run swift unit tests Lane Requirements

## Scope

Applies to `tests/t15_run_swift_unit_tests.sh`.

R001  Statement: Lane runs with a secure umask and strict shell mode before any work.
Design: Set `umask 007` and `set -euo pipefail` at the top of the self-contained lane so failures abort and artifacts are not world-readable.
Tests:
- R001-T01: Verify the lane sets a secure umask before running.

R005  Statement: Lane resolves roots, loads the mailcart runbook environment, and arms the macOS build lock.
Design: Resolve `RUNNER_HOME` and `RUNBOOK_REPO_ROOT`, export `RUNBOOK_REPO_ROOT`, source `runner/config/runbook/mailcart.env`, then source `scripts/macos_build_lock.sh`.
Tests:
- R005-T01: Verify the lane sources `runner/config/runbook/mailcart.env`.

R010  Statement: Lane runs the Swift unit-test target under the macOS build lock.
Design: Run `with_macos_build_lock make _swift-unit-tests`.
Tests:
- R010-T01: Verify the lane runs `with_macos_build_lock make _swift-unit-tests`.
