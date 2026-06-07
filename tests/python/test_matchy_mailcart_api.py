#!/usr/bin/env python3
"""Unit tests for matchy_mailcart_api."""

# Requirement test-case tags for requirements/matchy_mailcart_api-requirements.md
# #R020-T01: Traceability anchor.
# #R025-T01: Traceability anchor.
# #R025-T02: Traceability anchor.
# #R035-T01: Traceability anchor.
# #R035-T02: Traceability anchor.
# #R029-T01: Traceability anchor.
# #R050-T01: Traceability anchor.
# #R620-T01: Traceability anchor.

from __future__ import annotations

from itertools import product
import tempfile
import sys
import unittest
from pathlib import Path
from unittest import mock

def _resolve_scripts_dir(module_filename: str) -> Path:
    #R020: Resolve scripts directory robustly for copied mutation/fuzz test paths.
    # Keep imports stable when tests are copied under artifacts/mutation/mutants.
    probe_roots = [Path.cwd().resolve(), *Path(__file__).resolve().parents]
    for root in probe_roots:
        candidate = root / "scripts"
        if (candidate / module_filename).is_file():
            return candidate
    return Path(__file__).resolve().parents[2] / "scripts"


sys.path.insert(0, str(_resolve_scripts_dir("matchy_mailcart_api.py")))

import matchy_mailcart_api as api  # noqa: E402


class SearchMessagesTests(unittest.TestCase):
    def _search(self, query: str, rows: list[dict[str, object]], limit: int = 50) -> dict[str, object]:
        #R020: Helper - run search_messages against mocked Graph rows.
        with mock.patch.object(api, "_graph_get", return_value={"value": rows}) as graph_get:
            result = api.search_messages(query=query, limit=limit)
        graph_get.assert_called_once()
        return result

    def _mk_message(
        self,
        message_id: str,
        *,
        subject: str = "",
        sender: str = "",
        preview: str = "",
        body_content: str = "",
        body_content_type: str = "text",
        received_at: str = "2026-04-15T12:00:00Z",
    ) -> dict[str, object]:
        #R020: Helper - build a Graph message fixture for search tests.
        return {
            "id": message_id,
            "subject": subject,
            "bodyPreview": preview,
            "body": {"contentType": body_content_type, "content": body_content},
            "from": {"emailAddress": {"address": sender}},
            "receivedDateTime": received_at,
        }

    def test_field_scoping_filters_subject_sender_body_independently(self) -> None:
        #R020-T01: field-scoped tokens filter subject/sender/body independently.
        rows = [
            self._mk_message("msg1", subject="DoorDash receipt", sender="merchant@example.com", body_content="hello"),
            self._mk_message("msg2", subject="Hello", sender="doordash@merchant.com", body_content="hello"),
            self._mk_message("msg3", subject="Hello", sender="merchant@example.com", body_content="DOORDASH order details"),
        ]
        subject_ids = [m["message_id"] for m in self._search("subject:doordash", rows)["messages"]]
        sender_ids = [m["message_id"] for m in self._search("sender:doordash", rows)["messages"]]
        body_ids = [m["message_id"] for m in self._search("body:doordash", rows)["messages"]]
        self.assertEqual(subject_ids, ["msg1"])
        self.assertEqual(sender_ids, ["msg2"])
        self.assertEqual(body_ids, ["msg3"])

    def test_case_insensitive_field_matches_return_same_results(self) -> None:
        #R020-T01: scoped matches are case-insensitive.
        rows = [
            self._mk_message("msg1", subject="DoorDash", sender="shop@example.com", body_content="x"),
            self._mk_message("msg2", subject="x", sender="DoorDash@shop.com", body_content="x"),
            self._mk_message("msg3", subject="x", sender="shop@example.com", body_content="DOORDASH body"),
        ]
        expected_subject = ["msg1"]
        expected_sender = ["msg2"]
        expected_body = ["msg3"]
        for variant in ("DoorDash", "doordash", "DOORDASH"):
            with self.subTest(variant=variant):
                subject_ids = [m["message_id"] for m in self._search(f"subject:{variant}", rows)["messages"]]
                sender_ids = [m["message_id"] for m in self._search(f"sender:{variant}", rows)["messages"]]
                body_ids = [m["message_id"] for m in self._search(f"body:{variant}", rows)["messages"]]
                self.assertEqual(subject_ids, expected_subject)
                self.assertEqual(sender_ids, expected_sender)
                self.assertEqual(body_ids, expected_body)

    def test_whitespace_normalization_matches_irregular_spacing(self) -> None:
        #R020-T01: irregular spacing is normalized before matching.
        rows = [
            self._mk_message("subject", subject="DoorDash order total", sender="x@example.com", body_content="x"),
            self._mk_message("sender", subject="x", sender="DoorDash order total", body_content="x"),
            self._mk_message("body", subject="x", sender="x@example.com", body_content="DoorDash order total"),
        ]
        subject_ids = [m["message_id"] for m in self._search("subject:  DoorDash   order    total", rows)["messages"]]
        sender_ids = [m["message_id"] for m in self._search("sender:  DoorDash   order    total", rows)["messages"]]
        body_ids = [m["message_id"] for m in self._search("body:  DoorDash   order    total", rows)["messages"]]
        self.assertEqual(subject_ids, ["subject"])
        self.assertEqual(sender_ids, ["sender"])
        self.assertEqual(body_ids, ["body"])

    def test_multiple_tokens_use_and_semantics(self) -> None:
        #R020-T01: multiple scoped tokens combine with AND semantics.
        rows = [
            self._mk_message("msgA", subject="receipt available", sender="hello@example.com", body_content="x"),
            self._mk_message("msgB", subject="invoice", sender="doordash@shop.com", body_content="x"),
            self._mk_message("msgC", subject="receipt from store", sender="doordash@shop.com", body_content="x"),
        ]
        ids = [m["message_id"] for m in self._search("subject:receipt sender:doordash", rows)["messages"]]
        self.assertEqual(ids, ["msgC"])

    def test_date_bounds_are_inclusive(self) -> None:
        #R020-T01: from:/to: date bounds are inclusive.
        rows = [
            self._mk_message("start", received_at="2026-04-01T00:00:00Z"),
            self._mk_message("middle", received_at="2026-04-15T12:00:00Z"),
            self._mk_message("end", received_at="2026-04-30T23:59:59Z"),
            self._mk_message("outside_before", received_at="2026-03-31T23:59:59Z"),
            self._mk_message("outside_after", received_at="2026-05-01T00:00:00Z"),
        ]
        ids = [m["message_id"] for m in self._search("from:2026-04-01 to:2026-04-30", rows)["messages"]]
        self.assertEqual(ids, ["start", "middle", "end"])

    def test_graph_query_includes_server_side_date_filter(self) -> None:
        #R020-T01: date queries push a server-side receivedDateTime filter.
        with mock.patch.object(api, "_graph_get", return_value={"value": []}) as graph_get:
            api.search_messages(query="from:2026-04-01 to:2026-04-30", limit=25)
        _, kwargs = graph_get.call_args
        params = kwargs.get("params", {})
        self.assertIn("$filter", params)
        self.assertIn("receivedDateTime ge 2026-04-01T00:00:00Z", params["$filter"])
        self.assertIn("receivedDateTime le 2026-04-30T23:59:59Z", params["$filter"])

    def test_text_and_date_filters_are_combined_with_and(self) -> None:
        #R020-T01: text and date filters combine with AND semantics.
        rows = [
            self._mk_message("in_range_match", sender="doordash@shop.com", received_at="2026-04-10T10:00:00Z"),
            self._mk_message("out_of_range_match", sender="doordash@shop.com", received_at="2026-05-10T10:00:00Z"),
            self._mk_message("in_range_no_match", sender="other@shop.com", received_at="2026-04-10T10:00:00Z"),
        ]
        ids = [
            m["message_id"]
            for m in self._search("sender:doordash from:2026-04-01 to:2026-04-30", rows)["messages"]
        ]
        self.assertEqual(ids, ["in_range_match"])

    def test_token_order_does_not_change_results(self) -> None:
        #R020-T01: token order does not change results.
        rows = [
            self._mk_message("x", subject="receipt", sender="doordash@shop.com"),
            self._mk_message("y", subject="receipt", sender="other@shop.com"),
        ]
        query_a = "subject:receipt sender:doordash"
        query_b = "sender:doordash subject:receipt"
        ids_a = [m["message_id"] for m in self._search(query_a, rows)["messages"]]
        ids_b = [m["message_id"] for m in self._search(query_b, rows)["messages"]]
        self.assertEqual(ids_a, ids_b)
        self.assertEqual(ids_a, ["x"])

    def test_matchy_scoped_query_shape_matches_expected_message(self) -> None:
        #R020-T01: scoped query shape matches only the expected message.
        target = self._mk_message(
            "target",
            subject="DoorDash order confirmation",
            sender="no-reply@doordash.com",
            body_content="Tacombi receipt total $76.08",
            received_at="2026-05-24T14:30:00Z",
        )
        wrong_merchant = self._mk_message(
            "wrong_merchant",
            subject="DoorDash order confirmation",
            sender="no-reply@doordash.com",
            body_content="Chopt receipt total $76.08",
            received_at="2026-05-24T14:30:00Z",
        )
        out_of_window = self._mk_message(
            "out_of_window",
            subject="DoorDash order confirmation",
            sender="no-reply@doordash.com",
            body_content="Tacombi receipt total $76.08",
            received_at="2025-01-10T14:30:00Z",
        )
        query = "subject:doordash body:tacombi from:2026-04-09 to:2026-07-08"
        criteria = api._parse_scoped_query(query)
        self.assertTrue(api._message_matches_criteria(target, criteria))
        self.assertFalse(api._message_matches_criteria(wrong_merchant, criteria))
        self.assertFalse(api._message_matches_criteria(out_of_window, criteria))

    def test_invalid_or_unscoped_tokens_return_400(self) -> None:
        #R020-T01: invalid or unscoped tokens return HTTP 400.
        with self.assertRaises(Exception) as unscoped_ctx:
            api.search_messages(query="doordash", limit=10)
        self.assertEqual(getattr(unscoped_ctx.exception, "status_code", None), 400)
        with self.assertRaises(Exception) as unsupported_ctx:
            api.search_messages(query="foo:bar", limit=10)
        self.assertEqual(getattr(unsupported_ctx.exception, "status_code", None), 400)

    def test_empty_query_returns_recent_mail(self) -> None:
        #R020: empty query returns recent mail without a Graph date filter.
        rows = [
            self._mk_message("newest", subject="Newest", received_at="2026-06-02T12:00:00Z"),
            self._mk_message("middle", subject="Middle", received_at="2026-06-01T12:00:00Z"),
            self._mk_message("older", subject="Older", received_at="2026-05-31T12:00:00Z"),
        ]
        with mock.patch.object(api, "_graph_get", return_value={"value": rows}) as graph_get:
            result = api.search_messages(query="   ", limit=2)
        _, kwargs = graph_get.call_args
        params = kwargs.get("params", {})
        self.assertEqual(params.get("$orderby"), "receivedDateTime DESC")
        self.assertEqual(params.get("$top"), "50")
        self.assertNotIn("$filter", params)
        self.assertEqual([msg["message_id"] for msg in result["messages"]], ["newest", "middle"])

    def test_search_paginates_for_older_date_windows(self) -> None:
        #R020-T01: search follows @odata.nextLink for older date windows.
        page_one = [self._mk_message("newer", received_at="2026-05-27T10:00:00Z")]
        page_two = [self._mk_message("older", received_at="2026-05-22T10:00:00Z")]
        with (
            mock.patch.object(
                api,
                "_graph_get",
                return_value={
                    "value": page_one,
                    "@odata.nextLink": "https://graph.microsoft.com/v1.0/me/messages?$skiptoken=abc123",
                },
            ) as graph_get,
            mock.patch.object(api, "_graph_get_next_link", return_value={"value": page_two}) as graph_get_next,
        ):
            result = api.search_messages(query="from:2026-05-20 to:2026-05-23", limit=10)
        graph_get.assert_called_once()
        graph_get_next.assert_called_once()
        self.assertEqual([item["message_id"] for item in result["messages"]], ["older"])


class GetMessageEndpointTests(unittest.TestCase):
    def test_get_message_returns_full_body_for_html(self) -> None:
        #R035-T01: single-message fetch returns html_body and recipients.
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
        #R035-T01: single-message fetch returns text_body for plain mail.
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
        #R035-T02: single-message fetch rejects blank ids with HTTP 400.
        with self.assertRaises(Exception) as ctx:
            api.get_message("   ")
        self.assertEqual(getattr(ctx.exception, "status_code", None), 400)


class GetMessageRoutingTests(unittest.TestCase):
    def test_get_message_route_is_registered(self) -> None:
        #R035-T01: /v1/messages/{message_id} route is registered.
        paths = {getattr(route, "path", None) for route in api.app.routes}
        self.assertIn("/v1/messages/{message_id}", paths)


class EndpointAuthContractTests(unittest.TestCase):
    def _route_for(self, path: str, method: str):
        #R035: Helper - resolve a registered route by path and method.
        for route in api.app.routes:
            if getattr(route, "path", None) != path:
                continue
            methods = getattr(route, "methods", set()) or set()
            if method in methods:
                return route
        self.fail(f"missing route: {method} {path}")

    def test_search_get_move_routes_require_write_token_dependency(self) -> None:
        #R620-T01: search/get/move routes declare caller write-token auth dependencies.
        for path, method in [
            ("/v1/messages/search", "GET"),
            ("/v1/messages/{message_id}", "GET"),
            ("/v1/messages/{message_id}/move", "POST"),
        ]:
            with self.subTest(path=path, method=method):
                route = self._route_for(path, method)
                dependant = getattr(route, "dependant", None)
                self.assertIsNotNone(dependant)
                dependencies = getattr(dependant, "dependencies", [])
                self.assertGreaterEqual(len(dependencies), 1)


class WriteTokenAuthTests(unittest.TestCase):
    def test_require_api_write_token_returns_503_when_server_token_missing(self) -> None:
        #R620-T01: route auth dependency fails closed when write token is unconfigured.
        with mock.patch.dict(api.os.environ, {"MAILCART_API_WRITE_TOKEN": "", "TELLER_CLASSIFIER_WRITE_TOKEN": ""}, clear=False):
            with self.assertRaises(Exception) as ctx:
                api._require_api_write_token(None)
        self.assertEqual(getattr(ctx.exception, "status_code", None), 503)

    def test_require_api_write_token_returns_401_on_invalid_token(self) -> None:
        #R620-T01: route auth dependency rejects invalid caller tokens.
        with mock.patch.dict(
            api.os.environ,
            {"MAILCART_API_WRITE_TOKEN": "expected-token", "TELLER_CLASSIFIER_WRITE_TOKEN": ""},
            clear=False,
        ):
            with self.assertRaises(Exception) as ctx:
                api._require_api_write_token("wrong-token")
        self.assertEqual(getattr(ctx.exception, "status_code", None), 401)

    def test_health_redacts_token_metadata_without_valid_write_token(self) -> None:
        #R029-T01: /health exposes token metadata only to authenticated callers.
        with (
            mock.patch.dict(
                api.os.environ,
                {"MAILCART_API_WRITE_TOKEN": "expected-token", "TELLER_CLASSIFIER_WRITE_TOKEN": ""},
                clear=False,
            ),
            mock.patch.object(api._TOKEN_MANAGER, "token_status", return_value={"token_status": "ok", "token_expires_at": "soon"}),
        ):
            unauth = api.health(None)
            authed = api.health("expected-token")
        self.assertEqual(unauth, {"status": "ok"})
        self.assertEqual(authed["status"], "ok")
        self.assertEqual(authed["token_status"], "ok")


class GraphRequestAuthTests(unittest.TestCase):
    def test_graph_request_retries_once_on_401_then_succeeds(self) -> None:
        #R027-T01: Graph request retries once after a 401, then succeeds.
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

    def test_graph_request_returns_empty_dict_for_no_content(self) -> None:
        #R030-T01: successful Graph responses with empty text yield {}.
        response = mock.Mock(status_code=204, text="")
        with (
            mock.patch.object(api, "_headers", return_value={"Authorization": "Bearer t"}),
            mock.patch.object(api.requests, "request", return_value=response),
        ):
            result = api._graph_request("GET", "/me/messages/msg_4")
        self.assertEqual(result, {})

    def test_graph_request_maps_not_found_variants_to_404(self) -> None:
        #R030-T01: Graph ItemNotFound/ResourceNotFound errors are mapped to HTTP 404.
        for status_code, body in [
            (404, "ItemNotFound"),
            (400, "ResourceNotFound"),
        ]:
            with self.subTest(status_code=status_code, body=body):
                response = mock.Mock(status_code=status_code, text=body)
                with (
                    mock.patch.object(api, "_headers", return_value={"Authorization": "Bearer t"}),
                    mock.patch.object(api.requests, "request", return_value=response),
                ):
                    with self.assertRaises(Exception) as ctx:
                        api._graph_request("GET", "/me/messages/msg_5")
                self.assertEqual(getattr(ctx.exception, "status_code", None), 404)


class GraphHelpersTests(unittest.TestCase):
    def test_is_auth_failure_matches_status_and_known_markers(self) -> None:
        #R600-T01: auth failure detector handles status 401 and known body markers.
        self.assertTrue(api._is_auth_failure(401, "anything"))
        self.assertTrue(api._is_auth_failure(500, "InvalidAuthenticationToken"))
        self.assertTrue(api._is_auth_failure(500, "authorization_identity_not_found"))
        self.assertTrue(api._is_auth_failure(500, "graph auth failed"))
        self.assertFalse(api._is_auth_failure(500, "plain server error"))

    def test_headers_raise_http_500_when_token_manager_fails(self) -> None:
        #R015-T01: header construction surfaces token-manager failures as HTTP 500.
        with mock.patch.object(api._TOKEN_MANAGER, "get_access_token", side_effect=api.GraphTokenError("missing")):
            with self.assertRaises(Exception) as ctx:
                api._headers()
        self.assertEqual(getattr(ctx.exception, "status_code", None), 500)

    def test_graph_get_next_link_rejects_unexpected_host(self) -> None:
        #R020-T01: pagination next-link host must match Graph host.
        with self.assertRaises(Exception) as ctx:
            api._graph_get_next_link("https://evil.example.com/v1.0/me/messages?$top=10")
        self.assertEqual(getattr(ctx.exception, "status_code", None), 502)

    def test_graph_get_next_link_strips_graph_base_path_and_forwards_params(self) -> None:
        #R020-T01: pagination helper strips base path and forwards parsed query params.
        next_link = "https://graph.microsoft.com/v1.0/me/messages?$top=10&$skiptoken=abc"
        with mock.patch.object(api, "_graph_get", return_value={"value": []}) as graph_get:
            api._graph_get_next_link(next_link)
        graph_get.assert_called_once_with("/me/messages", params={"$top": "10", "$skiptoken": "abc"})

    def test_parse_received_at_date_handles_blank_and_invalid(self) -> None:
        #R610-T01: receivedDateTime parser returns None for blank/invalid inputs.
        self.assertIsNone(api._parse_received_at_date(""))
        self.assertIsNone(api._parse_received_at_date("not-a-date"))
        self.assertIsNotNone(api._parse_received_at_date("2026-05-01T01:02:03Z"))

    def test_existing_server_health_helpers_handle_exceptions(self) -> None:
        #R040-T01: health probes return False on request exceptions.
        with mock.patch.object(api.requests, "get", side_effect=RuntimeError("boom")):
            self.assertFalse(api._existing_server_is_healthy("/tmp/cert.pem"))
            self.assertFalse(api._existing_http_server_is_healthy())


class RunServerEdgeCasesTests(unittest.TestCase):
    def test_run_server_exits_one_when_initial_token_resolution_fails(self) -> None:
        #R040-T01: startup exits non-zero when eager token resolution fails.
        with (
            mock.patch.dict(api.os.environ, {"OUTLOOK_GRAPH_CLIENT_ID": "cid"}, clear=False),
            mock.patch.object(api._TOKEN_MANAGER, "get_access_token", side_effect=api.GraphTokenError("bad token")),
        ):
            with self.assertRaises(SystemExit) as ctx:
                api.run_server()
        self.assertEqual(ctx.exception.code, 1)

    def test_run_server_reports_generic_port_conflict(self) -> None:
        #R040-T01: startup reports generic conflict when port is occupied by unknown process.
        with tempfile.TemporaryDirectory() as temp_dir:
            cert_path = Path(temp_dir) / "cert.pem"
            key_path = Path(temp_dir) / "key.pem"
            cert_path.write_text("cert", encoding="utf-8")
            key_path.write_text("key", encoding="utf-8")
            with (
                mock.patch.dict(
                    api.os.environ,
                    {
                        "OUTLOOK_GRAPH_CLIENT_ID": "",
                        api.TLS_CERT_ENV: str(cert_path),
                        api.TLS_KEY_ENV: str(key_path),
                    },
                    clear=False,
                ),
                mock.patch.object(api, "_is_port_in_use", return_value=True),
                mock.patch.object(api, "_existing_server_is_healthy", return_value=False),
                mock.patch.object(api, "_existing_http_server_is_healthy", return_value=False),
            ):
                with self.assertRaises(SystemExit) as ctx:
                    api.run_server()
        self.assertIn("already in use by another process", str(ctx.exception))

    def test_graph_request_returns_502_when_refresh_fails_after_401(self) -> None:
        #R027-T01: 401 with failed refresh surfaces HTTP 502.
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
        #R030-T01: persistent 401 surfaces a 502 auth-failed detail.
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
        #R035-T01: get_message percent-encodes reserved id characters.
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
        #R035-T01: get_message normalizes an already-encoded id.
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
        #R025-T01: move_message percent-encodes reserved id characters.
        with (
            mock.patch.object(api, "_get_or_create_folder_id", return_value="folder-1"),
            mock.patch.object(api, "_graph_post", return_value={"id": "moved-1"}) as graph_post,
        ):
            result = api.move_message("abc123==", api.MoveRequest(folder_name="matchy"))
        self.assertEqual(graph_post.call_args.args[0], "/me/messages/abc123%3D%3D/move")
        self.assertEqual(result["moved"], True)


class HttpsStartupTests(unittest.TestCase):
    def test_api_base_is_https_only(self) -> None:
        #R040-T01: API base URL is HTTPS-only.
        self.assertTrue(api.API_HTTPS_BASE.startswith("https://"))
        self.assertFalse(api.API_HTTPS_BASE.startswith("http://"))

    def test_resolve_tls_materials_rejects_missing_cert(self) -> None:
        #R045-T01: TLS resolution fails fast when the cert file is missing.
        with tempfile.TemporaryDirectory() as temp_dir:
            cert_path = Path(temp_dir) / "missing-cert.pem"
            key_path = Path(temp_dir) / "key.pem"
            key_path.write_text("key", encoding="utf-8")
            with mock.patch.dict(
                api.os.environ,
                {
                    api.TLS_CERT_ENV: str(cert_path),
                    api.TLS_KEY_ENV: str(key_path),
                },
                clear=False,
            ):
                with self.assertRaises(SystemExit) as ctx:
                    api._resolve_tls_materials()
        self.assertIn(api.TLS_CERT_ENV, str(ctx.exception))

    def test_run_server_uses_https_probe_for_existing_process(self) -> None:
        #R040-T01: startup reuses an existing healthy HTTPS process.
        with tempfile.TemporaryDirectory() as temp_dir:
            cert_path = Path(temp_dir) / "cert.pem"
            key_path = Path(temp_dir) / "key.pem"
            cert_path.write_text("cert", encoding="utf-8")
            key_path.write_text("key", encoding="utf-8")
            response = mock.Mock(status_code=200, text='{"status":"ok"}')
            with (
                mock.patch.dict(
                    api.os.environ,
                    {
                        "OUTLOOK_GRAPH_CLIENT_ID": "",
                        api.TLS_CERT_ENV: str(cert_path),
                        api.TLS_KEY_ENV: str(key_path),
                    },
                    clear=False,
                ),
                mock.patch.object(api, "_is_port_in_use", return_value=True),
                mock.patch.object(api.requests, "get", return_value=response) as get_mock,
            ):
                with self.assertRaises(SystemExit) as ctx:
                    api.run_server()
        self.assertEqual(ctx.exception.code, 0)
        get_mock.assert_called_once_with("https://127.0.0.1:8788/health", timeout=1.5, verify=str(cert_path))

    def test_run_server_starts_uvicorn_with_ssl_files(self) -> None:
        #R040-T01: startup launches uvicorn with ssl_certfile and ssl_keyfile.
        with tempfile.TemporaryDirectory() as temp_dir:
            cert_path = Path(temp_dir) / "cert.pem"
            key_path = Path(temp_dir) / "key.pem"
            cert_path.write_text("cert", encoding="utf-8")
            key_path.write_text("key", encoding="utf-8")
            with (
                mock.patch.dict(
                    api.os.environ,
                    {
                        "OUTLOOK_GRAPH_CLIENT_ID": "",
                        api.TLS_CERT_ENV: str(cert_path),
                        api.TLS_KEY_ENV: str(key_path),
                    },
                    clear=False,
                ),
                mock.patch.object(api, "_is_port_in_use", return_value=False),
                mock.patch.object(api.uvicorn, "run") as uvicorn_run,
            ):
                api.run_server()
        uvicorn_run.assert_called_once_with(
            api.app,
            host="127.0.0.1",
            port=8788,
            ssl_certfile=str(cert_path),
            ssl_keyfile=str(key_path),
        )

    def test_run_server_reports_legacy_http_process_conflict(self) -> None:
        #R040-T01: startup reports a legacy HTTP process conflict.
        with tempfile.TemporaryDirectory() as temp_dir:
            cert_path = Path(temp_dir) / "cert.pem"
            key_path = Path(temp_dir) / "key.pem"
            cert_path.write_text("cert", encoding="utf-8")
            key_path.write_text("key", encoding="utf-8")
            with (
                mock.patch.dict(
                    api.os.environ,
                    {
                        "OUTLOOK_GRAPH_CLIENT_ID": "",
                        api.TLS_CERT_ENV: str(cert_path),
                        api.TLS_KEY_ENV: str(key_path),
                    },
                    clear=False,
                ),
                mock.patch.object(api, "_is_port_in_use", return_value=True),
                mock.patch.object(api, "_existing_server_is_healthy", return_value=False),
                mock.patch.object(api, "_existing_http_server_is_healthy", return_value=True),
            ):
                with self.assertRaises(SystemExit) as ctx:
                    api.run_server()
        self.assertIn("legacy HTTP Mailcart API process", str(ctx.exception))


class AhoCorasickTests(unittest.TestCase):
    def test_search_reports_substring_patterns_in_single_pass(self) -> None:
        #R050-T01: Aho-Corasick reports all substring hits in one pass.
        matcher = api.AhoCorasick(["coffee", "order", "absent"])
        self.assertEqual(matcher.search("your coffee order is ready"), {"coffee", "order"})

    def test_search_detects_overlapping_suffix_patterns(self) -> None:
        #R050-T01: Aho-Corasick handles overlapping suffix patterns.
        matcher = api.AhoCorasick(["he", "she", "his", "hers"])
        self.assertEqual(matcher.search("ushers"), {"she", "he", "hers"})

    def test_empty_patterns_never_match(self) -> None:
        #R050-T01: empty patterns never match.
        matcher = api.AhoCorasick(["", "x"])
        self.assertEqual(matcher.search("anything"), set())

    def test_message_matches_criteria_uses_prebuilt_matcher_for_and_semantics(self) -> None:
        #R050-T01: prebuilt matcher preserves AND semantics.
        criteria = {
            "subject": ["receipt"],
            "sender": [],
            "body": ["doordash"],
            "from": None,
            "to": None,
        }
        matcher = api._build_criteria_matcher(criteria)
        match = {
            "subject": "Your Receipt",
            "from": {"emailAddress": {"address": "noreply@store.com"}},
            "body": {"contentType": "text", "content": "DoorDash order total"},
            "receivedDateTime": "2026-04-15T12:00:00Z",
        }
        miss = {
            "subject": "Your Receipt",
            "from": {"emailAddress": {"address": "noreply@store.com"}},
            "body": {"contentType": "text", "content": "unrelated body"},
            "receivedDateTime": "2026-04-15T12:00:00Z",
        }
        self.assertTrue(api._message_matches_criteria(match, criteria, matcher=matcher))
        self.assertFalse(api._message_matches_criteria(miss, criteria, matcher=matcher))

    def test_message_matches_criteria_builds_matcher_when_absent(self) -> None:
        #R050-T01: matcher is built on demand when absent.
        criteria = {"subject": [], "sender": ["doordash"], "body": [], "from": None, "to": None}
        match = {
            "subject": "x",
            "from": {"emailAddress": {"address": "orders@doordash.com"}},
            "body": {"contentType": "text", "content": ""},
            "receivedDateTime": "2026-04-15T12:00:00Z",
        }
        self.assertTrue(api._message_matches_criteria(match, criteria))

    def test_search_matches_naive_substring_scan_across_corpus(self) -> None:
        #R050-T01: Aho-Corasick matches a naive substring scan across a corpus.
        pattern_sets = [
            ["a", "ab", "bab", "bc", "bca", "c", "caa"],
            ["he", "she", "his", "hers"],
            ["aa", "aaa", "aaaa", "baaa"],
            ["abc", "bcd", "cde", "de"],
        ]
        for patterns in pattern_sets:
            matcher = api.AhoCorasick(patterns)
            for length in range(6):
                for chars in product("abcde", repeat=length):
                    text = "".join(chars)
                    expected = {pattern for pattern in patterns if pattern and pattern in text}
                    with self.subTest(patterns=tuple(patterns), text=text):
                        self.assertEqual(matcher.search(text), expected)


if __name__ == "__main__":
    unittest.main()
