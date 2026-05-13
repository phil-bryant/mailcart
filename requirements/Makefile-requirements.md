# Makefile Requirements

## Scope

Applies to repository task automation in `Makefile` for consolidated local build, test lanes, app launch, and cleanup workflows.

R001  Statement: Expose discoverable consolidated developer entrypoints through a help target.
Design: `make help` lists supported targets and a one-line purpose for each (`build`, `test`, `ui-test`, `run`, `crash-reporter-smoke`, `sast`, `sast-report`, `clean`).
Tests:
- Run `make help` and verify all documented targets are present with descriptions.

R005  Statement: Run non-UI repository tests through the primary test lane.
Design: `make test` compiles and executes the C++ integration test binary, then runs non-UI shell tests under `tests/sh` (excluding `UI.bats`).
Tests:
- Run `make test` and verify C++ compilation succeeds, the binary exits zero, and non-UI BATS tests execute.
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
Design: `make run` depends on `build`, resolves `OUTLOOK_GRAPH_TOKEN` via `1psa -f <item> <field>`, fails with setup guidance when token retrieval fails, and launches the built app executable with that token in its environment.
Tests:
- Run `make run` and verify `build` executes first when no binary exists.
- Verify `make run` invokes `1psa` for token retrieval and launches the configured app executable with `OUTLOOK_GRAPH_TOKEN` set.

R035  Statement: Expose a dedicated interface verification lane that includes smoke launch verification.
Design: `make ui-test` ensures an app build is available, runs UI test coverage from `tests/sh/UI.bats`, then runs a smoke check that starts the app executable, waits three seconds, and fails when the process exits early.
Tests:
- Run `make ui-test` and verify `tests/sh/UI.bats` executes through BATS and smoke output reports success.
- Force immediate process exit and verify `make ui-test` fails non-zero with early-exit message.

R045  Statement: Expose a consolidated SAST lane for repository security checks.
Design: `make sast` runs shell, semantic, language-static-analysis, and secret-scanning checks through internal `_sast_*` targets and reports completion only when all pass.
Tests:
- Run `make sast` with tool stubs and verify each `_sast_*` lane executes before success output.
- Force one `_sast_*` tool command to fail and verify `make sast` exits non-zero.

R050  Statement: Run shell-script static analysis through ShellCheck.
Design: `_sast_shell` fails clearly when `shellcheck` is missing; when present, it scans discovered `*.sh` files and emits an explicit no-files message when none are found.
Tests:
- Run `_sast_shell` with `shellcheck` available and verify discovered shell scripts are scanned.
- Remove `shellcheck` from `PATH` and verify `_sast_shell` fails with install guidance.

R055  Statement: Run Semgrep using repository and auto rulesets.
Design: `_sast_semgrep` fails clearly when `semgrep` is missing, otherwise runs `semgrep --config auto --config .semgrep.yml --error --quiet .`.
Tests:
- Run `_sast_semgrep` with stubbed `semgrep` and verify command arguments include both `auto` and `.semgrep.yml` configs.
- Remove `semgrep` from `PATH` and verify `_sast_semgrep` fails non-zero with tool guidance.

R060  Statement: Run clang-tidy static analysis across C++ and bridge Objective-C(++) sources.
Design: `_sast_clang_tidy` fails clearly when `clang-tidy` is missing; when available, it runs clang-tidy against `cpp_core/src/*.cpp` and bridge translation units via `xcrun --sdk macosx clang-tidy` with required include/language flags and blocking configuration from `.clang-tidy`, then fails non-zero when blocking `-warnings-as-errors` findings are detected in the emitted diagnostics.
Tests:
- Run `_sast_clang_tidy` with stubs and verify C++ and both bridge-source invocations occur.
- Remove `clang-tidy` from `PATH` and verify `_sast_clang_tidy` fails non-zero with tool guidance.
- Simulate blocking clang-tidy findings and verify `_sast_clang_tidy` fails non-zero with blocking-findings guidance.

R065  Statement: Run repository secret scanning through gitleaks.
Design: `_sast_secrets` fails clearly when `gitleaks` is missing; when present, it runs `gitleaks detect --source . --config .gitleaks.toml --no-banner --redact --exit-code 1`.
Tests:
- Run `_sast_secrets` with stubbed `gitleaks` and verify expected detect command arguments.
- Remove `gitleaks` from `PATH` and verify `_sast_secrets` fails non-zero with tool guidance.

R070  Statement: Expose a non-blocking extended SAST reporting lane.
Design: `make sast-report` runs `_sast_clang_tidy_report` and returns success after reporting extended findings.
Tests:
- Run `make sast-report` and verify completion output is emitted.
- Force report lane clang-tidy invocation failures and verify the target remains non-blocking.

R075  Statement: Separate blocking and report-only clang-tidy configurations.
Design: `_sast_clang_tidy` uses `.clang-tidy` for high-signal blocking checks; `_sast_clang_tidy_report` uses `.clang-tidy.report` for broader non-blocking readability/performance/portability diagnostics.
Tests:
- Verify `_sast_clang_tidy` passes `--config-file=.clang-tidy` to direct and `xcrun` invocations.
- Verify `_sast_clang_tidy_report` passes `--config-file=.clang-tidy.report` to direct and `xcrun` invocations.

R080  Statement: Provide a dedicated PLCrashReporter smoke verification lane.
Design: `make crash-reporter-smoke` ensures a UI build exists and runs `./scripts/verify_macos_crash_reporter.sh`; `make ui-test` optionally runs this lane when `RUN_CRASH_REPORTER_SMOKE_TEST=true` and otherwise prints a skip message.
Tests:
- Run `make crash-reporter-smoke` and verify `_ui-build` and script invocation occur.
- Run `make ui-test RUN_CRASH_REPORTER_SMOKE_TEST=true` and verify crash-reporter-smoke lane executes.
- Run `make ui-test` without the flag and verify skip message is printed.

R095  Statement: Expose a Matchy API lane through Makefile script entrypoints.
Design: `make run-matchy-api` runs `python3 scripts/matchy_mailcart_api.py`, and `make matchy-mailcart-api` aliases to that same lane.
Tests:
- Run `make run-matchy-api` with stubbed `python3` and verify `scripts/matchy_mailcart_api.py` is invoked.
- Run `make matchy-mailcart-api` and verify it delegates to `run-matchy-api`.

R100  Statement: Expose stable alias entrypoints for script-backed crash and Matchy lanes.
Design: `make verify-macos-crash-reporter` aliases to `crash-reporter-smoke`, and `make matchy-mailcart-api` aliases to `run-matchy-api`.
Tests:
- Run `make verify-macos-crash-reporter` and verify crash reporter script lane executes.
- Run `make matchy-mailcart-api` and verify Matchy API script lane executes.

R085  Statement: Print a per-tool header before each blocking SAST tool execution.
Design: `make sast` emits a distinct header line for each tool lane (`ShellCheck`, `Semgrep`, `clang-tidy`, `gitleaks`) before invoking the corresponding `_sast_*` target.
Tests:
- Run `make sast` with tool stubs and verify output includes all four per-tool header lines in tool-execution order.

R090  Statement: Print a per-tool running notification before each blocking SAST tool execution.
Design: `make sast` emits an explicit `Running ...` notification for each tool lane (`ShellCheck`, `Semgrep`, `clang-tidy`, `gitleaks`) immediately before invoking the corresponding `_sast_*` target.
Tests:
- Run `make sast` with tool stubs and verify output includes all four per-tool running notification lines in tool-execution order.

R040  Statement: Remove generated local artifacts through a clean target.
Design: `make clean` removes repository `.build` outputs and generated project file path, then prints cleanup confirmation.
Tests:
- Create `.build` artifacts and generated project file, run `make clean`, and verify removal.
- Run `make clean` repeatedly and verify idempotent success.

## Changelog

- 2026-05-06: Initial reverse-engineered requirements for repository `Makefile` target behavior.
- 2026-05-07: Consolidated Make target contract to `build/test/ui-test/run/clean` and inlined legacy UI/bridge flows under `build`.
- 2026-05-07: Restored smoke launch verification under consolidated `make ui-test`.
- 2026-05-07: Added `make sast` with ShellCheck, Semgrep, clang-tidy, and gitleaks lanes.
- 2026-05-07: Split clang-tidy into blocking `make sast` and non-blocking `make sast-report` lanes.
- 2026-05-07: Added dedicated PLCrashReporter smoke lane and optional `make ui-test` execution toggle.
- 2026-05-12: Added `make sast` per-tool header and running-notification output requirements.
- 2026-05-12: Folded crash-reporter and Matchy API make entrypoint requirements into Makefile requirements.
