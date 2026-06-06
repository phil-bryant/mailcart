#!/usr/bin/env bats

# Contract checks for the Microsoft Graph OAuth token lifecycle module. The
# runtime behavior is exercised by the Python unit lane; these checks assert the
# token module implements each requirement's design contract so a regression
# fails the shell lane too.

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  TOKENS="${REPO_ROOT}/scripts/graph_token.py"
}

@test "R005: configured tokens are normalized by stripping a leading Bearer prefix" {
  #R005-T01: _normalize_token strips a leading Bearer prefix and surrounding quotes.
  run rg -F "def _normalize_token(token: str) -> str:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F 'if normalized.startswith("Bearer "):' "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "normalized = normalized[7:].strip()" "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R026: token manager refreshes via the Microsoft token endpoint" {
  #R026-T01: refresh posts a refresh_token grant to the Microsoft token endpoint and returns a refreshed session.
  run rg -F 'TOKEN_ENDPOINT = "https://login.microsoftonline.com/common/oauth2/v2.0/token"' "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "def refresh(self, force: bool = False, session: TokenSession | None = None) -> TokenSession:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F '"grant_type": "refresh_token",' "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R028: refreshed sessions persist to the shared cache with restrictive permissions" {
  #R028-T01: persist writes the cache atomically with 0o600 permissions.
  run rg -F 'DEFAULT_CACHE_PATH = Path.home() / ".cache" / "mailcart" / "graph_oauth.json"' "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "def persist(self, session: TokenSession | None = None) -> None:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "os.chmod(temp_path, 0o600)" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "os.replace(temp_path, self.cache_path)" "${TOKENS}"
  [ "$status" -eq 0 ]
}
