#!/usr/bin/env python3
"""Refresh the shared Microsoft Graph OAuth token cache."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from graph_token import GraphTokenError, get_manager  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Refresh Mailcart Graph OAuth token cache.")
    parser.add_argument("--force", action="store_true", help="Refresh even when the cached token is still valid.")
    args = parser.parse_args()

    manager = get_manager()
    try:
        if args.force:
            manager.invalidate()
            session = manager.load()
            manager.refresh(force=True, session=session)
        else:
            manager.get_access_token()
    except GraphTokenError as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
