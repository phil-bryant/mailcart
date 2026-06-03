---
name: Fix Traceability Contract Drift
overview: "Align mailcart traceability artifacts to the compact root-wrapper contract the user selected: keep `05_run_all_tests_parallel.sh` canonical, retire stale root `00` and `04_run_dependency` contracts, and fix failing t04/t07 checks accordingly without changing runner mappings."
status: done
todos:
  - id: align-requirements
    content: Retarget/rename requirement specs to compact wrappers and remove stale 00/04 root-wrapper specs
    status: completed
  - id: align-bats
    content: Retarget/rename wrapper Bats files to compact wrappers and remove stale 00/04 root-wrapper Bats
    status: completed
  - id: update-architecture-doc
    content: Update Architecture.md numbered-script references to match compact contract
    status: completed
  - id: validate-lanes
    content: Run t04, t07, and integrated 05 parallel test runner to confirm fix
    status: completed
isProject: false
---

# Fix Mailcart Traceability Contract Drift

## Goal
Make traceability and shell-wrapper tests reflect the **current mailcart wrapper contract** (compact numbering), so the failing `t04` and `t07` lanes pass reliably.

## Planned Changes
- Update requirements specs to match existing root scripts and retire stale wrapper contracts:
  - Rename/retarget [`/Users/phil/local/src/mailcart/requirements/11_run_all_tests_parallel-requirements.md`](/Users/phil/local/src/mailcart/requirements/11_run_all_tests_parallel-requirements.md) to the `05_run_all_tests_parallel.sh` contract.
  - Rename/retarget [`/Users/phil/local/src/mailcart/requirements/05_install_matchy_api_tls-requirements.md`](/Users/phil/local/src/mailcart/requirements/05_install_matchy_api_tls-requirements.md) to the `04_install_matchy_api_tls.sh` contract.
  - Remove stale requirements files for retired root wrappers:
    - [`/Users/phil/local/src/mailcart/requirements/00_verify_requirements_traceability-requirements.md`](/Users/phil/local/src/mailcart/requirements/00_verify_requirements_traceability-requirements.md)
    - [`/Users/phil/local/src/mailcart/requirements/04_run_dependency_freshness_checks-requirements.md`](/Users/phil/local/src/mailcart/requirements/04_run_dependency_freshness_checks-requirements.md)
- Update shell unit Bats files so they validate existing wrappers only:
  - Retarget/rename [`/Users/phil/local/src/mailcart/tests/sh/11_run_all_tests_parallel.bats`](/Users/phil/local/src/mailcart/tests/sh/11_run_all_tests_parallel.bats) to `05_run_all_tests_parallel.sh` while still asserting delegation to runner’s `11` golden.
  - Retarget/rename [`/Users/phil/local/src/mailcart/tests/sh/05_install_matchy_api_tls.bats`](/Users/phil/local/src/mailcart/tests/sh/05_install_matchy_api_tls.bats) to `04_install_matchy_api_tls.sh` while still asserting delegation to runner’s `05` golden.
  - Remove stale Bats coverage for retired root wrappers:
    - [`/Users/phil/local/src/mailcart/tests/sh/00_verify_requirements_traceability.bats`](/Users/phil/local/src/mailcart/tests/sh/00_verify_requirements_traceability.bats)
    - [`/Users/phil/local/src/mailcart/tests/sh/04_run_dependency_freshness_checks.bats`](/Users/phil/local/src/mailcart/tests/sh/04_run_dependency_freshness_checks.bats)
- Align architecture/docs wording with the compact script contract:
  - Update numbered-script references in [`/Users/phil/local/src/mailcart/Architecture.md`](/Users/phil/local/src/mailcart/Architecture.md) to remove stale `00`/`11` assumptions and reflect current wrappers.
- Do a final stale-reference sweep for removed names (`00_verify_requirements_traceability.sh`, `04_run_dependency_freshness_checks.sh`, `11_run_all_tests_parallel.sh` as root files) and adjust any remaining mailcart-local references.

## Validation Plan
- Run [`/Users/phil/local/src/mailcart/tests/t04_run_requirements_traceability_tests.sh`](/Users/phil/local/src/mailcart/tests/t04_run_requirements_traceability_tests.sh) and confirm no missing-source failures.
- Run [`/Users/phil/local/src/mailcart/tests/t07_run_shell_unit_tests.sh`](/Users/phil/local/src/mailcart/tests/t07_run_shell_unit_tests.sh) and confirm Bats passes for updated wrapper tests.
- Run [`/Users/phil/local/src/mailcart/05_run_all_tests_parallel.sh`](/Users/phil/local/src/mailcart/05_run_all_tests_parallel.sh) to verify the previously failing lanes are green in the integrated run.

## Scope Guardrails
- Per your direction, do **not** modify [`/Users/phil/local/src/eggnest/runner/src/scripts/generate_runbook_pointers.sh`](/Users/phil/local/src/eggnest/runner/src/scripts/generate_runbook_pointers.sh) in this pass.
- Leave `STRICT_TRACEABILITY_*` behavior unchanged for now; this fix targets current failures only.