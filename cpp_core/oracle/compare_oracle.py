#!/usr/bin/env python3
"""Mailcart Python<->C++ oracle parity harness.

Drives every scenario in scenarios.json through BOTH stacks against the same
canned Graph upstream and diffs the normalized results:

  * Python reference: the FastAPI app in scripts/matchy_mailcart_api.py, invoked
    over its ASGI interface (no network, no httpx) with `requests` monkeypatched
    to serve the scenario's graph[] fixtures and 1psa lookups disabled.
  * C++ port: tools/oracle_runner.cpp (mailcart_oracle_runner) running the same
    scenarios.json against its in-process stub Graph transport.

While the Python reference still exists this proves byte-parity; once it is
retired, oracle/goldens.json (frozen here with --record) is replayed by
mailcart_oracle_runner in the t19 lane.

Usage:
  compare_oracle.py [--scenarios FILE] [--runner BIN] [--record GOLDENS]
"""
from __future__ import annotations

import argparse
import asyncio
import json
import os
import subprocess  # nosec B404
import sys
import tempfile
from pathlib import Path
from typing import Any
from urllib.parse import urlencode

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = REPO_ROOT / "scripts"
DEFAULT_SCENARIOS = Path(__file__).resolve().parent / "scenarios.json"
DEFAULT_RUNNER = REPO_ROOT / "cpp_core" / "build" / "mailcart_oracle_runner"

# Must match kOracleJwt in tools/oracle_runner.cpp: unsigned JWT with exp 2100-01-01.
ORACLE_JWT = "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJleHAiOjQxMDI0NDQ4MDB9.signature"

sys.path.insert(0, str(SCRIPTS_DIR))
import graph_token  # noqa: E402
import matchy_mailcart_api as api  # noqa: E402

GRAPH_BASE = api.GRAPH_BASE  # https://graph.microsoft.com/v1.0


class _FakeResponse:
    def __init__(self, status_code: int, text: str) -> None:
        self.status_code = status_code
        self.text = text

    def json(self) -> Any:
        return json.loads(self.text)


class _StubGraph:
    """Mirror of tools/oracle_runner.cpp StubGraphTransport semantics."""

    def __init__(self, entries: list[dict[str, Any]]) -> None:
        self._entries = list(entries or [])
        self._consumed = [False] * len(self._entries)

    @staticmethod
    def _entry_text(entry: dict[str, Any]) -> str:
        if "json" in entry:
            # nlohmann's dump() emits compact JSON with no spaces; match it so any
            # verbatim echo of the body (error details) is byte-identical.
            return json.dumps(entry["json"], separators=(",", ":"))
        return str(entry.get("body", ""))

    def request(self, method: str, url: str, params=None, json=None, headers=None, timeout=None, **_):  # noqa: A002
        path = url[len(GRAPH_BASE):] if url.startswith(GRAPH_BASE) else url
        actual_params = list((params or {}).items())
        for index, entry in enumerate(self._entries):
            if self._consumed[index]:
                continue
            if entry.get("method", "") != method or entry.get("path", "") != path:
                continue
            expected_params = entry.get("params")
            if isinstance(expected_params, dict):
                if not all((key, str(value)) in [(k, str(v)) for k, v in actual_params]
                           for key, value in expected_params.items()):
                    continue
            if not entry.get("sticky", False):
                self._consumed[index] = True
            return _FakeResponse(int(entry.get("status", 200)), self._entry_text(entry))
        body = ('{"error":{"code":"ItemNotFound","message":"no fixture matched '
                + method + " " + path + '"}}')
        return _FakeResponse(404, body)

    def post(self, url, data=None, json=None, timeout=None, **_):  # noqa: A002
        # Token refresh endpoint; unused by the parity scenarios (no refresh token
        # is configured, so refresh() raises before reaching the network).
        return _FakeResponse(400, '{"error":"refresh disabled in oracle"}')


def _call_asgi(method: str, path: str, query: dict[str, Any], headers: dict[str, str],
               body_obj: Any) -> tuple[int, bytes, dict[str, str]]:
    raw_headers: list[tuple[bytes, bytes]] = [(k.lower().encode(), str(v).encode())
                                              for k, v in (headers or {}).items()]
    body = b""
    if body_obj is not None:
        body = json.dumps(body_obj).encode()
        raw_headers.append((b"content-type", b"application/json"))
    query_string = urlencode(list((query or {}).items())).encode()
    scope = {
        "type": "http",
        "asgi": {"version": "3.0", "spec_version": "2.3"},
        "http_version": "1.1",
        "method": method,
        "scheme": "https",
        "path": path,
        "raw_path": path.encode(),
        "query_string": query_string,
        "headers": raw_headers,
        "server": (api.API_HOST, api.API_PORT),
        "client": ("127.0.0.1", 50000),
        "root_path": "",
    }
    messages = [{"type": "http.request", "body": body, "more_body": False}]
    captured: dict[str, Any] = {"status": 500, "headers": [], "body": b""}

    async def receive() -> dict[str, Any]:
        return messages.pop(0) if messages else {"type": "http.disconnect"}

    async def send(message: dict[str, Any]) -> None:
        if message["type"] == "http.response.start":
            captured["status"] = message["status"]
            captured["headers"] = message.get("headers", [])
        elif message["type"] == "http.response.body":
            captured["body"] += message.get("body", b"")

    async def run() -> None:
        await api.app(scope, receive, send)

    asyncio.run(run())
    header_map = {k.decode().lower(): v.decode() for k, v in captured["headers"]}
    return captured["status"], captured["body"], header_map


def _raise_no_psa(item: str, field: str) -> str:
    raise graph_token.GraphTokenError("1psa is required to resolve Outlook Graph credentials")


def run_python_scenario(scenario: dict[str, Any], cache_dir: Path) -> dict[str, Any]:
    os.environ["OUTLOOK_GRAPH_TOKEN"] = ORACLE_JWT
    for key in ("OUTLOOK_GRAPH_CLIENT_ID", "MAILCART_API_WRITE_TOKEN_HEADER",
                "TELLER_CLASSIFIER_WRITE_TOKEN", "CLASSY_WRITE_TOKEN"):
        os.environ.pop(key, None)
    write_token = scenario.get("write_token", "")
    if write_token:
        os.environ["MAILCART_API_WRITE_TOKEN"] = write_token
    else:
        os.environ.pop("MAILCART_API_WRITE_TOKEN", None)

    cache_path = cache_dir / (scenario.get("name", "scenario") + ".graph_oauth.json")
    if cache_path.exists():
        cache_path.unlink()

    stub = _StubGraph(scenario.get("graph", []))
    saved_read_psa = graph_token._read_psa_field
    api._TOKEN_MANAGER.cache_path = cache_path
    api._TOKEN_MANAGER.invalidate()
    api.requests = stub  # type: ignore[assignment]
    graph_token.requests = stub  # type: ignore[assignment]
    graph_token._read_psa_field = _raise_no_psa  # type: ignore[assignment]
    try:
        request = scenario["request"]
        status, body, header_map = _call_asgi(
            request.get("method", "GET"),
            request.get("path", "/"),
            request.get("query", {}),
            request.get("headers", {}),
            request.get("body"),
        )
    finally:
        graph_token._read_psa_field = saved_read_psa  # type: ignore[assignment]

    result: dict[str, Any] = {"name": scenario.get("name", ""), "status": status}
    result["body"] = json.loads(body) if body else None
    if "www-authenticate" in header_map:
        result["www_authenticate"] = header_map["www-authenticate"]
    return result


def run_python_scenarios(scenarios: list[dict[str, Any]]) -> list[dict[str, Any]]:
    with tempfile.TemporaryDirectory(prefix="mailcart-oracle-py-") as tmp:
        cache_dir = Path(tmp)
        return [run_python_scenario(scenario, cache_dir) for scenario in scenarios]


def run_cpp_scenarios(runner: Path, scenarios_path: Path) -> list[dict[str, Any]]:
    completed = subprocess.run(  # nosec B603
        [str(runner), "run", "--scenarios", str(scenarios_path)],
        check=True, capture_output=True, text=True,
    )
    return json.loads(completed.stdout)


def normalize(result: dict[str, Any]) -> dict[str, Any]:
    """Allowlisted normalization for documented, non-contract divergences.

    pydantic v2 (FastAPI) tags each 422 validation entry with a 'url' pointing at
    the pydantic error docs; the C++ port omits this non-contract field. Drop it
    from both sides before comparing.
    """
    normalized = json.loads(json.dumps(result))
    body = normalized.get("body")
    if isinstance(body, dict) and isinstance(body.get("detail"), list):
        for entry in body["detail"]:
            if isinstance(entry, dict):
                entry.pop("url", None)
    return normalized


def main() -> int:
    parser = argparse.ArgumentParser(description="Mailcart Python<->C++ oracle parity harness")
    parser.add_argument("--scenarios", type=Path, default=DEFAULT_SCENARIOS)
    parser.add_argument("--runner", type=Path, default=DEFAULT_RUNNER)
    parser.add_argument("--record", type=Path, default=None,
                        help="Freeze verified results to this goldens file.")
    args = parser.parse_args()

    document = json.loads(args.scenarios.read_text())
    scenarios = document["scenarios"]

    python_results = run_python_scenarios(scenarios)
    cpp_results = run_cpp_scenarios(args.runner, args.scenarios)

    mismatches = 0
    for index, scenario in enumerate(scenarios):
        name = scenario.get("name", str(index))
        py = normalize(python_results[index])
        cpp = normalize(cpp_results[index]) if index < len(cpp_results) else {}
        if py != cpp:
            mismatches += 1
            print(f"MISMATCH [{name}]")
            print(f"  python: {json.dumps(py, sort_keys=True)}")
            print(f"  cpp:    {json.dumps(cpp, sort_keys=True)}")

    if mismatches:
        print(f"\n{mismatches} scenario(s) diverged between Python and C++")
        return 1

    print(f"All {len(scenarios)} scenarios match between Python and C++.")
    if args.record is not None:
        # Freeze the C++ results (the surviving runtime) as the replay goldens.
        args.record.write_text(json.dumps(cpp_results, indent=2) + "\n")
        print(f"Recorded {len(cpp_results)} goldens to {args.record}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
