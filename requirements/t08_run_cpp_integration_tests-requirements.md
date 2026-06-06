# t08 run cpp integration tests Lane Requirements

## Scope

Applies to `tests/t08_run_cpp_integration_tests.sh`.

R001  Statement: Lane runs with a secure umask and strict shell mode before any work.
Design: Set `umask 007` and `set -euo pipefail` at the top of the self-contained lane so failures abort and artifacts are not world-readable.
Tests:
- R001-T01: Verify the lane sets a secure umask before running.

R005  Statement: Lane resolves runner and repo roots and loads the mailcart runbook environment.
Design: Resolve `RUNNER_HOME` and `RUNBOOK_REPO_ROOT` from `BASH_SOURCE`, export `RUNBOOK_REPO_ROOT`, and source `runner/config/runbook/mailcart.env`.
Tests:
- R005-T01: Verify the lane sources `runner/config/runbook/mailcart.env`.

R010  Statement: Lane runs the Makefile C++ integration target from the repo root.
Design: `cd "$RUNBOOK_REPO_ROOT"` and `exec make _cpp-test`.
Tests:
- R010-T01: Verify the lane runs `make _cpp-test`.
