#!/usr/bin/env python3
"""Minimal Mailcart API for Matchy search/move operations."""

from __future__ import annotations

import os
from typing import Any

import requests
import uvicorn
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field


GRAPH_BASE = "https://graph.microsoft.com/v1.0"


def _graph_token() -> str:
    token = os.environ.get("OUTLOOK_GRAPH_TOKEN", "").strip()
    if token.startswith("Bearer "):
        token = token[7:].strip()
    return token


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
def search_messages(query: str = Query(default="", max_length=160), limit: int = Query(default=50, ge=1, le=100)) -> dict[str, Any]:
    payload = _graph_get(
        "/me/messages",
        params={
            "$select": "id,subject,bodyPreview,receivedDateTime,from",
            "$orderby": "receivedDateTime DESC",
            "$top": str(max(limit, 50)),
        },
    )
    normalized_query = query.strip().lower()
    messages = []
    for row in payload.get("value", []):
        subject = str(row.get("subject", ""))
        preview = str(row.get("bodyPreview", ""))
        if normalized_query:
            blob = f"{subject} {preview}".lower()
            if normalized_query not in blob:
                continue
        sender = str((((row.get("from") or {}).get("mailcartAddress") or {}).get("address")) or "")
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
def move_message(message_id: str, request: MoveRequest) -> dict[str, Any]:
    folder_id = _get_or_create_folder_id(request.folder_name)
    response = _graph_post(f"/me/messages/{message_id}/move", {"destinationId": folder_id})
    return {"moved": True, "folder_id": folder_id, "result_id": response.get("id", "")}


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8788)
