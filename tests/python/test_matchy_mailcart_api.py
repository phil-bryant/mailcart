#!/usr/bin/env python3
"""Unit tests for matchy_mailcart_api."""

# Requirement test-case tags for requirements/matchy_mailcart_api-requirements.md
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.
# #R025-T02: Traceability anchor.
# #R035-T01: Traceability anchor.
# #R035-T02: Traceability anchor.

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import matchy_mailcart_api as api  # noqa: E402


class GetMessageEndpointTests(unittest.TestCase):
    def test_get_message_returns_full_body_for_html(self) -> None:
        #R035-T01
        payload = {
            "id": "msg_42",
            "subject": "Receipt",
            "bodyPreview": "Thanks for your order",
            "body": {"contentType": "html", "content": "<p>Thanks!</p>"},
            "from": {"emailAddress": {"address": "store@example.com"}},
            "toRecipients": [
                {"emailAddress": {"address": "me@example.com"}},
                {"emailAddress": {"address": "cc@example.com"}},
            ],
            "receivedDateTime": "2026-05-17T12:00:00Z",
        }
        with mock.patch.object(api, "_graph_get", return_value=payload) as graph_get:
            result = api.get_message("msg_42")
        graph_get.assert_called_once()
        call_path, call_kwargs = graph_get.call_args.args[0], graph_get.call_args.kwargs
        self.assertEqual(call_path, "/me/messages/msg_42")
        self.assertIn("$select", call_kwargs.get("params", {}))
        self.assertEqual(result["message_id"], "msg_42")
        self.assertEqual(result["subject"], "Receipt")
        self.assertEqual(result["preview"], "Thanks for your order")
        self.assertEqual(result["sender"], "store@example.com")
        self.assertEqual(result["recipients"], "me@example.com,cc@example.com")
        self.assertEqual(result["html_body"], "<p>Thanks!</p>")
        self.assertEqual(result["text_body"], "")
        self.assertEqual(result["received_at"], "2026-05-17T12:00:00Z")

    def test_get_message_returns_text_body_for_plain(self) -> None:
        #R035-T01
        payload = {
            "id": "msg_99",
            "subject": "Plain",
            "bodyPreview": "preview",
            "body": {"contentType": "text", "content": "hello world"},
            "from": {"emailAddress": {"address": "alice@example.com"}},
            "toRecipients": [],
            "receivedDateTime": "2026-05-17T12:00:00Z",
        }
        with mock.patch.object(api, "_graph_get", return_value=payload):
            result = api.get_message("msg_99")
        self.assertEqual(result["text_body"], "hello world")
        self.assertEqual(result["html_body"], "")
        self.assertEqual(result["body_text"], "hello world")
        self.assertEqual(result["recipients"], "")

    def test_get_message_rejects_blank_id(self) -> None:
        #R035-T02
        with self.assertRaises(Exception) as ctx:
            api.get_message("   ")
        self.assertEqual(getattr(ctx.exception, "status_code", None), 400)


class GetMessageRoutingTests(unittest.TestCase):
    def test_get_message_route_is_registered(self) -> None:
        #R035-T01
        paths = {getattr(route, "path", None) for route in api.app.routes}
        self.assertIn("/v1/messages/{message_id}", paths)


class GraphRequestAuthTests(unittest.TestCase):
    def test_graph_request_retries_once_on_401_then_succeeds(self) -> None:
        first = mock.Mock(status_code=401, text="InvalidAuthenticationToken")
        second = mock.Mock(status_code=200, text='{"ok": true}')
        second.json.return_value = {"ok": True}

        with (
            mock.patch.object(api, "_headers", return_value={"Authorization": "Bearer t"}),
            mock.patch.object(api.requests, "request", side_effect=[first, second]) as request_mock,
            mock.patch.object(api._TOKEN_MANAGER, "invalidate") as invalidate_mock,
            mock.patch.object(api._TOKEN_MANAGER, "refresh") as refresh_mock,
        ):
            result = api._graph_request("GET", "/me/messages/msg_1")

        self.assertEqual(result, {"ok": True})
        self.assertEqual(request_mock.call_count, 2)
        invalidate_mock.assert_called_once()
        refresh_mock.assert_called_once_with(force=True)

    def test_graph_request_returns_502_when_refresh_fails_after_401(self) -> None:
        response = mock.Mock(status_code=401, text="InvalidAuthenticationToken")

        with (
            mock.patch.object(api, "_headers", return_value={"Authorization": "Bearer t"}),
            mock.patch.object(api.requests, "request", return_value=response),
            mock.patch.object(api._TOKEN_MANAGER, "invalidate"),
            mock.patch.object(api._TOKEN_MANAGER, "refresh", side_effect=api.GraphTokenError("invalid_grant")),
        ):
            with self.assertRaises(Exception) as ctx:
                api._graph_request("GET", "/me/messages/msg_2")

        self.assertEqual(getattr(ctx.exception, "status_code", None), 502)
        self.assertIn("token refresh failed", str(getattr(ctx.exception, "detail", "")))

    def test_graph_request_returns_502_when_second_attempt_is_still_401(self) -> None:
        first = mock.Mock(status_code=401, text="InvalidAuthenticationToken")
        second = mock.Mock(status_code=401, text="InvalidAuthenticationToken")

        with (
            mock.patch.object(api, "_headers", return_value={"Authorization": "Bearer t"}),
            mock.patch.object(api.requests, "request", side_effect=[first, second]) as request_mock,
            mock.patch.object(api._TOKEN_MANAGER, "invalidate") as invalidate_mock,
            mock.patch.object(api._TOKEN_MANAGER, "refresh") as refresh_mock,
        ):
            with self.assertRaises(Exception) as ctx:
                api._graph_request("GET", "/me/messages/msg_3")

        self.assertEqual(getattr(ctx.exception, "status_code", None), 502)
        self.assertIn("Graph auth failed", str(getattr(ctx.exception, "detail", "")))
        self.assertEqual(request_mock.call_count, 2)
        invalidate_mock.assert_called_once()
        refresh_mock.assert_called_once_with(force=True)


class MessageIdEncodingTests(unittest.TestCase):
    def test_get_message_url_encodes_reserved_characters(self) -> None:
        payload = {
            "id": "abc123==",
            "subject": "",
            "bodyPreview": "",
            "body": {"contentType": "text", "content": ""},
            "from": {"emailAddress": {"address": ""}},
            "toRecipients": [],
            "receivedDateTime": "",
        }
        with mock.patch.object(api, "_graph_get", return_value=payload) as graph_get:
            api.get_message("abc123==")
        self.assertEqual(graph_get.call_args.args[0], "/me/messages/abc123%3D%3D")

    def test_get_message_url_normalizes_already_encoded_id(self) -> None:
        payload = {
            "id": "abc123==",
            "subject": "",
            "bodyPreview": "",
            "body": {"contentType": "text", "content": ""},
            "from": {"emailAddress": {"address": ""}},
            "toRecipients": [],
            "receivedDateTime": "",
        }
        with mock.patch.object(api, "_graph_get", return_value=payload) as graph_get:
            api.get_message("abc123%3D%3D")
        self.assertEqual(graph_get.call_args.args[0], "/me/messages/abc123%3D%3D")

    def test_move_message_url_encodes_reserved_characters(self) -> None:
        with (
            mock.patch.object(api, "_get_or_create_folder_id", return_value="folder-1"),
            mock.patch.object(api, "_graph_post", return_value={"id": "moved-1"}) as graph_post,
        ):
            result = api.move_message("abc123==", api.MoveRequest(folder_name="matchy"))
        self.assertEqual(graph_post.call_args.args[0], "/me/messages/abc123%3D%3D/move")
        self.assertEqual(result["moved"], True)


if __name__ == "__main__":
    unittest.main()
