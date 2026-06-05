#!/usr/bin/env bash
# Self-contained mailcart test lane (mailcart-owned; wraps the Makefile macOS UI regression target).
umask 007
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RUNNER_HOME="$(cd "${SCRIPT_DIR}/../../runner" && pwd -P)"
RUNBOOK_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
export RUNBOOK_REPO_ROOT
# shellcheck source=/dev/null
source "${RUNNER_HOME}/config/runbook/mailcart.env"
cd "$RUNBOOK_REPO_ROOT"
exec make ui-test
