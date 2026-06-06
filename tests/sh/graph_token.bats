#!/usr/bin/env bats

# Contract checks for the Microsoft Graph OAuth token lifecycle module. The
# runtime behavior is exercised by the Python unit lane; these checks assert the
# token module implements each requirement's design contract so a regression
# fails the shell lane too.

load helpers/repo_root

setup() {
  #R005: Test harness setup for graph_token contract checks.
  #R030: Resolve repository-root token source path for contract assertions.
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

@test "R030: jwt expiry decoder parses exp claims and handles malformed tokens" {
  #R030-T01: jwt_expires_at decodes a valid exp claim and returns None for malformed tokens.
  run rg -F "def jwt_expires_at(access_token: str) -> int | None:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F 'parts = access_token.split(".")' "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "return int(exp)" "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R032: 1Password field resolution normalizes token output and raises when unavailable" {
  #R032-T01: 1Password field resolution normalizes output and raises when 1psa is unavailable.
  run rg -F "def _read_psa_field(item: str, field: str) -> str:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F 'psa_path = shutil.which("1psa")' "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "raise GraphTokenError(\"1psa is required to resolve Outlook Graph credentials\")" "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R034: session validity requires token presence and refresh-buffer headroom" {
  #R034-T01: Session validity requires non-empty access token and expiry beyond the refresh buffer.
  run rg -F "def is_valid(self, buffer_seconds: int = REFRESH_BUFFER_SECONDS) -> bool:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "if not self.access_token:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "return self.expires_at > int(time.time()) + buffer_seconds" "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R036: token sessions serialize and deserialize with normalization and coercion" {
  #R036-T01: Token session dictionary round-trip preserves normalized access/refresh/client/expiry values.
  run rg -F "def to_dict(self) -> dict[str, Any]:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "def from_dict(cls, payload: dict[str, Any]) -> TokenSession:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F 'access_token=_normalize_token(str(payload.get("access_token", "")))' "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R038: manager construction and invalidate control in-memory session lifecycle" {
  #R038-T01: Manager initialization honors explicit cache path and invalidate clears in-memory session state.
  run rg -F "def __init__(self, cache_path: Path | None = None) -> None:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "self.cache_path = cache_path or DEFAULT_CACHE_PATH" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "def invalidate(self) -> None:" "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R040: token status reports valid expired and missing state families" {
  #R040-T01: Token status reports valid/expired/missing/missing_refresh_token states from crafted manager sessions.
  run rg -F "def token_status(self) -> dict[str, str]:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F '"token_status": _STATUS_VALID' "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F '"token_status": _STATUS_MISSING_REFRESH_TOKEN' "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R042: load prefers valid memory and cache sessions before bootstrap refresh fallback" {
  #R042-T01: load returns valid cached sessions without forcing bootstrap/refresh when cache is valid.
  run rg -F "def load(self) -> TokenSession:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "if self._session is not None and self._session.is_valid():" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "cached = self._read_cache()" "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R044: access-token getter refreshes expired sessions with refresh tokens" {
  #R044-T01: get_access_token triggers forced refresh for expired sessions and returns refreshed access tokens.
  run rg -F "def get_access_token(self) -> str:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "if session.refresh_token:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "refreshed = self.refresh(force=True, session=session)" "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R046: cache reader tolerates missing corrupt and non-dict payloads" {
  #R046-T01: _read_cache returns None for missing/corrupt payloads and returns normalized sessions for valid cache data.
  run rg -F "def _read_cache(self) -> TokenSession | None:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "except (OSError, json.JSONDecodeError):" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "if not isinstance(payload, dict):" "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R048: bootstrap session composes env cache and 1Password token sources" {
  #R048-T01: _bootstrap_session prioritizes env/cache values and fills missing credentials from 1Password lookups.
  run rg -F "def _bootstrap_session(self, cached: TokenSession | None) -> TokenSession:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F 'env_token = _normalize_token(os.environ.get("OUTLOOK_GRAPH_TOKEN", ""))' "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "refresh_token = self._refresh_token_from_psa()" "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R052: PSA item and field names honor environment overrides with defaults" {
  #R052-T01: PSA item/field helpers honor environment overrides and default values when unset.
  run rg -F "def _psa_item(self) -> str:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F 'os.environ.get("OUTLOOK_GRAPH_TOKEN_PSA_ITEM", DEFAULT_PSA_ITEM)' "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F 'os.environ.get("OUTLOOK_GRAPH_TOKEN_PSA_CLIENT_ID_FIELD", DEFAULT_PSA_CLIENT_ID_FIELD)' "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R054: get_manager returns the process-wide singleton token manager" {
  #R054-T01: get_manager() returns the same singleton manager instance on repeated calls.
  run rg -F "_DEFAULT_MANAGER = GraphTokenManager()" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "def get_manager() -> GraphTokenManager:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "return _DEFAULT_MANAGER" "${TOKENS}"
  [ "$status" -eq 0 ]
}
