---
name: repo-only-traceability-fix
overview: Make traceability truly repo-local for mailcart and close the resulting local coverage gaps for numbered thin wrappers.
todos:
  - id: scope-t04-t05-local-roots
    content: Make t04/t05 wrappers explicitly load profile then override roots to mailcart-local only
    status: completed
  - id: add-numbered-wrapper-requirements
    content: Create local 01/02/04/06 thin-wrapper requirement docs with R001/R005/R010/R015 coverage
    status: completed
  - id: add-numbered-wrapper-bats
    content: Create local 01/02/04/06 companion Bats asserting shim/profile/delegate contracts
    status: completed
  - id: validate-traceability-lanes
    content: Run t04 and t05 lanes and confirm strict traceability/shell contracts are green
    status: completed
isProject: false
---

# Repo-Only Traceability Fix Plan

## Goal
Make `t04`/`t05` evaluate only mailcart-local requirements/tests, then ensure every numbered thin wrapper in this repo has local requirement + Bats coverage.

## Why this is the right shape
- Current pointer flow auto-loads runner profile env at delegate time, which currently injects shared roots.
- The shim supports explicit profile load via `select_runbook_profile`, so mailcart pointers can override roots locally before delegation.
- Once scoped local-only, mailcart must own coverage for numbered wrappers `01/02/04/06` (matching existing local `03/05`).

## Planned changes
- Update traceability lane wrapper to force local roots in [`tests/t04_run_requirements_traceability_tests.sh`](tests/t04_run_requirements_traceability_tests.sh):
  - Call `select_runbook_profile "mailcart"` after sourcing shim.
  - Export:
    - `TRACEABILITY_REQUIREMENTS_ROOTS="${RUNBOOK_REPO_ROOT}/requirements"`
    - `TRACEABILITY_TEST_ROOTS="${RUNBOOK_REPO_ROOT}/tests/sh"`
  - Keep existing `delegate_golden "tests/t04_run_requirements_traceability_tests.sh" "$@"`.

- Update shell lane wrapper to force local Bats roots in [`tests/t05_run_shell_unit_tests.sh`](tests/t05_run_shell_unit_tests.sh):
  - Call `select_runbook_profile "mailcart"`.
  - Export `SHELL_BATS_ROOTS="${RUNBOOK_REPO_ROOT}/tests/sh"` (and keep traceability roots local for consistency if needed).
  - Keep existing delegate call.

- Add missing local numbered wrapper requirements (thin-pointer contract style, matching existing pattern in [`requirements/05_install_matchy_api_tls-requirements.md`](requirements/05_install_matchy_api_tls-requirements.md)):
  - [`requirements/01_install_prerequisites-requirements.md`](requirements/01_install_prerequisites-requirements.md)
  - [`requirements/02_create_venv-requirements.md`](requirements/02_create_venv-requirements.md)
  - [`requirements/04_load_requirements-requirements.md`](requirements/04_load_requirements-requirements.md)
  - [`requirements/06_run_all_tests_parallel-requirements.md`](requirements/06_run_all_tests_parallel-requirements.md)
  - Each doc will carry the standard thin-wrapper IDs (`R001/R005/R010/R015`) scoped to the exact wrapper delegate target.

- Add missing local companion Bats for those numbered wrappers (matching local style from [`tests/sh/05_install_matchy_api_tls.bats`](tests/sh/05_install_matchy_api_tls.bats)):
  - [`tests/sh/01_install_prerequisites.bats`](tests/sh/01_install_prerequisites.bats)
  - [`tests/sh/02_create_venv.bats`](tests/sh/02_create_venv.bats)
  - [`tests/sh/04_load_requirements.bats`](tests/sh/04_load_requirements.bats)
  - [`tests/sh/06_run_all_tests_parallel.bats`](tests/sh/06_run_all_tests_parallel.bats)
  - Assertions will verify shim sourcing, profile selection, and exact `delegate_golden ... "$@"` mapping.

- Optional documentation touch-up (if you want in-scope during implementation):
  - Update stale CI comment in [`.github/workflows/ci.yml`](.github/workflows/ci.yml) about hardcoded `/Users/phil/...` Bats paths.

## Validation after implementation
- Run `./tests/t04_run_requirements_traceability_tests.sh` in venv and confirm strict traceability passes using local roots.
- Run `./tests/t05_run_shell_unit_tests.sh` and confirm local `tests/sh` contracts pass without runner shared pointer Bats.
- Spot-check that no numbered wrapper in repo lacks a local `requirements/NN_*-requirements.md` and `tests/sh/NN_*.bats`.
