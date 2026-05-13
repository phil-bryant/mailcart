# Load Requirements Requirements

## Scope

Applies to `03_load_requirements.sh`.

R001  Statement: Require expected virtual environment directory to exist.
Design: Compute `<cwd-basename>-venv` and fail if missing.
Tests:
- Remove venv directory and verify clear failure with `02_create_venv.sh` guidance.

R005  Statement: Require a currently active virtual environment.
Design: Check `VIRTUAL_ENV`; fail with activation instructions when unset.
Tests:
- Run outside venv and verify non-zero exit with activation hint.

R010  Statement: Fail when active virtualenv Python executable is not available.
Design: Resolve `${VIRTUAL_ENV}/bin/python` and fail clearly when not executable.
Tests:
- Set `VIRTUAL_ENV` to a directory without a `bin/python` executable and verify failure.

R015  Statement: Require active virtual environment to match expected project venv.
Design: Resolve absolute paths and compare expected/current virtual environment roots.
Tests:
- Activate different venv and verify mismatch warning then non-zero exit.

R020  Statement: Expose a stable activation hint for local shell workflow.
Design: Print `activate` guidance when virtual environment is not active.
Tests:
- Run outside venv and verify output includes `activate`.

R025  Statement: Select requirements file by deterministic precedence.
Design: Use `requirements.txt` when present; otherwise use cpu/gpu split flow.
Tests:
- With `requirements.txt` present, verify split-file argument is not required.
- Without `requirements.txt`, verify split-file detection engages.

R030  Statement: Validate cpu/gpu selector when split requirements files are used.
Design: Require exactly one parameter and allow only `cpu` or `gpu`.
Tests:
- Run with missing selector and verify usage failure.
- Run with invalid selector and verify usage failure.

R035  Statement: Install dependencies through active virtualenv python.
Design: Use `${VIRTUAL_ENV}/bin/python -m pip install --upgrade pip` and `${VIRTUAL_ENV}/bin/python -m pip install -r <selected-file>`.
Tests:
- Verify pip upgrade runs before requirements install through the venv python executable.
- Verify selected requirements file is passed to pip install.

## Changelog

- 2026-04-19: Initial reverse-engineered requirements for `03_load_requirements.sh`.
- 2026-05-12: Reswizzled from Teller lock-policy flow to mailcart active-venv install flow.
