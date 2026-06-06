#!/usr/bin/env bats

# Contract checks for the shared macOS build serialization helper. These checks
# assert the helper implements each requirement's design contract so a
# regression fails the shell lane.

load helpers/repo_root

setup() {
  #R001: Test harness setup for macos_build_lock contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/scripts/macos_build_lock.sh"
}

@test "R001: helper applies a secure umask" {
  #R001-T01: The helper sets a secure umask 007.
  run rg -F "umask 007" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R005: build critical section is serialized with a mkdir lock, stale reclaim, and timeout" {
  #R005-T01: The lock is acquired via mkdir, reclaims stale owners, and enforces a timeout.
  run rg -F 'while ! mkdir "$lock_dir" 2>/dev/null; do' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'if [[ -n "$owner" ]] && ! kill -0 "$owner" 2>/dev/null; then' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'if [[ "$waited" -ge "$timeout_seconds" ]]; then' "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R010: wrapped command runs under the lock and its exit status is propagated" {
  #R010-T01: The wrapped command runs under the lock and its exit status is propagated after release.
  run rg -F '"$@" || status=$?' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'rm -rf "$lock_dir" 2>/dev/null || true' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F 'return "$status"' "${SRC}"
  [ "$status" -eq 0 ]
}
