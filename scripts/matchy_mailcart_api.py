#!/usr/bin/env python3
"""Minimal Mailcart API for Matchy search/move operations."""

from __future__ import annotations

import os
import shutil
import socket
import subprocess  # nosec B404
from typing import Any

import requests
import uvicorn
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field


GRAPH_BASE = "https://graph.microsoft.com/v1.0"
DEFAULT_PSA_ITEM = "outlook_graph_token"
DEFAULT_PSA_FIELD = "password"


#R005: Normalize optional Bearer token prefix before Graph usage.
def _graph_token() -> str:
    token = os.environ.get("OUTLOOK_GRAPH_TOKEN", "").strip()
    if not token:
        token = _token_from_1psa()
    if token.startswith("Bearer "):
        token = token[7:].strip()
    return token


def _token_from_1psa() -> str:
    item = os.environ.get("OUTLOOK_GRAPH_TOKEN_PSA_ITEM", DEFAULT_PSA_ITEM).strip()
    # Default "password" is the standard 1Password field name, not an embedded credential.
    field = os.environ.get("OUTLOOK_GRAPH_TOKEN_PSA_FIELD", DEFAULT_PSA_FIELD).strip()
    if not item:
        raise HTTPException(status_code=500, detail="OUTLOOK_GRAPH_TOKEN_PSA_ITEM cannot be empty")
    if not field:
        raise HTTPException(status_code=500, detail="OUTLOOK_GRAPH_TOKEN_PSA_FIELD cannot be empty")
    psa_path = shutil.which("1psa")
    if not psa_path:
        raise HTTPException(status_code=500, detail="1psa is required to resolve OUTLOOK_GRAPH_TOKEN")
    try:
        # Arguments are explicit, shell is disabled, and executable path is resolved via shutil.which.
        completed = subprocess.run(
            [psa_path, "-f", item, field],
            check=True,
            capture_output=True,
            text=True,
            shell=False,  # nosec B603
        )
        return completed.stdout.strip()
    except FileNotFoundError as exc:
        raise HTTPException(status_code=500, detail="1psa is required to resolve OUTLOOK_GRAPH_TOKEN") from exc
    except subprocess.CalledProcessError as exc:
        detail = exc.stderr.strip() if exc.stderr else "unknown 1psa error"
        raise HTTPException(status_code=500, detail=f"Unable to resolve OUTLOOK_GRAPH_TOKEN via 1psa: {detail}") from exc


#R001: Require an Outlook Graph token for API-backed operations.
#R010: Build Graph request headers with auth and JSON content negotiation.
#R015: Fail request processing with explicit error when token is missing.
def _headers() -> dict[str, str]:
    token = _graph_token()
    if not token:
        raise HTTPException(status_code=500, detail="OUTLOOK_GRAPH_TOKEN is required")
    return {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "Content-Type": "application/json",
    }


def _graph_get(path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    response = requests.get(f"{GRAPH_BASE}{path}", params=params or {}, headers=_headers(), timeout=25)
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail=f"Graph GET failed: {response.status_code} {response.text[:200]}")
    return response.json()


def _graph_post(path: str, payload: dict[str, Any]) -> dict[str, Any]:
    response = requests.post(f"{GRAPH_BASE}{path}", json=payload, headers=_headers(), timeout=25)
    if response.status_code >= 400:
        raise HTTPException(status_code=502, detail=f"Graph POST failed: {response.status_code} {response.text[:200]}")
    if not response.text:
        return {}
    return response.json()


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
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/messages/search")
#R020: Return recent messages and apply optional text filtering with caller limit.
def search_messages(query: str = Query(default="", max_length=160), limit: int = Query(default=50, ge=1, le=100)) -> dict[str, Any]:
    payload: dict[str, Any] = {"value": []}
    normalized_query = query.strip()
    if normalized_query:
        try:
            payload = _graph_get(
                "/me/messages",
                params={"$select": "id,subject,bodyPreview,receivedDateTime,from", "$search": f"\"{normalized_query}\"", "$top": str(limit)},
            )
        except HTTPException:
            payload = {"value": []}
    if not payload.get("value"):
        payload = _graph_get(
            "/me/messages",
            params={
                "$select": "id,subject,bodyPreview,receivedDateTime,from",
                "$orderby": "receivedDateTime DESC",
                "$top": str(max(limit * 8, 200) if normalized_query else max(limit, 50)),
            },
        )
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


@app.post("/v1/messages/{message_id}/move")
#R025: Move selected message into requested destination folder.
def move_message(message_id: str, request: MoveRequest) -> dict[str, Any]:
    folder_id = _get_or_create_folder_id(request.folder_name)
    response = _graph_post(f"/me/messages/{message_id}/move", {"destinationId": folder_id})
    return {"moved": True, "folder_id": folder_id, "result_id": response.get("id", "")}


if __name__ == "__main__":
    in_use = False
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(0.25)
    if sock.connect_ex(("127.0.0.1", 8788)) == 0:
        in_use = True
    sock.close()
    if in_use:
        healthy = False
        try:
            probe = requests.get("http://127.0.0.1:8788/health", timeout=1.5)
            if probe.status_code == 200 and '"status":"ok"' in probe.text:
                healthy = True
        except Exception:
            healthy = False
        if healthy:
            print("Mailcart API already running on 127.0.0.1:8788; reusing existing process.")
            raise SystemExit(0)
        raise SystemExit("Port 8788 is already in use by another process.")
    uvicorn.run(app, host="127.0.0.1", port=8788)
