# Portable repo-root derivation for mailcart Bats tests.
# Resolves the repository root from the running test file's own location
# (tests/sh/<file>.bats sits two directories below the repo root) so tests run
# from any checkout without a hardcoded /Users/... absolute path.
mailcart_repo_root() {
  cd "${BATS_TEST_DIRNAME}/../.." && pwd
}
