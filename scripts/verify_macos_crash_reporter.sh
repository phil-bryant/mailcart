#!/usr/bin/env bash
umask 007

#R001: Run in strict shell mode and fail fast.
set -euo pipefail

#R005: Execute from repository root regardless of caller directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

APP_EXECUTABLE="${APP_EXECUTABLE:-.build/ui/DerivedData/Build/Products/Debug/Mailcart.app/Contents/MacOS/Mailcart}"
CRASH_REPORT_DIR="${CRASH_REPORT_DIR:-${HOME}/Library/Application Support/com.local.outlookmailapp/CrashReports}"
STARTUP_WAIT_SECONDS="${STARTUP_WAIT_SECONDS:-3}"
LAUNCH_LOG="$(mktemp)"
MARKER_FILE="$(mktemp)"
latest_plcrash=""
latest_json=""

#R030: Fail clearly when required local tooling is unavailable.
if ! command -v make >/dev/null 2>&1; then
    echo "❌ make is required for PLCrashReporter verification."
    exit 1
fi

#R025: Ensure a local app build exists before verification runs.
if ! make _ui-build >/dev/null; then
    echo "❌ failed to build app executable for crash reporter verification."
    exit 1
fi

if [[ ! -x "$APP_EXECUTABLE" ]]; then
    echo "❌ app executable not found at ${APP_EXECUTABLE}."
    exit 1
fi

#R600: Resolve newest persisted .plcrash/.json crash artifacts before freshness checks.
refresh_latest_artifacts() {
    shopt -s nullglob
    local plcrash_files=("$CRASH_REPORT_DIR"/*.plcrash)
    local json_files=("$CRASH_REPORT_DIR"/*.json)
    shopt -u nullglob

    latest_plcrash=""
    latest_json=""

    if [[ "${#plcrash_files[@]}" -eq 0 || "${#json_files[@]}" -eq 0 ]]; then
        return
    fi

    latest_plcrash="${plcrash_files[0]}"
    for candidate in "${plcrash_files[@]}"; do
        if [[ "$candidate" -nt "$latest_plcrash" ]]; then
            latest_plcrash="$candidate"
        fi
    done

    latest_json="${json_files[0]}"
    for candidate in "${json_files[@]}"; do
        if [[ "$candidate" -nt "$latest_json" ]]; then
            latest_json="$candidate"
        fi
    done
}

#R605: Require both crash artifacts to exist and be newer than the verification run marker.
artifacts_are_fresh() {
    [[ -n "$latest_plcrash" && -n "$latest_json" && "$latest_plcrash" -nt "$MARKER_FILE" && "$latest_json" -nt "$MARKER_FILE" ]]
}

echo "▶ Triggering intentional crash to seed pending crash report..."
#R010: Require intentional crash run to fail non-zero.
if OUTLOOK_MACOS_FORCE_CRASH_ON_LAUNCH=1 "$APP_EXECUTABLE" >/dev/null 2>&1; then
    echo "❌ expected forced crash run to exit non-zero."
    exit 1
fi

echo "▶ Relaunching app to process pending crash report..."
touch "$MARKER_FILE"
sleep 1
"$APP_EXECUTABLE" >"$LAUNCH_LOG" 2>&1 &
APP_PID=$!
FOUND_SAVE_LOG="false"
FOUND_FRESH_ARTIFACTS="false"

#R015: Confirm relaunch processes pending crash via log signal or fresh artifacts.
for ((second = 1; second <= STARTUP_WAIT_SECONDS; second++)); do
    if [[ -f "$LAUNCH_LOG" ]] && grep -q "CrashReporter: saved pending crash report to" "$LAUNCH_LOG"; then
        FOUND_SAVE_LOG="true"
    fi
    refresh_latest_artifacts
    if artifacts_are_fresh; then
        FOUND_FRESH_ARTIFACTS="true"
        break
    fi
    if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

if kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" >/dev/null 2>&1 || true
else
    wait "$APP_PID" >/dev/null 2>&1 || true
fi
pkill -x "Mailcart" >/dev/null 2>&1 || true

if [[ "$FOUND_SAVE_LOG" != "true" && "$FOUND_FRESH_ARTIFACTS" != "true" ]]; then
    echo "ℹ️  Did not observe persistence log line; validating via artifact timestamps instead."
fi

#R020: Require newly written .plcrash and .json artifacts after marker timestamp.
refresh_latest_artifacts
if [[ -z "$latest_plcrash" || -z "$latest_json" ]]; then
    echo "❌ expected crash artifacts under ${CRASH_REPORT_DIR}."
    exit 1
fi
if ! artifacts_are_fresh; then
    echo "❌ latest crash artifacts are not newer than this verification run."
    exit 1
fi

#R040: Provide environment overrides for executable path and crash report output path.
#R035: Print clear success output with artifact paths.
echo "✅ PLCrashReporter verification passed."
echo "   - crash report: ${latest_plcrash}"
echo "   - metadata: ${latest_json}"
