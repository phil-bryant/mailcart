#!/usr/bin/env bash
# Self-contained mailcart test lane (mailcart-owned; wraps the Makefile C++ integration target).
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
#R010: Run the Makefile C++ integration target from the repo root.
exec make _cpp-test
