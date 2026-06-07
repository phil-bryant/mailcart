#!/usr/bin/env python3
"""Unit tests for refresh_graph_token CLI."""

from __future__ import annotations

import io
import sys
import unittest
from pathlib import Path
from unittest import mock

def _resolve_scripts_dir(module_filename: str) -> Path:
    # Keep imports stable when tests are copied under artifacts/mutation/mutants.
    probe_roots = [Path.cwd().resolve(), *Path(__file__).resolve().parents]
    for root in probe_roots:
        candidate = root / "scripts"
        if (candidate / module_filename).is_file():
            return candidate
    return Path(__file__).resolve().parents[2] / "scripts"


sys.path.insert(0, str(_resolve_scripts_dir("refresh_graph_token.py")))

import refresh_graph_token as cli  # noqa: E402


class RefreshGraphTokenCliTests(unittest.TestCase):
    def test_main_without_force_uses_existing_access_token(self) -> None:
        #R001-T01: default CLI path validates token without forcing refresh.
        manager = mock.Mock()
        with (
            mock.patch.object(cli, "get_manager", return_value=manager),
            mock.patch.object(sys, "argv", ["refresh_graph_token.py"]),
        ):
            rc = cli.main()
        self.assertEqual(rc, 0)
        manager.get_access_token.assert_called_once_with()
        manager.invalidate.assert_not_called()
        manager.refresh.assert_not_called()

    def test_main_force_invalidates_and_refreshes(self) -> None:
        #R001-T01: --force invalidates then refreshes session.
        manager = mock.Mock()
        manager.load.return_value = object()
        with (
            mock.patch.object(cli, "get_manager", return_value=manager),
            mock.patch.object(sys, "argv", ["refresh_graph_token.py", "--force"]),
        ):
            rc = cli.main()
        self.assertEqual(rc, 0)
        manager.invalidate.assert_called_once_with()
        manager.load.assert_called_once_with()
        manager.refresh.assert_called_once()
        args, kwargs = manager.refresh.call_args
        self.assertEqual(kwargs.get("force"), True)
        self.assertIs(kwargs.get("session"), manager.load.return_value)

    def test_main_surfaces_graph_token_errors(self) -> None:
        #R005-T01: token errors are emitted to stderr and return non-zero.
        manager = mock.Mock()
        manager.get_access_token.side_effect = cli.GraphTokenError("broken token")
        stderr = io.StringIO()
        with (
            mock.patch.object(cli, "get_manager", return_value=manager),
            mock.patch.object(sys, "argv", ["refresh_graph_token.py"]),
            mock.patch("sys.stderr", stderr),
        ):
            rc = cli.main()
        self.assertEqual(rc, 1)
        self.assertIn("broken token", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
