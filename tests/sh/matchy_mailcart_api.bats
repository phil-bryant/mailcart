#!/usr/bin/env bats

# Contract checks for the Matchy Mailcart API. The runtime behavior (mocked
# Graph requests, refresh/retry, search semantics) is exercised by the Python
# unit lane (tests/t06_run_python_unit_tests.sh ->
# tests/python/test_matchy_mailcart_api.py + test_graph_token.py). These checks
# assert the API/token source implements each requirement's design contract so
# a regression fails the shell lane too. Requirements delegated to the token
# module are asserted against scripts/graph_token.py.

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  API="${REPO_ROOT}/scripts/matchy_mailcart_api.py"
  TOKENS="${REPO_ROOT}/scripts/graph_token.py"
}

@test "R001: API operations resolve a Graph access token before issuing requests" {
  #R001-T01: API operations resolve a Graph access token before issuing requests.
  run rg -F "token = _TOKEN_MANAGER.get_access_token()" "${API}"
  [ "$status" -eq 0 ]
}

@test "R005: configured tokens are normalized by stripping a leading Bearer prefix" {
  #R005-T01: Configured tokens are normalized by stripping a leading Bearer prefix.
  run rg -F "def _normalize_token(token: str) -> str:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F 'if normalized.startswith("Bearer "):' "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "normalized = normalized[7:].strip()" "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R010: Graph headers include Authorization, Accept, and Content-Type" {
  #R010-T01: Graph headers include Authorization, Accept, and Content-Type.
  run rg -F '"Authorization": f"Bearer {token}",' "${API}"
  [ "$status" -eq 0 ]
  run rg -F '"Accept": "application/json",' "${API}"
  [ "$status" -eq 0 ]
  run rg -F '"Content-Type": "application/json",' "${API}"
  [ "$status" -eq 0 ]
}

@test "R015: header construction fails clearly when the token cannot be resolved" {
  #R015-T01: Header construction fails clearly when the token cannot be resolved.
  run rg -F "except GraphTokenError as exc:" "${API}"
  [ "$status" -eq 0 ]
  run rg -F 'detail="Graph access token is unavailable."' "${API}"
  [ "$status" -eq 0 ]
}

@test "R020: scoped search applies AND semantics and rejects unscoped tokens with HTTP 400" {
  #R020-T01: Scoped search applies AND semantics and rejects unsupported/unscoped tokens with HTTP 400.
  run rg -F "def _message_matches_criteria(" "${API}"
  [ "$status" -eq 0 ]
  run rg -F 'detail="Invalid query: unsupported or unscoped token content detected.",' "${API}"
  [ "$status" -eq 0 ]
}

@test "R025: move resolves the destination folder by name, creating it when absent" {
  #R025-T01: Move resolves the destination folder by name, creating it when absent.
  run rg -F "def _get_or_create_folder_id(folder_name: str) -> str:" "${API}"
  [ "$status" -eq 0 ]
  run rg -F 'if str(row.get("displayName", "")).lower() == folder_name.lower():' "${API}"
  [ "$status" -eq 0 ]
  run rg -F '_graph_post("/me/mailFolders", {"displayName": folder_name})' "${API}"
  [ "$status" -eq 0 ]
}

@test "R026: token manager refreshes via the Microsoft token endpoint" {
  #R026-T01: Token manager refreshes via the Microsoft token endpoint.
  run rg -F 'TOKEN_ENDPOINT = "https://login.microsoftonline.com/common/oauth2/v2.0/token"' "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "def refresh(self, force: bool = False, session: TokenSession | None = None) -> TokenSession:" "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R027: Graph requests retry once after a 401 by force-refreshing the token" {
  #R027-T01: Graph requests retry once after a 401 by force-refreshing the token.
  run rg -F "for attempt in range(2):" "${API}"
  [ "$status" -eq 0 ]
  run rg -F "if attempt == 0 and _is_auth_failure(response.status_code, response.text):" "${API}"
  [ "$status" -eq 0 ]
  run rg -F "_TOKEN_MANAGER.invalidate()" "${API}"
  [ "$status" -eq 0 ]
  run rg -F "_TOKEN_MANAGER.refresh(force=True)" "${API}"
  [ "$status" -eq 0 ]
}

@test "R028: refreshed sessions persist to the shared cache with restrictive permissions" {
  #R028-T01: Refreshed sessions persist to the shared cache with restrictive permissions.
  run rg -F 'DEFAULT_CACHE_PATH = Path.home() / ".cache" / "mailcart" / "graph_oauth.json"' "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "def persist(self, session: TokenSession | None = None) -> None:" "${TOKENS}"
  [ "$status" -eq 0 ]
  run rg -F "os.chmod(temp_path, 0o600)" "${TOKENS}"
  [ "$status" -eq 0 ]
}

@test "R029: health endpoint surfaces token status metadata" {
  #R029-T01: Health endpoint surfaces token status metadata.
  run rg -F '@app.get("/health")' "${API}"
  [ "$status" -eq 0 ]
  run rg -F "status.update(_TOKEN_MANAGER.token_status())" "${API}"
  [ "$status" -eq 0 ]
}

@test "R030: Graph auth failures surface a 502 detail instead of empty results" {
  #R030-T01: Graph auth failures surface a 502 detail instead of empty results.
  run rg -F "status_code=502" "${API}"
  [ "$status" -eq 0 ]
  run rg -F "#R030:" "${API}"
  [ "$status" -eq 0 ]
}

@test "R035: single-message endpoint selects body/recipients and rejects blank ids" {
  #R035-T01: Single-message endpoint selects body/recipients/metadata and rejects blank ids with HTTP 400.
  run rg -F '@app.get("/v1/messages/{message_id}")' "${API}"
  [ "$status" -eq 0 ]
  run rg -F "toRecipients" "${API}"
  [ "$status" -eq 0 ]
  run rg -F 'detail="message_id is required"' "${API}"
  [ "$status" -eq 0 ]
}

@test "R040: API starts over HTTPS-only uvicorn with TLS cert/key on 127.0.0.1:8788" {
  #R040-T01: API starts over HTTPS-only uvicorn with TLS cert/key on 127.0.0.1:8788.
  run rg -F "uvicorn.run(app, host=API_HOST, port=API_PORT, ssl_certfile=tls_cert_file, ssl_keyfile=tls_key_file)" "${API}"
  [ "$status" -eq 0 ]
  run rg -F "API_PORT = 8788" "${API}"
  [ "$status" -eq 0 ]
}

@test "R045: startup fails fast when required TLS materials are missing" {
  #R045-T01: Startup fails fast when required TLS materials are missing.
  run rg -F "def _resolve_tls_materials() -> tuple[str, str]:" "${API}"
  [ "$status" -eq 0 ]
  run rg -F "is required and must point to an existing certificate file" "${API}"
  [ "$status" -eq 0 ]
  run rg -F "is required and must point to an existing key file" "${API}"
  [ "$status" -eq 0 ]
}

@test "R050: scoped text filters match via a single-pass Aho-Corasick automaton" {
  #R050-T01: Scoped text filters match via a single-pass Aho-Corasick automaton.
  run rg -F "class AhoCorasick:" "${API}"
  [ "$status" -eq 0 ]
  run rg -F "def _build_failure_links(self) -> None:" "${API}"
  [ "$status" -eq 0 ]
  run rg -F "def _build_criteria_matcher(" "${API}"
  [ "$status" -eq 0 ]
}
