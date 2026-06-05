#!/usr/bin/env bash
# Self-contained mailcart test lane (mailcart-owned; wraps Makefile Swift/ObjC++ build + native static analysis).
umask 007
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
RUNNER_HOME="$(cd "${SCRIPT_DIR}/../../runner" && pwd -P)"
RUNBOOK_REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
export RUNBOOK_REPO_ROOT
# shellcheck source=/dev/null
source "${RUNNER_HOME}/config/runbook/mailcart.env"
# shellcheck source=/dev/null
source "${RUNBOOK_REPO_ROOT}/scripts/macos_build_lock.sh"
cd "$RUNBOOK_REPO_ROOT"
# Compile/typecheck the Swift + ObjC++ surface, then run native-only static analysis
# (clang-tidy + SwiftLint) that the shared t03 SAST pointer does not exercise.
# The Xcode build is serialized so parallel macOS lanes don't race on the shared project.
with_macos_build_lock make build
make _sast_clang_tidy
exec make _lint_swiftlint
