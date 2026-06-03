#!/usr/bin/env bash
# Thin runbook pointer: sets RUNBOOK_REPO_ROOT + mailcart profile, execs the runner golden.
#R001: Wrapper enforces secure shell defaults before delegation.
umask 007
set -euo pipefail
#R005: Wrapper resolves script and runner locations relative to this file.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER_HOME="$(cd "${SCRIPT_DIR}/../runner" && pwd)"
#R010: Wrapper exports runbook root and loads the mailcart runbook profile.
export RUNBOOK_REPO_ROOT="$SCRIPT_DIR"
# shellcheck source=/dev/null
source "${RUNNER_HOME}/config/runbook/mailcart.env"
#R015: Wrapper delegates to the runner golden venv entrypoint.
exec "${RUNNER_HOME}/02_create_venv.sh" "$@"
