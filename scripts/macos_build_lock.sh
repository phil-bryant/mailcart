#!/usr/bin/env bash
# Shared mutual-exclusion lock for mailcart's macOS app build lanes.
#
# The Swift build (t09), macOS UI regression (t12), and crash verification (t13) lanes all drive
# `xcodegen generate` + `xcodebuild` against the SAME Xcode project (macos_app/Mailcart.xcodeproj)
# and DerivedData. Under the parallel test orchestrator they would otherwise race (e.g. xcodegen
# "File exists" on the shared .xcodeproj, or a clean rebuild deleting DerivedData mid-build).
#
# Wrap only the build critical section so the first lane builds the app bundle and the others find
# it fresh and skip the rebuild; test/launch phases remain unserialized.
#
# Usage: source this file, then: with_macos_build_lock <command> [args...]
#R001: Enable a secure umask for any lane that sources the shared build lock.
umask 007

#R005: Serialize the macOS build critical section with a mkdir-based mutual-exclusion lock,
# reclaiming a stale lock whose owner PID is no longer running and timing out after a bound.
with_macos_build_lock() {
  local repo_root="${RUNBOOK_REPO_ROOT:-$PWD}"
  local lock_dir="${repo_root}/.build/.macos-ui-build.lock"
  local pid_file="${lock_dir}/owner.pid"
  local timeout_seconds="${MACOS_UI_BUILD_LOCK_TIMEOUT_SECONDS:-1800}"
  local waited=0
  local owner=""

  mkdir -p "${repo_root}/.build"
  while ! mkdir "$lock_dir" 2>/dev/null; do
    owner="$(cat "$pid_file" 2>/dev/null || true)"
    # Reclaim a lock left behind by a holder that is no longer running.
    if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then
      rm -rf "$lock_dir" 2>/dev/null || true
      continue
    fi
    if [[ "$waited" -ge "$timeout_seconds" ]]; then
      echo "❌ Timed out after ${timeout_seconds}s waiting for macOS UI build lock at ${lock_dir}." >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  echo "$$" > "$pid_file" 2>/dev/null || true
  # shellcheck disable=SC2064
  trap "rm -rf '${lock_dir}' 2>/dev/null || true" EXIT

  #R010: Run the wrapped command under the lock, then release the lock and propagate its exit status.
  local status=0
  "$@" || status=$?

  rm -rf "$lock_dir" 2>/dev/null || true
  trap - EXIT
  return "$status"
}
