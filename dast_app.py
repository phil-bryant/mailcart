#!/usr/bin/env python3
"""DAST entrypoint: serve mailcart FastAPI app over TLS."""
from __future__ import annotations

import os
from pathlib import Path
import sys

import uvicorn


def _resolve(names: list[str], default: str) -> str:
    for name in names:
        value = os.environ.get(name, "").strip()
        if value:
            return value
    return default


def main() -> None:
    home_certs = Path.home() / ".teller"
    host = _resolve(
        [
            "CLASSIFICATION_API_HOST",
            "CLASSY_API_HOST",
            "TELLER_CLASSIFIER_API_HOST",
            "MATCHY_API_HOST",
        ],
        "127.0.0.1",
    )
    port = int(
        _resolve(
            [
                "CLASSIFICATION_API_PORT",
                "CLASSY_API_PORT",
                "TELLER_CLASSIFIER_API_PORT",
                "MATCHY_API_PORT",
            ],
            "8788",
        )
    )
    cert = _resolve(
        ["TELLER_CLASSIFIER_TLS_CERT_FILE", "MATCHY_API_TLS_CERT_FILE"],
        str(home_certs / "classifier-localhost-cert.pem"),
    )
    key = _resolve(
        ["TELLER_CLASSIFIER_TLS_KEY_FILE", "MATCHY_API_TLS_KEY_FILE"],
        str(home_certs / "classifier-localhost-key.pem"),
    )

    scripts_dir = Path(__file__).resolve().parent / "scripts"
    sys.path.insert(0, str(scripts_dir))
    import matchy_mailcart_api as api  # noqa: PLC0415

    uvicorn.run(api.app, host=host, port=port, ssl_certfile=cert, ssl_keyfile=key, log_level="warning")


if __name__ == "__main__":
    main()
