# Makefile Requirements

## Scope

Applies to repository task automation in `Makefile` for consolidated local build, test lanes, app launch, and cleanup workflows.

R001  Statement: Expose discoverable consolidated developer entrypoints through a help target.
Design: `make help` lists supported targets and a one-line purpose for each (`lint`, `build`, `test`, `ui-test`, `sast`, `clam`, `crash`, `run-ui`, `run-api`, `clean`).
Tests:
- Run `make help` and verify all documented targets are present with descriptions.

R005  Statement: Run repository tests through the primary test lane.
Design: `make test` compiles and executes the C++ integration test binary, then runs all shell tests under `tests/sh` including `UI.bats`.
Tests:
- Run `make test` and verify C++ compilation succeeds, the binary exits zero, and all shell BATS tests execute (including `tests/sh/UI.bats`).
- Remove one required C++ source path from the compile command and verify `make test` fails non-zero.

R010  Statement: Include bridge compilation validation in the default build lane.
Design: `make build` executes bridge compilation checks for Objective-C and Objective-C++ bridge sources into local object files under `.build/` via `xcrun`.
Tests:
- Run `make build` and verify both bridge object files are produced.
- Introduce a bridge compile error and verify `make build` fails non-zero.

R015  Statement: Include Swift UI typecheck validation in the default build lane.
Design: `make build` runs `xcrun swiftc -typecheck` against app Swift entrypoint/view/view-model sources with macOS SDK, expected target, and Objective-C bridging include configuration.
Tests:
- Run `make build` and verify Swift typecheck completes with success output.
- Break a Swift symbol reference and verify `make build` fails non-zero.

R020  Statement: Reuse an existing built app when present to avoid unnecessary rebuilds.
Design: `make build` checks execute permission on the expected app executable path and runs the rebuild path only when the binary is missing; otherwise it reports reuse.
Tests:
- Run `make build` with an existing executable and verify it reports existing build reuse.
- Remove the executable and verify `make build` dispatches the rebuild flow.

R025  Statement: Perform deterministic full UI rebuild from project spec when rebuild is required.
Design: `make build` rebuild flow ensures UI build directory exists, regenerates Xcode project with `xcodegen`, clears derived data path, then runs `xcodebuild clean build` with project/scheme/configuration variables and local no-signing flag.
Tests:
- Run `make build` when no existing binary is present and verify app bundle is produced at the configured derived-data location.
- Set an invalid scheme and verify `make build` fails non-zero with `xcodebuild` error output.

R030  Statement: Launch the built app bundle through a dedicated run target.
Design: `make run` depends on `build`, resolves `OUTLOOK_GRAPH_TOKEN` via `1psa -f <item> <field>`, optionally warms the shared token cache when `OUTLOOK_GRAPH_CLIENT_ID` is set, exports `MAILCART_REPO_ROOT` and `OUTLOOK_GRAPH_CLIENT_ID`, fails with setup guidance when token retrieval fails, and launches the built app executable with that token in its environment.
Tests:
- Run `make run` and verify `build` executes first when no binary exists.
- Verify `make run` invokes `1psa` for token retrieval and launches the configured app executable with `OUTLOOK_GRAPH_TOKEN` set.

R035  Statement: Expose a dedicated interface verification lane that includes smoke launch verification.
Design: `make ui-test` ensures an app build is available, runs several inline UI regression checks directly in `Makefile` (without invoking BATS), then runs a macOS XCUITest regression suite through `xcodebuild test` with optional selector and runtime overrides (`RUN_XCUITESTS`, `XCUITEST_SELECTOR`, `XCUITEST_PROJECT`, `XCUITEST_SCHEME`, `XCUITEST_DESTINATION`, `XCUITEST_DERIVED_DATA_PATH`), then runs a smoke check that starts the app executable and fails when the process exits early; crash-reporter smoke remains optional behind `RUN_CRASH_REPORTER_SMOKE_TEST=true`.
Tests:
- Run `make ui-test` and verify inline UI regression checks, `xcodebuild test` XCUITest output, and smoke regression output report success.
- Force immediate process exit and verify `make ui-test` fails non-zero with early-exit message.

R045  Statement: Expose a consolidated SAST lane for repository security checks.
Design: `make sast` runs `ShellCheck`, `Semgrep`, `Bandit`, `detect-secrets`, and `gitleaks` through internal `_sast_*` targets, then prints an end-of-lane summary marker: `✅` when all checks are clean and `❌` when any tool reports findings/failures.
Tests:
- Run `make sast` with tool stubs and verify each `_sast_*` lane executes before `✅ SAST checks completed with no findings.`.
- Force one `_sast_*` tool command to fail and verify `make sast` exits non-zero and prints `❌ SAST checks completed with findings or failures.`.

R050  Statement: Run shell-script static analysis through ShellCheck.
Design: `_sast_shell` fails clearly when `shellcheck` is missing; when present, it scans discovered `*.sh` files and emits an explicit no-files message when none are found.
Tests:
- Run `_sast_shell` with `shellcheck` available and verify discovered shell scripts are scanned.
- Remove `shellcheck` from `PATH` and verify `_sast_shell` fails with install guidance.

R055  Statement: Run Semgrep using repository and auto rulesets.
Design: `_sast_semgrep` fails clearly when `semgrep` is missing, otherwise runs `semgrep scan --config auto --config .semgrep.yml --error .`.
Tests:
- Run `_sast_semgrep` with stubbed `semgrep` and verify command arguments include `scan`, both `auto` and `.semgrep.yml` configs, and `--error`.
- Remove `semgrep` from `PATH` and verify `_sast_semgrep` fails non-zero with tool guidance.

R060  Statement: Run clang-tidy exclusively through `make lint` and fail on any reported findings.
Design: `make lint` is the only entrypoint that executes `_sast_clang_tidy`; it fails clearly when `clang-tidy` is missing and runs clang-tidy against `cpp_core/src/*.cpp` and bridge translation units via `xcrun --sdk macosx clang-tidy` with `.clang-tidy` blocking configuration. The lane fails non-zero when blocking diagnostics or suppressed-warning summaries are detected.
Tests:
- Run `make lint` with stubs and verify C++ and both bridge-source clang-tidy invocations occur.
- Remove `clang-tidy` from `PATH` and verify `make lint` fails non-zero with tool guidance.
- Simulate suppressed-warning output and verify `make lint` fails non-zero with red-X completion guidance.

R065  Statement: Run repository secret scanning through gitleaks.
Design: `_sast_secrets` fails clearly when `gitleaks` is missing; when present, it runs `gitleaks detect --source . --config .gitleaks.toml --no-banner --redact --exit-code 1`.
Tests:
- Run `_sast_secrets` with stubbed `gitleaks` and verify expected detect command arguments.
- Remove `gitleaks` from `PATH` and verify `_sast_secrets` fails non-zero with tool guidance.

R070  Statement: Expose a dedicated blocking lint lane for repository language linters.
Design: `make lint` executes `_sast_clang_tidy`, `_lint_swiftlint`, and `_lint_python_equivalent`, and prints `✅` on clean output or `❌` when findings/failures are detected.
Tests:
- Run `make lint` with clean stubs and verify `✅ lint checks completed with no findings.` is emitted.
- Force one lint tool to fail and verify `make lint` exits non-zero with `❌ lint checks completed with findings or failures.`.

R075  Statement: Enforce blocking clang-tidy configuration in lint lane.
Design: `_sast_clang_tidy` uses `.clang-tidy` for lint lane checks, and `make lint` does not use the non-blocking `.clang-tidy.report` configuration.
Tests:
- Verify `make lint` passes `--config-file=.clang-tidy` to direct and `xcrun` clang-tidy invocations.

R125  Statement: Run SwiftLint checks in `make lint`.
Design: `make lint` runs Swift linting via `_lint_swiftlint` (`swiftlint lint --strict --config .swiftlint.yml`) so warning-level and error-level findings are both blocking while generated build/dependency trees (for example `.build`, `DerivedData`, and `SourcePackages`) remain excluded from first-party lint evaluation.
Tests:
- Run `make lint` with stubs and verify `swiftlint lint --strict --config .swiftlint.yml` is invoked.
- Verify `.swiftlint.yml` excludes generated build/dependency directories from lint traversal.
- Remove `swiftlint` from `PATH` and verify `make lint` fails non-zero with tool guidance.
- Simulate SwiftLint warning output and verify `make lint` fails non-zero with red-X completion guidance.

R126  Statement: Run Python-equivalent lint checks in `make lint`.
Design: `make lint` runs Python-equivalent linting via `_lint_python_equivalent` (`ruff check .`) and treats any findings as blocking.
Tests:
- Run `make lint` with stubs and verify `ruff check .` is invoked.
- Remove `ruff` from `PATH` and verify `make lint` fails non-zero with tool guidance.

R115  Statement: Run Bandit as part of the blocking SAST lane.
Design: `_sast_bandit` fails clearly when `bandit` is missing; when present, it scans first-party Python only via `bandit -q -r scripts -x mailcart-venv,.venv,venv,build,dist`.
Tests:
- Run `make sast` with stubbed `bandit` and verify `bandit -q -r scripts -x mailcart-venv,.venv,venv,build,dist` is invoked.
- Remove `bandit` from `PATH` and verify `make sast` fails non-zero with tool guidance.

R120  Statement: Run detect-secrets as part of the blocking SAST lane and fail on findings.
Design: `_sast_detect_secrets` fails clearly when `detect-secrets` is missing; when present, it resolves tracked repository paths from `git ls-files`, scans those paths via `detect-secrets scan`, parses findings, and fails non-zero when any findings exist. If tracked files cannot be resolved, it falls back to `detect-secrets scan --all-files`.
Tests:
- Run `make sast` with stubbed `detect-secrets` reporting no findings and verify lane success.
- Run `make sast` with stubbed `detect-secrets` findings and verify non-zero exit and red-X summary marker.

R135  Statement: Ignore detect-secrets self-referential keyword findings in `Makefile`.
Design: `_sast_detect_secrets` suppresses `Secret Keyword` findings only when they point to `Makefile`; all other findings remain blocking and fail the lane.
Tests:
- Run `make sast` with stubbed `detect-secrets` output containing only `Makefile` keyword findings and verify lane success.
- Run `make sast` with non-allowlisted detect-secrets findings and verify non-zero exit and red-X summary marker.

R130  Statement: Expose ClamAV repository scanning through a dedicated target.
Design: `make clam` checks for `clamscan` and runs `clamscan -r .` from repository root.
Tests:
- Run `make clam` with stubbed `clamscan` and verify `clamscan -r .` is invoked.
- Remove `clamscan` from `PATH` and verify `make clam` fails non-zero with install guidance.

R140  Statement: Surface explicit pass/fail summary markers for ClamAV findings.
Design: `make clam` parses `clamscan` summary output for `Infected files: <count>`, prints a red-X failure marker when infected files are greater than zero, and prints a green-check success marker when infected files are zero.
Tests:
- Run `make clam` with a zero infected-file summary and verify green-check output.
- Run `make clam` with a positive infected-file summary and verify red-X output and non-zero exit.

R080  Statement: Provide a dedicated PLCrashReporter smoke verification lane.
Design: `make crash-reporter-smoke` ensures a UI build exists and runs `./scripts/verify_macos_crash_reporter.sh`; `make ui-test` optionally runs this lane only when `RUN_CRASH_REPORTER_SMOKE_TEST=true` and otherwise proceeds silently.
Tests:
- Run `make crash-reporter-smoke` and verify `_ui-build` and script invocation occur.
- Run `make ui-test RUN_CRASH_REPORTER_SMOKE_TEST=true` and verify crash-reporter-smoke lane executes.
- Run `make ui-test` without the flag and verify no skip message is printed.

R095  Statement: Expose a Matchy API lane through Makefile script entrypoints.
Design: `make run-api` optionally warms the shared token cache when `OUTLOOK_GRAPH_CLIENT_ID` is set, provisions HTTPS cert/key materials via `./05_install_matchy_api_tls.sh`, exports `MAILCART_REPO_ROOT` plus `MAILCART_MATCHY_TLS_*` path variables, and runs `python3 scripts/matchy_mailcart_api.py`.
Tests:
- Run `make run-api` with stubbed `bash` and `python3` and verify `./05_install_matchy_api_tls.sh` executes before `scripts/matchy_mailcart_api.py`.

R100  Statement: Expose stable alias entrypoints for script-backed crash and Matchy lanes.
Design: `make verify-macos-crash-reporter` aliases to `crash-reporter-smoke` and `make crash` aliases to `crash-reporter-smoke`; `make run-api` is the canonical Matchy API entrypoint.
Tests:
- Run `make verify-macos-crash-reporter` and verify crash reporter script lane executes.
- Run `make crash` and verify it delegates to crash reporter smoke lane.
- Run `make run-api` and verify Matchy API script lane executes.

R085  Statement: Print a per-tool header before each blocking SAST tool execution.
Design: `make sast` emits manifold/piston-style boxed per-tool headers before each tool lane (`ShellCheck`, `Semgrep`, `Bandit`, `detect-secrets`, `gitleaks`), including `Security Tool:` title and tool documentation URL, before invoking the corresponding `_sast_*` target.
Tests:
- Run `make sast` with tool stubs and verify output includes all five `Security Tool:` headers and their URL lines in tool-execution order.

R090  Statement: Print a per-tool running notification before each blocking SAST tool execution.
Design: `make sast` emits an explicit `Running ...` notification for each tool lane (`ShellCheck`, `Semgrep`, `Bandit`, `detect-secrets`, `gitleaks`) immediately after the manifold/piston-style boxed header and before invoking the corresponding `_sast_*` target.
Tests:
- Run `make sast` with tool stubs and verify output includes all five per-tool running notification lines in tool-execution order.

R040  Statement: Remove generated local artifacts through a clean target.
Design: `make clean` removes repository `.build` outputs, generated project file path, and local `default.profraw` profiling artifact, then prints cleanup confirmation.
Tests:
- Create `.build` artifacts and generated project file, run `make clean`, and verify removal.
- Run `make clean` repeatedly and verify idempotent success.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for repository `Makefile` target behavior.
- 2026-05-07: Consolidated Make target contract to `build/test/ui-test/run/clean` and inlined legacy UI/bridge flows under `build`.
- 2026-05-07: Restored smoke launch verification under consolidated `make ui-test`.
- 2026-05-07: Added `make sast` with ShellCheck, Semgrep, Bandit, detect-secrets, and gitleaks lanes.
- 2026-05-07: Moved clang-tidy execution exclusively to blocking `make lint`.
- 2026-05-07: Added dedicated PLCrashReporter smoke lane and optional `make ui-test` execution toggle.
- 2026-05-12: Added `make sast` per-tool header and running-notification output requirements.
- 2026-05-12: Folded crash-reporter and Matchy API make entrypoint requirements into Makefile requirements.
- 2026-05-12: Added human-friendly alias targets (`lint`, `crash`, `run-ui`).
- 2026-05-12: Updated `make lint` to run clang-tidy, SwiftLint, and Ruff, and added `make clam` for ClamAV repository scanning.
- 2026-05-12: Added detect-secrets self-referential Makefile keyword false-positive suppression requirement.
- 2026-05-12: Scoped detect-secrets scans to tracked repository files with fallback behavior for non-git contexts.
- 2026-05-13: Split lint sub-requirements into dedicated SwiftLint (`R125`) and Ruff (`R126`) contracts.
- 2026-05-13: Scoped SwiftLint lint lane to `.swiftlint.yml` with generated dependency tree exclusions.
- 2026-05-13: Added `make clam` green-check/red-X summary marker requirement keyed to infected file count.
- 2026-05-13: Removed `make ui-test` skip-message output when crash-reporter smoke toggle is not enabled.
- 2026-05-13: Added UI lane controls for `make ui-test` smoke execution via `RUN_UI_SMOKE_TEST`.
- 2026-05-13: Moved shell BATS ownership to `make test` and switched `make ui-test` to inline non-BATS UI regression checks plus smoke.
- 2026-05-13: Replaced ad-hoc runtime automation lane with Teller-style XCUITest `xcodebuild test` lane in `make ui-test`.
- 2026-05-13: Extended `make clean` requirements to remove `default.profraw` profiling artifacts.
- 2026-05-27: Updated `make run-api` requirements to include TLS bootstrap orchestration and HTTPS environment propagation.
