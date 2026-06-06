#!/usr/bin/env bash
# Thin pointer: selects the mailcart runbook profile and delegates to the runner golden via the shared shim.
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
POINTER_SHIM="${SCRIPT_DIR}/../../runner/src/scripts/pointer_shim.sh"
if [[ ! -f "${POINTER_SHIM}" ]]; then
  echo "Runner shim not found from ${POINTER_SHIM}. Expected sibling repo at ../runner." >&2
  exit 1
fi
#R001: Secure umask and strict shell mode are centralized in pointer_shim.sh.
#R005: RUNNER_HOME and RUNBOOK_REPO_ROOT resolution are centralized in pointer_shim.sh.
# shellcheck source=/dev/null
source "${POINTER_SHIM}"
#R010: Pointer selects its runbook profile via select_runbook_profile; the shim sources the matching runner/config/runbook profile and exports RUNBOOK_REPO_ROOT.
select_runbook_profile "mailcart"
#R015: Delegate to the mapped runner golden with argument passthrough.
delegate_golden "tests/t07_run_mutation_tests.sh" "$@"
