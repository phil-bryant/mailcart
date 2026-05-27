#!/usr/bin/env python3
"""Minimal Mailcart API for Matchy search/move operations."""

# Traceability anchors for requirements whose implementation is delegated to scripts/graph_token.py:
# #R005: Bearer-prefix normalization (graph_token._normalize_token)
# #R026: Graph refresh-token exchange (graph_token.GraphTokenManager.refresh)
# #R028: OAuth session cache persistence (graph_token.GraphTokenManager.persist)

from __future__ import annotations

import os
import socket
import sys
from urllib.parse import quote, unquote
from pathlib import Path
from typing import Any

import requests
import uvicorn
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

sys.path.insert(0, str(Path(__file__).resolve().parent))

from graph_token import GraphTokenError, get_manager  # noqa: E402


GRAPH_BASE = "https://graph.microsoft.com/v1.0"
_TOKEN_MANAGER = get_manager()
API_HOST = "127.0.0.1"
API_PORT = 8788
API_HTTPS_BASE = f"https://{API_HOST}:{API_PORT}"
TLS_DIR_DEFAULT = Path.home() / ".mailcart"
TLS_CERT_ENV = "MAILCART_MATCHY_TLS_CERT_FILE"
TLS_KEY_ENV = "MAILCART_MATCHY_TLS_KEY_FILE"
TLS_CERT_DEFAULT = TLS_DIR_DEFAULT / "matchy-localhost-cert.pem"
TLS_KEY_DEFAULT = TLS_DIR_DEFAULT / "matchy-localhost-key.pem"


def _is_auth_failure(status_code: int, body: str) -> bool:
    if status_code == 401:
        return True
    lowered = body.lower()
    return (
        "invalidauthenticationtoken" in lowered
        or "authorization_identity_not_found" in lowered
        or "graph auth failed" in lowered
        or ": 401 " in lowered
    )


#R001: Require an Outlook Graph token for API-backed operations.
#R010: Build Graph request headers with auth and JSON content negotiation.
#R015: Fail request processing with explicit error when token is missing.
def _headers() -> dict[str, str]:
    try:
        token = _TOKEN_MANAGER.get_access_token()
    except GraphTokenError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }


#R027: Retry the Graph request once after a 401 by invalidating + force-refreshing the cached token before re-issuing.
def _graph_request(method: str, path: str, *, params: dict[str, Any] | None = None, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    url = f"{GRAPH_BASE}{path}"
    for attempt in range(2):
        headers = _headers()
        response = requests.request(method, url, params=params or {}, json=payload, headers=headers, timeout=25)
        if response.status_code < 400:
            if not response.text:
                return {}
            return response.json()
        if attempt == 0 and _is_auth_failure(response.status_code, response.text):
            _TOKEN_MANAGER.invalidate()
            try:
                _TOKEN_MANAGER.refresh(force=True)
            except GraphTokenError as exc:
                raise HTTPException(status_code=502, detail=f"Graph auth failed and token refresh failed: {exc}") from exc
            continue
        detail = f"Graph {method} failed: {response.status_code} {response.text[:200]}"
        if _is_auth_failure(response.status_code, response.text):
            raise HTTPException(status_code=502, detail=f"Graph auth failed: {response.status_code} {response.text[:200]}")
        # Pass through Graph's 404 (and ItemNotFound errors) as a real 404 so downstream
        # callers can render "no longer in inbox" instead of a generic 502. Graph also
        # occasionally serves ResourceNotFound as 400 with that text in the body.
        if response.status_code == 404 or "itemnotfound" in response.text.lower() or "resourcenotfound" in response.text.lower():
            raise HTTPException(status_code=404, detail=f"Graph reports message not found: {response.text[:200]}")
        raise HTTPException(status_code=502, detail=detail)
    raise HTTPException(status_code=502, detail="Graph request failed after token refresh retry")


def _graph_get(path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    return _graph_request("GET", path, params=params)


def _graph_post(path: str, payload: dict[str, Any]) -> dict[str, Any]:
    return _graph_request("POST", path, payload=payload)


def _graph_message_path(message_id: str) -> str:
    # Normalize possibly pre-encoded IDs, then quote as a single path segment.
    normalized_id = unquote(message_id)
    return f"/me/messages/{quote(normalized_id, safe='')}"


#R025: Resolve destination mail folder by name, creating it when absent.
def _get_or_create_folder_id(folder_name: str) -> str:
    folders = _graph_get("/me/mailFolders", params={"$select": "id,displayName", "$top": "200"})
    for row in folders.get("value", []):
        if str(row.get("displayName", "")).lower() == folder_name.lower():
            return str(row.get("id", ""))
    created = _graph_post("/me/mailFolders", {"displayName": folder_name})
    folder_id = str(created.get("id", ""))
    if not folder_id:
        raise HTTPException(status_code=502, detail=f"Unable to create folder: {folder_name}")
    return folder_id


class MoveRequest(BaseModel):
    folder_name: str = Field(default="matchy", min_length=1, max_length=120)


app = FastAPI(title="mailcart-matchy-api")


@app.get("/health")
#R029: Expose Graph token health metadata (`token_status`, `token_expires_at`) from the API health endpoint.
def health() -> dict[str, str]:
    status = {"status": "ok"}
    status.update(_TOKEN_MANAGER.token_status())
    return status


@app.get("/v1/messages/search")
#R020: Return recent messages and apply optional text filtering with caller limit.
def search_messages(query: str = Query(default="", max_length=160), limit: int = Query(default=50, ge=1, le=100)) -> dict[str, Any]:
    payload: dict[str, Any] = {"value": []}
    normalized_query = query.strip()
    search_error: HTTPException | None = None
    if normalized_query:
        try:
            payload = _graph_get(
                "/me/messages",
                params={"$select": "id,subject,bodyPreview,receivedDateTime,from", "$search": f"\"{normalized_query}\"", "$top": str(limit)},
            )
        except HTTPException as exc:
            if exc.status_code == 502 and isinstance(exc.detail, str) and _is_auth_failure(401, exc.detail):
                raise
            search_error = exc
            payload = {"value": []}
    #R030: Surface Graph auth failures explicitly instead of swallowing them as empty `{"messages": []}` results.
    if not payload.get("value"):
        try:
            payload = _graph_get(
                "/me/messages",
                params={
                    "$select": "id,subject,bodyPreview,receivedDateTime,from",
                    "$orderby": "receivedDateTime DESC",
                    "$top": str(max(limit * 8, 200) if normalized_query else max(limit, 50)),
                },
            )
        except HTTPException as exc:
            if exc.status_code == 502 and isinstance(exc.detail, str) and _is_auth_failure(401, exc.detail):
                raise
            if search_error is not None:
                raise search_error
            raise
    normalized_query_lc = normalized_query.lower()
    messages = []
    for row in payload.get("value", []):
        subject = str(row.get("subject", ""))
        preview = str(row.get("bodyPreview", ""))
        sender = str((((row.get("from") or {}).get("emailAddress") or {}).get("address")) or "")
        if normalized_query_lc:
            blob = f"{subject} {preview} {sender}".lower()
            if normalized_query_lc not in blob:
                continue
        messages.append(
            {
                "message_id": str(row.get("id", "")),
                "subject": subject,
                "preview": preview,
                "received_at": str(row.get("receivedDateTime", "")),
                "sender": sender,
                "body_text": preview,
            }
        )
        if len(messages) >= limit:
            break
    return {"messages": messages}


@app.get("/v1/messages/{message_id}")
#R035: Return a single message with subject, sender, recipients, body, and preview metadata for downstream UIs.
def get_message(message_id: str) -> dict[str, Any]:
    if not message_id.strip():
        raise HTTPException(status_code=400, detail="message_id is required")
    payload = _graph_get(
        _graph_message_path(message_id),
        params={"$select": "id,subject,bodyPreview,body,from,toRecipients,receivedDateTime"},
    )
    sender = str((((payload.get("from") or {}).get("emailAddress") or {}).get("address")) or "")
    recipients_raw = payload.get("toRecipients") or []
    recipients = [
        str(((row or {}).get("emailAddress") or {}).get("address") or "")
        for row in recipients_raw
        if isinstance(row, dict)
    ]
    recipients = [value for value in recipients if value]
    body_obj = payload.get("body") or {}
    body_content_type = str(body_obj.get("contentType", "")).lower()
    body_content = str(body_obj.get("content", ""))
    html_body = body_content if body_content_type == "html" else ""
    text_body = body_content if body_content_type == "text" else ""
    return {
        "message_id": str(payload.get("id", message_id)),
        "subject": str(payload.get("subject", "")),
        "preview": str(payload.get("bodyPreview", "")),
        "received_at": str(payload.get("receivedDateTime", "")),
        "sender": sender,
        "recipients": ",".join(recipients),
        "html_body": html_body,
        "text_body": text_body,
        "body_text": text_body or html_body,
    }


@app.post("/v1/messages/{message_id}/move")
#R025: Move selected message into requested destination folder.
def move_message(message_id: str, request: MoveRequest) -> dict[str, Any]:
    folder_id = _get_or_create_folder_id(request.folder_name)
    response = _graph_post(f"{_graph_message_path(message_id)}/move", {"destinationId": folder_id})
    return {"moved": True, "folder_id": folder_id, "result_id": response.get("id", "")}


#R040: Resolve TLS cert/key paths and require HTTPS startup materials.
#R045: Fail fast with explicit guidance when TLS cert/key files are missing.
def _resolve_tls_materials() -> tuple[str, str]:
    cert_file = Path(os.environ.get(TLS_CERT_ENV, str(TLS_CERT_DEFAULT))).expanduser()
    key_file = Path(os.environ.get(TLS_KEY_ENV, str(TLS_KEY_DEFAULT))).expanduser()
    if not cert_file.is_file():
        raise SystemExit(
            f"{TLS_CERT_ENV} is required and must point to an existing certificate file: {cert_file}. "
            "Run ./05_install_matchy_api_tls.sh to install local TLS materials."
        )
    if not key_file.is_file():
        raise SystemExit(
            f"{TLS_KEY_ENV} is required and must point to an existing key file: {key_file}. "
            "Run ./05_install_matchy_api_tls.sh to install local TLS materials."
        )
    return str(cert_file), str(key_file)


def _is_port_in_use(host: str, port: int) -> bool:
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(0.25)
    in_use = sock.connect_ex((host, port)) == 0
    sock.close()
    return in_use


def _existing_server_is_healthy(cert_file: str) -> bool:
    try:
        probe = requests.get(f"{API_HTTPS_BASE}/health", timeout=1.5, verify=cert_file)
    except Exception:
        return False
    return probe.status_code == 200 and '"status":"ok"' in probe.text


def _existing_http_server_is_healthy() -> bool:
    try:
        probe = requests.get(f"http://{API_HOST}:{API_PORT}/health", timeout=1.5)
    except Exception:
        return False
    return probe.status_code == 200 and '"status":"ok"' in probe.text


#R040: Start the Matchy Mailcart API with HTTPS-only uvicorn TLS settings.
def run_server() -> None:
    if os.environ.get("OUTLOOK_GRAPH_CLIENT_ID", "").strip():
        try:
            _TOKEN_MANAGER.get_access_token()
        except GraphTokenError as exc:
            print(str(exc), file=sys.stderr)
            raise SystemExit(1) from exc
    tls_cert_file, tls_key_file = _resolve_tls_materials()
    if _is_port_in_use(API_HOST, API_PORT):
        if _existing_server_is_healthy(tls_cert_file):
            print(f"Mailcart API already running at {API_HTTPS_BASE}; reusing existing process.")
            raise SystemExit(0)
        if _existing_http_server_is_healthy():
            raise SystemExit(
                f"Port {API_PORT} is occupied by a legacy HTTP Mailcart API process. "
                "Stop the existing process and rerun make run-api to launch HTTPS."
            )
        raise SystemExit(f"Port {API_PORT} is already in use by another process.")
    uvicorn.run(app, host=API_HOST, port=API_PORT, ssl_certfile=tls_cert_file, ssl_keyfile=tls_key_file)


if __name__ == "__main__":
    run_server()
