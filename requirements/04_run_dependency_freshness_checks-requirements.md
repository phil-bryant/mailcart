# Run Dependency Freshness Checks Requirements

## Scope

Applies to `04_run_dependency_freshness_checks.sh`.

R001  Statement: Run from repository root regardless of caller working directory.
Design: Resolve script directory from `${BASH_SOURCE[0]}` and `cd` into it before invoking local scripts.
Tests:
- Run from a non-root directory and verify report paths resolve under repo root.

R005  Statement: Select the project interpreter predictably.
Design: Prefer `${VIRTUAL_ENV}/bin/python` when active, else `./<cwd-basename>-venv/bin/python`, else `python3`; fail fast when explicit interpreter path is not executable.
Tests:
- Run with active virtualenv and verify selected interpreter path is printed.
- Set `DEPENDENCY_CHECK_PYTHON` to a bad path and verify script exits non-zero.

R010  Statement: Require a project requirements file before freshness checks.
Design: Fail non-zero with guidance when `requirements.txt` is missing from repository root.
Tests:
- Remove `requirements.txt` and verify clear failure output.

R015  Statement: Produce machine-readable outdated dependency report.
Design: Run `<python> -m pip list --outdated --format=json`, then filter rows to dependencies declared in `requirements.txt` and write JSON output to `${DEPENDENCY_REPORT_DIR:-reports/dependency-freshness}/dependency-freshness.json`.
Tests:
- Run with a stub interpreter and verify JSON artifact path and command arguments.

R020  Statement: Print human-readable freshness summary inline to stdout.
Design: Parse JSON outdated report and print either package transitions or an "up to date" summary directly in script output.
Tests:
- Run with outdated rows and verify stdout includes package/version transitions.
- Run with empty rows and verify stdout includes "up to date" summary text.

R025  Statement: Support optional fail-on-major gate for outdated packages.
Design: When `DEPENDENCY_FAIL_ON_MAJOR=true`, emit explicit major-version diagnostics for outdated dependencies whose major version increased.
Tests:
- Run with major update data and verify non-zero failure.
- Run with only minor/patch updates and verify major-version diagnostic is not emitted.

R030  Statement: Support configurable report output directory.
Design: Honor `DEPENDENCY_REPORT_DIR` when writing JSON artifact and completion output.
Tests:
- Set `DEPENDENCY_REPORT_DIR` and verify JSON artifact is written under that path.

R035  Statement: Fail freshness checks when any outdated package is detected.
Design: Exit non-zero and print failure status when outdated package count is greater than zero for dependencies declared in `requirements.txt`, so stale project dependencies never report a green success completion, while still retaining the JSON report.
Tests:
- Run with outdated rows and verify non-zero exit and failure summary.
- Run with no outdated rows and verify success completion output.
- Run with outdated rows that are not declared in `requirements.txt` and verify success completion output.

R040  Statement: Require fresh ClamAV signatures before dependency freshness reporting.
Design: Resolve ClamAV database path from `CLAMAV_DB_DIR` (default `/opt/homebrew/var/lib/clamav`), detect newest signature file (`*.cvd`, `*.cld`, `*.cud`) mtime, and fail non-zero when signatures are missing or older than `CLAMAV_SIGNATURE_MAX_AGE_HOURS` (default `72`) with explicit refresh guidance (`freshclam --stdout`).
Tests:
- Run with a fresh signature file and verify script prints a fresh-signature confirmation.
- Run with stale signature file mtimes and verify script exits non-zero with refresh guidance.

R045  Statement: Require Semgrep version freshness before dependency freshness reporting.
Design: Require `semgrep` on `PATH`, resolve installed Semgrep version (`semgrep show version`), resolve latest available Semgrep release version, and fail non-zero when installed Semgrep is older than latest available; failure guidance must direct users to rerun `./01_install_prerequisites.sh`.
Tests:
- Run with equal installed/latest versions and verify script prints a Semgrep-fresh confirmation.
- Run with a newer available version and verify script exits non-zero with guidance to rerun `./01_install_prerequisites.sh`.

R050  Statement: Advise the next workflow step after a green dependency freshness run.
Design: When the script reaches successful completion (no blocking red-X failures), print explicit next-step guidance telling users to run `make`.
Tests:
- Run with no outdated package findings and fresh ClamAV/Semgrep inputs and verify stdout includes guidance to run `make`.

## Changelog

- 2026-04-26: Initial requirements for `04_run_dependency_freshness_checks.sh`.
- 2026-05-12: Reswizzled from Teller/PostgreSQL canary flow to mailcart requirements freshness reporting flow.
- 2026-05-12: Updated freshness policy to fail when any outdated dependency is detected.
- 2026-05-12: Simplified output contract to inline summary + JSON artifact only.
- 2026-05-12: Added ClamAV signature freshness and Semgrep binary freshness gates.
- 2026-05-12: Scoped outdated-package failure gate to dependencies declared in `requirements.txt` to avoid false failures from tool-managed transitive packages.
- 2026-05-13: Added success-path next-step guidance requirement to run `make`.
