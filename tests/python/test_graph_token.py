#!/usr/bin/env python3
"""Unit tests for Graph OAuth token management."""

from __future__ import annotations

import base64
import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

def _resolve_scripts_dir(module_filename: str) -> Path:
    # Keep imports stable when tests are copied under artifacts/mutation/mutants.
    probe_roots = [Path.cwd().resolve(), *Path(__file__).resolve().parents]
    for root in probe_roots:
        candidate = root / "scripts"
        if (candidate / module_filename).is_file():
            return candidate
    return Path(__file__).resolve().parents[2] / "scripts"


sys.path.insert(0, str(_resolve_scripts_dir("graph_token.py")))

import graph_token  # noqa: E402
from graph_token import (  # noqa: E402
    GraphTokenError,
    GraphTokenManager,
    TokenSession,
    _normalize_token,
    _read_psa_field,
    jwt_expires_at,
)


def _make_jwt(exp: int) -> str:
    #R026: Build a JWT fixture with an exp claim for token-lifecycle tests.
    header = base64.urlsafe_b64encode(json.dumps({"alg": "none", "typ": "JWT"}).encode()).decode().rstrip("=")
    payload = base64.urlsafe_b64encode(json.dumps({"exp": exp}).encode()).decode().rstrip("=")
    return f"{header}.{payload}.signature"


class GraphTokenModuleTests(unittest.TestCase):
    def test_normalize_token_strips_bearer_and_quotes(self) -> None:
        #R005-T01: token normalization strips Bearer prefix and surrounding quotes.
        self.assertEqual(_normalize_token('Bearer "abc"'), "abc")
        self.assertEqual(_normalize_token("  Bearer abc  "), "abc")

    def test_jwt_expires_at_reads_exp_claim(self) -> None:
        #R026: jwt_expires_at reads the exp claim used for refresh decisions.
        exp = int(time.time()) + 3600
        token = _make_jwt(exp)
        self.assertEqual(jwt_expires_at(token), exp)

    def test_jwt_expires_at_handles_malformed_tokens(self) -> None:
        #R030-T01: malformed JWTs return None instead of raising.
        self.assertIsNone(jwt_expires_at("no-dots"))
        self.assertIsNone(jwt_expires_at("a.b.c"))

    def test_token_session_validity_uses_buffer(self) -> None:
        #R026: TokenSession.is_valid applies the pre-expiry refresh buffer.
        session = TokenSession(
            access_token="token",
            refresh_token="refresh",
            expires_at=int(time.time()) + 120,
            client_id="client",
        )
        self.assertFalse(session.is_valid())
        session.expires_at = int(time.time()) + 600
        self.assertTrue(session.is_valid())

    def test_get_access_token_uses_valid_cache(self) -> None:
        #R028: get_access_token returns a valid token from the persisted cache.
        with tempfile.TemporaryDirectory() as tmp_dir:
            cache_path = Path(tmp_dir) / "graph_oauth.json"
            exp = int(time.time()) + 7200
            cache_path.write_text(
                json.dumps(
                    {
                        "access_token": "cached-access",
                        "refresh_token": "cached-refresh",
                        "expires_at": exp,
                        "client_id": "client-id",
                    }
                ),
                encoding="utf-8",
            )
            manager = GraphTokenManager(cache_path=cache_path)
            self.assertEqual(manager.get_access_token(), "cached-access")

    def test_refresh_persists_rotated_tokens(self) -> None:
        #R028: refresh persists rotated tokens to the 0o600 cache.
        with tempfile.TemporaryDirectory() as tmp_dir:
            cache_path = Path(tmp_dir) / "graph_oauth.json"
            manager = GraphTokenManager(cache_path=cache_path)
            session = TokenSession(
                access_token="old-access",
                refresh_token="old-refresh",
                expires_at=int(time.time()) - 10,
                client_id="client-id",
            )
            response = mock.Mock()
            response.status_code = 200
            response.text = ""
            response.json.return_value = {
                "access_token": "new-access",
                "refresh_token": "new-refresh",
                "expires_in": 3600,
            }
            with mock.patch.dict(os.environ, {"OUTLOOK_GRAPH_CLIENT_ID": "client-id"}):
                with mock.patch("graph_token.requests.post", return_value=response):
                    refreshed = manager.refresh(force=True, session=session)
            self.assertEqual(refreshed.access_token, "new-access")
            self.assertEqual(refreshed.refresh_token, "new-refresh")
            persisted = json.loads(cache_path.read_text(encoding="utf-8"))
            self.assertEqual(persisted["access_token"], "new-access")
            self.assertEqual(persisted["refresh_token"], "new-refresh")
            self.assertEqual(oct(cache_path.stat().st_mode & 0o777), oct(0o600))

    def test_refresh_requires_client_id(self) -> None:
        #R026: refresh fails clearly when no client id can be resolved.
        with tempfile.TemporaryDirectory() as tmp_dir:
            manager = GraphTokenManager(cache_path=Path(tmp_dir) / "graph_oauth.json")
            session = TokenSession(
                access_token="",
                refresh_token="refresh",
                expires_at=0,
                client_id="",
            )
            with mock.patch.dict(os.environ, {}, clear=True):
                os.environ.pop("OUTLOOK_GRAPH_CLIENT_ID", None)
                with mock.patch.object(manager, "_client_id", return_value=""):
                    with self.assertRaises(GraphTokenError):
                        manager.refresh(force=True, session=session)

    def test_client_id_reads_from_psa_when_env_missing(self) -> None:
        #R026: _client_id falls back to the PSA store when env is unset.
        with tempfile.TemporaryDirectory() as tmp_dir:
            manager = GraphTokenManager(cache_path=Path(tmp_dir) / "graph_oauth.json")
            with mock.patch.dict(os.environ, {}, clear=True):
                with mock.patch("graph_token._read_psa_field", return_value="client-from-psa"):
                    self.assertEqual(manager._client_id(), "client-from-psa")

    def test_missing_credentials_raise_clear_error(self) -> None:
        #R026: get_access_token raises a clear error when all credentials are absent.
        with tempfile.TemporaryDirectory() as tmp_dir:
            manager = GraphTokenManager(cache_path=Path(tmp_dir) / "missing.json")
            with mock.patch.dict(os.environ, {}, clear=True):
                os.environ.pop("OUTLOOK_GRAPH_TOKEN", None)
                os.environ.pop("OUTLOOK_GRAPH_CLIENT_ID", None)
                with mock.patch.object(manager, "_access_token_from_psa", return_value=""):
                    with mock.patch.object(manager, "_refresh_token_from_psa", return_value=""):
                        with self.assertRaisesRegex(GraphTokenError, "OUTLOOK_GRAPH_TOKEN or refresh_token is required"):
                            manager.get_access_token()

    def test_read_psa_field_requires_1psa_binary(self) -> None:
        #R032-T01: 1psa binary is required for PSA field resolution.
        with mock.patch.object(graph_token.shutil, "which", return_value=None):
            with self.assertRaisesRegex(GraphTokenError, "1psa is required"):
                _read_psa_field("item", "field")

    def test_read_psa_field_surfaces_subprocess_failure_details(self) -> None:
        #R032-T01: subprocess failures include stderr details for diagnostics.
        error = graph_token.subprocess.CalledProcessError(1, ["1psa"], stderr="not found")
        with (
            mock.patch.object(graph_token.shutil, "which", return_value="/usr/bin/1psa"),
            mock.patch.object(graph_token.subprocess, "run", side_effect=error),
        ):
            with self.assertRaisesRegex(GraphTokenError, "not found"):
                _read_psa_field("item", "field")

    def test_token_status_maps_load_errors_and_states(self) -> None:
        #R040-T01: token_status maps error and expiry states correctly.
        with tempfile.TemporaryDirectory() as tmp_dir:
            manager = GraphTokenManager(cache_path=Path(tmp_dir) / "graph_oauth.json")
            with mock.patch.object(manager, "load", side_effect=GraphTokenError("refresh token missing")):
                self.assertEqual(manager.token_status()["token_status"], "missing_refresh_token")
            with mock.patch.object(manager, "load", side_effect=GraphTokenError("missing creds")):
                self.assertEqual(manager.token_status()["token_status"], "missing")
            expired = TokenSession(
                access_token="x",
                refresh_token="r",
                expires_at=int(time.time()) - 10,
                client_id="c",
            )
            with mock.patch.object(manager, "load", return_value=expired):
                self.assertEqual(manager.token_status()["token_status"], "expired")
            missing_refresh = TokenSession(
                access_token="x",
                refresh_token="",
                expires_at=int(time.time()) - 10,
                client_id="c",
            )
            with mock.patch.object(manager, "load", return_value=missing_refresh):
                self.assertEqual(manager.token_status()["token_status"], "missing_refresh_token")

    def test_refresh_short_circuits_when_valid_and_not_forced(self) -> None:
        #R026-T01: non-forced refresh on valid session returns unchanged session.
        with tempfile.TemporaryDirectory() as tmp_dir:
            manager = GraphTokenManager(cache_path=Path(tmp_dir) / "graph_oauth.json")
            valid = TokenSession(
                access_token="cached-access",
                refresh_token="cached-refresh",
                expires_at=int(time.time()) + 7200,
                client_id="client-id",
            )
            with mock.patch.object(graph_token.requests, "post") as post_mock:
                result = manager.refresh(force=False, session=valid)
            self.assertEqual(result.access_token, "cached-access")
            post_mock.assert_not_called()

    def test_refresh_raises_on_http_failure_or_empty_access_token(self) -> None:
        #R026-T01: refresh rejects token endpoint HTTP failures and empty access_token payloads.
        with tempfile.TemporaryDirectory() as tmp_dir:
            manager = GraphTokenManager(cache_path=Path(tmp_dir) / "graph_oauth.json")
            base_session = TokenSession(
                access_token="old",
                refresh_token="refresh",
                expires_at=int(time.time()) - 10,
                client_id="client-id",
            )
            bad_http = mock.Mock(status_code=400, text="invalid_grant")
            with mock.patch.object(graph_token.requests, "post", return_value=bad_http):
                with self.assertRaisesRegex(GraphTokenError, "Graph token refresh failed"):
                    manager.refresh(force=True, session=base_session)
            empty_access = mock.Mock(status_code=200, text="ok")
            empty_access.json.return_value = {"access_token": "  "}
            with mock.patch.object(graph_token.requests, "post", return_value=empty_access):
                with self.assertRaisesRegex(GraphTokenError, "empty access_token"):
                    manager.refresh(force=True, session=base_session)

    def test_read_cache_tolerates_invalid_payload_shapes(self) -> None:
        #R046-T01: cache reader tolerates invalid JSON/non-dict payloads and returns None.
        with tempfile.TemporaryDirectory() as tmp_dir:
            cache_path = Path(tmp_dir) / "graph_oauth.json"
            manager = GraphTokenManager(cache_path=cache_path)
            cache_path.write_text("{not json", encoding="utf-8")
            self.assertIsNone(manager._read_cache())
            cache_path.write_text("[]", encoding="utf-8")
            self.assertIsNone(manager._read_cache())
            cache_path.write_text(json.dumps({"access_token": "", "refresh_token": ""}), encoding="utf-8")
            self.assertIsNone(manager._read_cache())


if __name__ == "__main__":
    unittest.main()
