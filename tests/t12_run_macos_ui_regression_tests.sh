#!/usr/bin/env bash
# Self-contained mailcart test lane (mailcart-owned; wraps the Makefile macOS UI regression target).
#R001: Run with a secure umask and strict shell mode before any work.
umask 007
set -euo pipefail
#R005: Resolve RUNNER_HOME and RUNBOOK_REPO_ROOT, export RUNBOOK_REPO_ROOT, and source the mailcart runbook env and macOS build lock.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RUNNER_HOME="$(cd "${SCRIPT_DIR}/../../runner" && pwd -P)"
RUNBOOK_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
export RUNBOOK_REPO_ROOT
# shellcheck source=/dev/null
source "${RUNNER_HOME}/config/runbook/mailcart.env"
# shellcheck source=/dev/null
source "${RUNBOOK_REPO_ROOT}/scripts/macos_build_lock.sh"
cd "$RUNBOOK_REPO_ROOT"
# Serialize the Xcode build so parallel macOS lanes don't race on the shared project; once the
# bundle is built, `make ui-test` re-checks _ui-build (fresh -> no rebuild) and runs the UI suite.
#R010: Build the UI bundle under the macOS build lock, then run the Makefile macOS UI regression target.
with_macos_build_lock make _ui-build
exec make ui-test
