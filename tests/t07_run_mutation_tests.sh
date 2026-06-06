#!/usr/bin/env bash
# Thin pointer: selects the mailcart runbook profile and delegates to the runner golden via the shared shim.
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
POINTER_SHIM="${SCRIPT_DIR}/../../runner/src/scripts/pointer_shim.sh"
if [[ ! -f "${POINTER_SHIM}" ]]; then
  echo "Runner shim not found from ${POINTER_SHIM}. Expected sibling repo at ../runner." >&2
  exit 1
fi
# shellcheck source=/dev/null
source "${POINTER_SHIM}"
select_runbook_profile "mailcart"
delegate_golden "tests/t07_run_mutation_tests.sh" "$@"
