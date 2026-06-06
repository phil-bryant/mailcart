---
name: fix t07 mutation failure
overview: Fix `t07` mutation wrapper resolution so it works when `mailcart` is opened through the `/Users/phil/local/src/mailcart` symlink. Keep scope to `t07` only, and verify with targeted wrapper checks before re-running mutation.
todos:
  - id: edit-t07-wrapper-path
    content: Patch t07 wrapper to use physical path resolution and stable RUNNER_HOME derivation
    status: completed
  - id: add-t07-missing-runner-guard
    content: Add explicit failure message when RUNNER_HOME cannot be resolved
    status: completed
  - id: verify-symlink-invocation
    content: Validate t07 startup from symlinked workspace and confirm wrapper no longer fails early
    status: completed
isProject: false
---

# Fix T07 Mutation Wrapper Path Resolution

## Goal
Make [`/Users/phil/local/src/eggnest/mailcart/tests/t07_run_mutation_tests.sh`](/Users/phil/local/src/eggnest/mailcart/tests/t07_run_mutation_tests.sh) resolve `RUNNER_HOME` correctly when invoked from either the real repo path or the symlinked workspace path.

## Proposed Changes
- Update [`/Users/phil/local/src/eggnest/mailcart/tests/t07_run_mutation_tests.sh`](/Users/phil/local/src/eggnest/mailcart/tests/t07_run_mutation_tests.sh) to resolve the script directory using physical-path semantics (`cd -P`/`pwd -P`) before deriving `RUNNER_HOME`.
- Keep delegation behavior unchanged (`source mailcart profile` + `exec runner t07`) so only path resolution changes.
- Add a clear guardrail error if computed `RUNNER_HOME` is missing, so failures are explicit instead of a generic `cd` error.

## Verification
- Run a fast path-resolution check from symlinked workspace to confirm `RUNNER_HOME` resolves to `/Users/phil/local/src/eggnest/runner`.
- Execute [`/Users/phil/local/src/eggnest/mailcart/tests/t07_run_mutation_tests.sh`](/Users/phil/local/src/eggnest/mailcart/tests/t07_run_mutation_tests.sh) and confirm it reaches runner mutation logic instead of failing at wrapper startup.
- If it still fails after wrapper fix, investigate runner preflight mismatch in [`/Users/phil/local/src/eggnest/runner/tests/t07_run_mutation_tests.sh`](/Users/phil/local/src/eggnest/runner/tests/t07_run_mutation_tests.sh) (`tests/py` vs `tests/python`) as follow-up scope.
