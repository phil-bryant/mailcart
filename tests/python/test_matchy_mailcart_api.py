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


if __name__ == "__main__":
    unittest.main()
