#!/usr/bin/env python3
"""Property-based fuzz tests for matchy_mailcart_api helpers."""

from __future__ import annotations

from pathlib import Path
import string
import sys

from hypothesis import given
from hypothesis import strategies as st

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

import matchy_mailcart_api as api  # noqa: E402


ALNUM = string.ascii_letters + string.digits


@given(st.text())
def test_normalize_search_text_matches_reference_impl(raw: str) -> None:
    #R020: _normalize_search_text matches the reference normalization.
    assert api._normalize_search_text(raw) == " ".join(raw.split()).casefold()


@given(st.text(alphabet=ALNUM, min_size=1, max_size=16))
def test_parse_scoped_query_normalizes_subject_value(value: str) -> None:
    #R020: _parse_scoped_query normalizes subject values.
    parsed = api._parse_scoped_query(f"subject:{value}")
    assert parsed["subject"] == [api._normalize_search_text(value)]


@given(st.text(alphabet=ALNUM, min_size=1, max_size=16))
def test_message_matching_subject_is_case_insensitive(value: str) -> None:
    #R020: subject matching is case-insensitive.
    normalized = api._normalize_search_text(value)
    criteria = {
        "subject": [normalized],
        "sender": [],
        "body": [],
        "from": None,
        "to": None,
    }
    message = {
        "subject": value.swapcase(),
        "from": {"emailAddress": {"address": "sender@example.com"}},
        "body": {"contentType": "text", "content": "body"},
        "receivedDateTime": "2026-06-03T12:00:00Z",
    }
    assert api._message_matches_criteria(message, criteria)


@given(
    st.text(alphabet=ALNUM, min_size=1, max_size=8),
    st.text(alphabet=ALNUM, min_size=1, max_size=8),
)
def test_aho_corasick_finds_inserted_terms(term_a: str, term_b: str) -> None:
    #R050: Aho-Corasick finds inserted terms.
    matcher = api.AhoCorasick([term_a, term_b])
    hits = matcher.search(f"prefix {term_a} middle {term_b} suffix")
    assert term_a in hits
    assert term_b in hits
