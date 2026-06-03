#!/usr/bin/env python3
"""Minimal Mailcart API for Matchy search/move operations."""

# Traceability anchors for requirements whose implementation is delegated to scripts/graph_token.py:
# #R005: Bearer-prefix normalization (graph_token._normalize_token)
# #R026: Graph refresh-token exchange (graph_token.GraphTokenManager.refresh)
# #R028: OAuth session cache persistence (graph_token.GraphTokenManager.persist)

from __future__ import annotations

from collections import deque
from datetime import date, datetime
from html import unescape
import os
import re
import socket
import sys
from urllib.parse import parse_qsl, quote, unquote, urlsplit
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


def _graph_get_next_link(next_link: str) -> dict[str, Any]:
    parsed_next = urlsplit(next_link)
    parsed_base = urlsplit(GRAPH_BASE)
    if (parsed_next.scheme, parsed_next.netloc) != (parsed_base.scheme, parsed_base.netloc):
        raise HTTPException(status_code=502, detail="Graph pagination returned an unexpected host")
    path = parsed_next.path
    if parsed_base.path and path.startswith(parsed_base.path):
        path = path[len(parsed_base.path) :] or "/"
    params = dict(parse_qsl(parsed_next.query, keep_blank_values=True))
    return _graph_get(path, params=params)


def _graph_message_path(message_id: str) -> str:
    # Normalize possibly pre-encoded IDs, then quote as a single path segment.
    normalized_id = unquote(message_id)
    return f"/me/messages/{quote(normalized_id, safe='')}"


_TOKEN_PATTERN = re.compile(r"(?i)\b(subject|sender|body|from|to)\s*:")


def _normalize_search_text(value: str) -> str:
    #R020: Normalize scoped search text by trimming, collapsing whitespace, and case-folding.
    return re.sub(r"\s+", " ", value.strip()).casefold()


def _strip_html(value: str) -> str:
    #R020: Convert HTML body payloads to plain searchable text before normalization.
    no_script = re.sub(r"(?is)<(script|style)\b[^>]*>.*?</\1>", " ", value)
    no_tags = re.sub(r"(?s)<[^>]+>", " ", no_script)
    return unescape(no_tags)


def _extract_body_text(message: dict[str, Any]) -> str:
    #R020: Evaluate body: tokens against full body content when available.
    body_obj = message.get("body") or {}
    if not isinstance(body_obj, dict):
        return str(message.get("bodyPreview", ""))
    content = str(body_obj.get("content", ""))
    content_type = str(body_obj.get("contentType", "")).casefold()
    if content_type == "html":
        return _strip_html(content)
    if content_type == "text":
        return content
    return str(message.get("bodyPreview", ""))


def _parse_iso_date(value: str) -> date:
    #R020: Enforce strict yyyy-mm-dd parsing for from:/to: scoped filters.
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise ValueError("date must use yyyy-mm-dd")
    return date.fromisoformat(value)


def _parse_received_at_date(value: str) -> date | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).date()
    except ValueError:
        return None


def _parse_scoped_query(query: str) -> dict[str, list[str] | date | None]:
    #R020: Parse scoped search tokens and reject unsupported/unprefixed token text.
    normalized_query = query.strip()
    if not normalized_query:
        return {
            "subject": [],
            "sender": [],
            "body": [],
            "from": None,
            "to": None,
        }
    matches = list(_TOKEN_PATTERN.finditer(normalized_query))
    if not matches:
        raise HTTPException(
            status_code=400,
            detail="Invalid query: use scoped tokens subject:, sender:, body:, from:, or to:.",
        )
    parsed: dict[str, list[str] | date | None] = {
        "subject": [],
        "sender": [],
        "body": [],
        "from": None,
        "to": None,
    }
    cursor = 0
    for index, match in enumerate(matches):
        prefix_region = normalized_query[cursor : match.start()]
        if prefix_region.strip():
            raise HTTPException(
                status_code=400,
                detail="Invalid query: unsupported or unscoped token content detected.",
            )
        token = match.group(1).casefold()
        value_start = match.end()
        value_end = matches[index + 1].start() if index + 1 < len(matches) else len(normalized_query)
        raw_value = normalized_query[value_start:value_end].strip()
        if not raw_value:
            raise HTTPException(status_code=400, detail=f"Invalid query: {token}: requires a value.")
        if token in ("subject", "sender", "body"):
            normalized_value = _normalize_search_text(raw_value)
            if not normalized_value:
                raise HTTPException(status_code=400, detail=f"Invalid query: {token}: requires text.")
            cast_values = parsed[token]
            if not isinstance(cast_values, list):
                raise HTTPException(status_code=500, detail="Search token parser state error.")
            cast_values.append(normalized_value)
        elif token == "from":  # nosec B105
            if parsed["from"] is not None:
                raise HTTPException(status_code=400, detail="Invalid query: duplicate from: token.")
            try:
                parsed["from"] = _parse_iso_date(raw_value)
            except ValueError as exc:
                raise HTTPException(status_code=400, detail=f"Invalid query: from: {exc}") from exc
        else:  # token == "to"
            if parsed["to"] is not None:
                raise HTTPException(status_code=400, detail="Invalid query: duplicate to: token.")
            try:
                parsed["to"] = _parse_iso_date(raw_value)
            except ValueError as exc:
                raise HTTPException(status_code=400, detail=f"Invalid query: to: {exc}") from exc
        cursor = value_end
    if normalized_query[cursor:].strip():
        raise HTTPException(
            status_code=400,
            detail="Invalid query: unsupported or unscoped token content detected.",
        )
    from_date = parsed["from"]
    to_date = parsed["to"]
    if isinstance(from_date, date) and isinstance(to_date, date) and from_date > to_date:
        raise HTTPException(status_code=400, detail="Invalid query: from: date cannot be after to: date.")
    return parsed


#R050: Aho-Corasick automaton: build a keyword trie with failure links so one linear pass over a
#R050: message field reports every scoped filter that occurs as a substring, replacing the per-filter
#R050: re-scan with a single O(text + patterns) traversal across the full-mailbox search.
class AhoCorasick:
    def __init__(self, patterns: list[str]) -> None:
        self._goto: list[dict[str, int]] = [{}]
        self._fail: list[int] = [0]
        self._output: list[set[str]] = [set()]
        for pattern in patterns:
            if pattern:
                self._add_pattern(pattern)
        self._build_failure_links()

    def _add_pattern(self, pattern: str) -> None:
        node = 0
        for char in pattern:
            next_node = self._goto[node].get(char)
            if next_node is None:
                next_node = len(self._goto)
                self._goto.append({})
                self._fail.append(0)
                self._output.append(set())
                self._goto[node][char] = next_node
            node = next_node
        self._output[node].add(pattern)

    def _build_failure_links(self) -> None:
        queue: deque[int] = deque()
        for next_node in self._goto[0].values():
            queue.append(next_node)
        while queue:
            node = queue.popleft()
            for char, next_node in self._goto[node].items():
                queue.append(next_node)
                fail_node = self._fail[node]
                while fail_node != 0 and char not in self._goto[fail_node]:
                    fail_node = self._fail[fail_node]
                target = self._goto[fail_node].get(char, 0)
                if target == next_node:
                    target = 0
                self._fail[next_node] = target
                self._output[next_node] = self._output[next_node] | self._output[target]

    #R050: Return the set of patterns occurring as substrings of text in a single pass.
    def search(self, text: str) -> set[str]:
        found: set[str] = set()
        node = 0
        for char in text:
            while node != 0 and char not in self._goto[node]:
                node = self._fail[node]
            node = self._goto[node].get(char, 0)
            found = found | self._output[node]
        return found


#R050: Build one Aho-Corasick matcher over the union of scoped text filters so it is constructed once
#R050: per search request and reused across every scanned message.
def _build_criteria_matcher(criteria: dict[str, list[str] | date | None]) -> AhoCorasick:
    patterns: set[str] = set()
    for field in ("subject", "sender", "body"):
        values = criteria[field] if isinstance(criteria[field], list) else []
        for value in values:
            if value:
                patterns.add(value)
    return AhoCorasick(sorted(patterns))


def _message_matches_criteria(message: dict[str, Any], criteria: dict[str, list[str] | date | None],
                              matcher: AhoCorasick | None = None) -> bool:
    #R020: Apply AND semantics across scoped text and inclusive date range filters.
    #R050: Resolve all scoped-token substring hits per field via a single Aho-Corasick pass.
    active_matcher = matcher if matcher is not None else _build_criteria_matcher(criteria)
    subject = _normalize_search_text(str(message.get("subject", "")))
    sender = _normalize_search_text(str((((message.get("from") or {}).get("emailAddress") or {}).get("address")) or ""))
    body_text = _normalize_search_text(_extract_body_text(message))
    subject_hits = active_matcher.search(subject)
    sender_hits = active_matcher.search(sender)
    body_hits = active_matcher.search(body_text)
    subject_filters = criteria["subject"] if isinstance(criteria["subject"], list) else []
    sender_filters = criteria["sender"] if isinstance(criteria["sender"], list) else []
    body_filters = criteria["body"] if isinstance(criteria["body"], list) else []
    matches = True
    for token in subject_filters:
        if token not in subject_hits:
            matches = False
    for token in sender_filters:
        if token not in sender_hits:
            matches = False
    for token in body_filters:
        if token not in body_hits:
            matches = False
    received_at_date = _parse_received_at_date(str(message.get("receivedDateTime", "")))
    from_date = criteria["from"]
    to_date = criteria["to"]
    if isinstance(from_date, date):
        if received_at_date is None or received_at_date < from_date:
            matches = False
    if isinstance(to_date, date):
        if received_at_date is None or received_at_date > to_date:
            matches = False
    return matches


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
def search_messages(query: str = Query(default="", max_length=400), limit: int = Query(default=50, ge=1, le=100)) -> dict[str, Any]:
    criteria = _parse_scoped_query(query)
    normalized_query = query.strip()
    from_date = criteria["from"]
    to_date = criteria["to"]
    graph_params: dict[str, Any] = {
        "$select": "id,subject,bodyPreview,body,receivedDateTime,from",
        "$orderby": "receivedDateTime DESC",
        "$top": str(max(limit * 8, 200) if normalized_query else max(limit, 50)),
    }
    graph_filters: list[str] = []
    if isinstance(from_date, date):
        graph_filters.append(f"receivedDateTime ge {from_date.isoformat()}T00:00:00Z")
    if isinstance(to_date, date):
        graph_filters.append(f"receivedDateTime le {to_date.isoformat()}T23:59:59Z")
    if graph_filters:
        graph_params["$filter"] = " and ".join(graph_filters)
    #R030: Surface Graph auth failures explicitly instead of swallowing them as empty `{"messages": []}` results.
    payload: dict[str, Any] = _graph_get(
        "/me/messages",
        params=graph_params,
    )
    messages = []
    #R050: Construct the Aho-Corasick matcher once per request and reuse it for every scanned message.
    criteria_matcher = _build_criteria_matcher(criteria)
    should_paginate = isinstance(from_date, date) or isinstance(to_date, date)
    max_scanned_rows = max(limit * 100, 2_000) if should_paginate else max(limit * 8, 200)
    scanned_rows = 0
    while True:
        page_rows = payload.get("value", [])
        if not isinstance(page_rows, list):
            page_rows = []
        oldest_received_on_page: date | None = None
        for row in page_rows:
            if not isinstance(row, dict):
                continue
            scanned_rows += 1
            received_at_date = _parse_received_at_date(str(row.get("receivedDateTime", "")))
            if isinstance(received_at_date, date):
                if oldest_received_on_page is None or received_at_date < oldest_received_on_page:
                    oldest_received_on_page = received_at_date
            subject = str(row.get("subject", ""))
            preview = str(row.get("bodyPreview", ""))
            sender = str((((row.get("from") or {}).get("emailAddress") or {}).get("address")) or "")
            body_text = _extract_body_text(row)
            if normalized_query and not _message_matches_criteria(row, criteria, matcher=criteria_matcher):
                continue
            messages.append(
                {
                    "message_id": str(row.get("id", "")),
                    "subject": subject,
                    "preview": preview,
                    "received_at": str(row.get("receivedDateTime", "")),
                    "sender": sender,
                    "body_text": body_text,
                }
            )
            if len(messages) >= limit:
                break
        if len(messages) >= limit or not normalized_query:
            break
        if not should_paginate:
            break
        if scanned_rows >= max_scanned_rows:
            break
        if isinstance(from_date, date) and isinstance(oldest_received_on_page, date) and oldest_received_on_page < from_date:
            break
        next_link = payload.get("@odata.nextLink")
        if not isinstance(next_link, str) or not next_link:
            break
        payload = _graph_get_next_link(next_link)
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
            "Run ./04_install_matchy_api_tls.sh to install local TLS materials."
        )
    if not key_file.is_file():
        raise SystemExit(
            f"{TLS_KEY_ENV} is required and must point to an existing key file: {key_file}. "
            "Run ./04_install_matchy_api_tls.sh to install local TLS materials."
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
        # Intentional localhost HTTP probe to detect and report a legacy non-TLS Mailcart API process.
        probe = requests.get(f"http://{API_HOST}:{API_PORT}/health", timeout=1.5)  # nosemgrep: python.lang.security.audit.insecure-transport.requests.request-with-http.request-with-http
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
