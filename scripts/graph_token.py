#!/usr/bin/env python3
"""OAuth token lifecycle for Microsoft Graph access."""

from __future__ import annotations

import base64
import json
import os
import shutil
import subprocess  # nosec B404
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import requests


TOKEN_ENDPOINT = "https://login.microsoftonline.com/common/oauth2/v2.0/token"  # nosec B105
_STATUS_MISSING_REFRESH_TOKEN = "missing_refresh_token"  # nosec B105
_STATUS_MISSING = "missing"
_STATUS_VALID = "valid"
_STATUS_EXPIRED = "expired"
DEFAULT_CACHE_PATH = Path.home() / ".cache" / "mailcart" / "graph_oauth.json"
DEFAULT_PSA_ITEM = "OUTLOOK_GRAPH_API"
DEFAULT_PSA_FIELD = "token"
DEFAULT_PSA_REFRESH_FIELD = "refresh_token"
DEFAULT_PSA_CLIENT_ID_FIELD = "application_client_id"
REFRESH_BUFFER_SECONDS = 300


class GraphTokenError(Exception):
    """Raised when a valid Graph access token cannot be obtained."""


#R005: Accept tokens with or without a leading `Bearer ` prefix (also strip stray surrounding quotes).
def _normalize_token(token: str) -> str:
    normalized = token.strip()
    if normalized.startswith("Bearer "):
        normalized = normalized[7:].strip()
    if len(normalized) >= 2 and normalized[0] == '"' and normalized[-1] == '"':
        normalized = normalized[1:-1]
    return normalized


def jwt_expires_at(access_token: str) -> int | None:
    try:
        parts = access_token.split(".")
        if len(parts) < 2:
            return None
        payload = parts[1]
        padding = (-len(payload)) % 4
        if padding:
            payload += "=" * padding
        decoded = base64.urlsafe_b64decode(payload.encode("ascii"))
        data = json.loads(decoded)
        exp = data.get("exp")
        if exp is None:
            return None
        return int(exp)
    except (ValueError, json.JSONDecodeError, TypeError):
        return None


def _read_psa_field(item: str, field: str) -> str:
    psa_path = shutil.which("1psa")
    if not psa_path:
        raise GraphTokenError("1psa is required to resolve Outlook Graph credentials")
    try:
        completed = subprocess.run(
            [psa_path, "-f", item, field],
            check=True,
            capture_output=True,
            text=True,
            shell=False,  # nosec B603
        )
        return _normalize_token(completed.stdout)
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() if exc.stderr else "unknown 1psa error"
        raise GraphTokenError(f"Unable to resolve 1psa field {item}/{field}: {detail}") from exc


@dataclass
class TokenSession:
    access_token: str
    refresh_token: str
    expires_at: int
    client_id: str

    def is_valid(self, buffer_seconds: int = REFRESH_BUFFER_SECONDS) -> bool:
        if not self.access_token:
            return False
        return self.expires_at > int(time.time()) + buffer_seconds

    def to_dict(self) -> dict[str, Any]:
        return {
            "access_token": self.access_token,
            "refresh_token": self.refresh_token,
            "expires_at": self.expires_at,
            "client_id": self.client_id,
        }

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> TokenSession:
        return cls(
            access_token=_normalize_token(str(payload.get("access_token", ""))),
            refresh_token=_normalize_token(str(payload.get("refresh_token", ""))),
            expires_at=int(payload.get("expires_at", 0) or 0),
            client_id=str(payload.get("client_id", "")).strip(),
        )


class GraphTokenManager:
    def __init__(self, cache_path: Path | None = None) -> None:
        self.cache_path = cache_path or DEFAULT_CACHE_PATH
        self._session: TokenSession | None = None

    def invalidate(self) -> None:
        self._session = None

    def token_status(self) -> dict[str, str]:
        try:
            session = self.load()
        except GraphTokenError as exc:
            message = str(exc)
            if "refresh" in message.lower():
                return {"token_status": _STATUS_MISSING_REFRESH_TOKEN, "token_error": message}
            return {"token_status": _STATUS_MISSING, "token_error": message}
        if session.is_valid():
            return {"token_status": _STATUS_VALID, "token_expires_at": str(session.expires_at)}
        if session.refresh_token:
            return {"token_status": _STATUS_EXPIRED, "token_expires_at": str(session.expires_at)}
        return {"token_status": _STATUS_MISSING_REFRESH_TOKEN}

    def load(self) -> TokenSession:
        if self._session is not None and self._session.is_valid():
            return self._session

        cached = self._read_cache()
        if cached is not None and cached.is_valid():
            self._session = cached
            return cached

        bootstrapped = self._bootstrap_session(cached)
        if bootstrapped.is_valid():
            self._session = bootstrapped
            self.persist(bootstrapped)
            return bootstrapped

        if bootstrapped.refresh_token:
            refreshed = self.refresh(force=True, session=bootstrapped)
            self._session = refreshed
            return refreshed

        raise GraphTokenError("OUTLOOK_GRAPH_TOKEN or refresh_token is required")

    def get_access_token(self) -> str:
        session = self.load()
        if session.is_valid():
            return session.access_token
        if session.refresh_token:
            refreshed = self.refresh(force=True, session=session)
            return refreshed.access_token
        raise GraphTokenError("OUTLOOK_GRAPH_TOKEN is required")

    #R026: Refresh expired Graph access tokens using a stored refresh token via the Microsoft token endpoint.
    def refresh(self, force: bool = False, session: TokenSession | None = None) -> TokenSession:
        current = session or self._session or self._read_cache() or self._bootstrap_session(None)
        if not force and current.is_valid():
            self._session = current
            return current
        if not current.refresh_token:
            raise GraphTokenError("refresh_token is required for automatic Graph token refresh")
        client_id = current.client_id or self._client_id()
        if not client_id:
            raise GraphTokenError("OUTLOOK_GRAPH_CLIENT_ID is required for automatic Graph token refresh")

        response = requests.post(
            TOKEN_ENDPOINT,
            data={
                "client_id": client_id,
                "grant_type": "refresh_token",
                "refresh_token": current.refresh_token,
                "scope": "openid profile offline_access https://graph.microsoft.com/Mail.Read https://graph.microsoft.com/Mail.ReadWrite",
            },
            timeout=25,
        )
        if response.status_code >= 400:
            raise GraphTokenError(f"Graph token refresh failed: {response.status_code} {response.text[:200]}")

        payload = response.json()
        access_token = _normalize_token(str(payload.get("access_token", "")))
        if not access_token:
            raise GraphTokenError("Graph token refresh returned an empty access_token")

        refresh_token = _normalize_token(str(payload.get("refresh_token", current.refresh_token)))
        expires_in = int(payload.get("expires_in", 3600) or 3600)
        expires_at = jwt_expires_at(access_token) or int(time.time()) + expires_in

        refreshed = TokenSession(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_at=expires_at,
            client_id=client_id,
        )
        self._session = refreshed
        self.persist(refreshed)
        return refreshed

    #R028: Persist refreshed OAuth session data atomically to the shared local cache file with restrictive permissions.
    def persist(self, session: TokenSession | None = None) -> None:
        payload = (session or self._session)
        if payload is None:
            return
        self.cache_path.parent.mkdir(parents=True, exist_ok=True)
        serialized = json.dumps(payload.to_dict(), indent=2) + "\n"
        fd, temp_path = tempfile.mkstemp(dir=str(self.cache_path.parent), prefix="graph_oauth.", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(serialized)
            os.chmod(temp_path, 0o600)
            os.replace(temp_path, self.cache_path)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)

    def _client_id(self) -> str:
        env_value = os.environ.get("OUTLOOK_GRAPH_CLIENT_ID", "").strip()
        if env_value:
            return env_value
        try:
            return _read_psa_field(self._psa_item(), self._psa_client_id_field())
        except GraphTokenError:
            return ""

    def _read_cache(self) -> TokenSession | None:
        if not self.cache_path.exists():
            return None
        try:
            payload = json.loads(self.cache_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        if not isinstance(payload, dict):
            return None
        session = TokenSession.from_dict(payload)
        if not session.access_token and not session.refresh_token:
            return None
        if not session.client_id:
            session.client_id = self._client_id()
        return session

    def _bootstrap_session(self, cached: TokenSession | None) -> TokenSession:
        env_token = _normalize_token(os.environ.get("OUTLOOK_GRAPH_TOKEN", ""))
        access_token = env_token
        refresh_token = ""  # nosec B105
        client_id = self._client_id()
        expires_at = 0

        if cached is not None:
            if not access_token:
                access_token = cached.access_token
            refresh_token = cached.refresh_token
            if not client_id:
                client_id = cached.client_id
            expires_at = cached.expires_at

        if not refresh_token:
            refresh_token = self._refresh_token_from_psa()
        if not access_token:
            access_token = self._access_token_from_psa()

        if access_token and not expires_at:
            expires_at = jwt_expires_at(access_token) or 0

        return TokenSession(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_at=expires_at,
            client_id=client_id,
        )

    def _psa_item(self) -> str:
        return os.environ.get("OUTLOOK_GRAPH_TOKEN_PSA_ITEM", DEFAULT_PSA_ITEM).strip() or DEFAULT_PSA_ITEM

    def _psa_access_field(self) -> str:
        return os.environ.get("OUTLOOK_GRAPH_TOKEN_PSA_FIELD", DEFAULT_PSA_FIELD).strip() or DEFAULT_PSA_FIELD

    def _psa_refresh_field(self) -> str:
        field = os.environ.get("OUTLOOK_GRAPH_TOKEN_PSA_REFRESH_FIELD", DEFAULT_PSA_REFRESH_FIELD).strip()
        return field or DEFAULT_PSA_REFRESH_FIELD

    def _psa_client_id_field(self) -> str:
        field = os.environ.get("OUTLOOK_GRAPH_TOKEN_PSA_CLIENT_ID_FIELD", DEFAULT_PSA_CLIENT_ID_FIELD).strip()
        return field or DEFAULT_PSA_CLIENT_ID_FIELD

    def _access_token_from_psa(self) -> str:
        try:
            return _read_psa_field(self._psa_item(), self._psa_access_field())
        except GraphTokenError:
            return ""

    def _refresh_token_from_psa(self) -> str:
        try:
            return _read_psa_field(self._psa_item(), self._psa_refresh_field())
        except GraphTokenError:
            return ""


_DEFAULT_MANAGER = GraphTokenManager()


def get_manager() -> GraphTokenManager:
    return _DEFAULT_MANAGER
