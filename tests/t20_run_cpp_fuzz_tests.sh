#!/usr/bin/env bash
# Self-contained mailcart lane: build and run the libFuzzer targets for the
# C++ core (query parser, Aho-Corasick matcher, Graph payload mapping). Replaces
# the retired Hypothesis fuzz lane (t10) that targeted the Python API.
#R001: Run with a secure umask and strict shell mode before any work.
umask 007
set -euo pipefail
#R005: Resolve RUNNER_HOME and RUNBOOK_REPO_ROOT, export RUNBOOK_REPO_ROOT, and source the mailcart runbook env.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RUNNER_HOME="$(cd "${SCRIPT_DIR}/../../runner" && pwd -P)"
RUNBOOK_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
export RUNBOOK_REPO_ROOT
# shellcheck source=/dev/null
source "${RUNNER_HOME}/config/runbook/mailcart.env"
cd "$RUNBOOK_REPO_ROOT"
#R060: Build the libFuzzer targets with brew LLVM and run the configured budget.
exec make fuzz FUZZ_RUNS="${FUZZ_RUNS:-200000}"
