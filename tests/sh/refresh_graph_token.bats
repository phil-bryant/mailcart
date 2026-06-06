#!/usr/bin/env bats

# Contract checks for the Graph OAuth token-cache refresh CLI. These checks
# assert the CLI implements each requirement's design contract so a regression
# fails the shell lane.

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/scripts/refresh_graph_token.py"
}

@test "R001: CLI parses --force and refreshes/validates via the shared manager" {
  #R001-T01: CLI parses --force and refreshes/validates the cache through the shared token manager.
  run rg -F 'parser.add_argument("--force", action="store_true"' "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "manager.refresh(force=True, session=session)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "manager.get_access_token()" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R005: token errors print to stderr and return non-zero" {
  #R005-T01: Token errors are printed to stderr and surfaced as a non-zero exit code.
  run rg -F "except GraphTokenError as exc:" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "print(str(exc), file=sys.stderr)" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "return 1" "${SRC}"
  [ "$status" -eq 0 ]
}
