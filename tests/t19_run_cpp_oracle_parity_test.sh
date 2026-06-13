#!/usr/bin/env bash
# Self-contained mailcart lane: replay the frozen Python/C++ oracle goldens
# (cpp_core/oracle/goldens.json) through the C++ API handlers. These goldens
# were frozen from a verified live Python/C++ parity run (oracle/compare_oracle.py)
# and replace the retired Python unit/contract coverage for the API surface.
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
#R060: Replay the oracle goldens against the C++ API handlers (drift fails the lane).
exec make parity
