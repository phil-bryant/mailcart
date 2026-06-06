#!/usr/bin/env bash
# Self-contained mailcart test lane (mailcart-owned; wraps the Makefile Swift unit-test target).
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
# Serialize Swift XCTest execution so parallel macOS lanes do not race on shared
# Xcode/DerivedData state while this lane runs the dedicated Swift unit suite.
#R010: Run the Makefile Swift unit-test target under the macOS build lock.
with_macos_build_lock make _swift-unit-tests
