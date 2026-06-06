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

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from graph_token import (  # noqa: E402
    GraphTokenError,
    GraphTokenManager,
    TokenSession,
    jwt_expires_at,
)


def _make_jwt(exp: int) -> str:
    #R026: Build a JWT fixture with an exp claim for token-lifecycle tests.
    header = base64.urlsafe_b64encode(json.dumps({"alg": "none", "typ": "JWT"}).encode()).decode().rstrip("=")
    payload = base64.urlsafe_b64encode(json.dumps({"exp": exp}).encode()).decode().rstrip("=")
    return f"{header}.{payload}.signature"


class GraphTokenModuleTests(unittest.TestCase):
    def test_jwt_expires_at_reads_exp_claim(self) -> None:
        #R026: jwt_expires_at reads the exp claim used for refresh decisions.
        exp = int(time.time()) + 3600
        token = _make_jwt(exp)
        self.assertEqual(jwt_expires_at(token), exp)

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


if __name__ == "__main__":
    unittest.main()
