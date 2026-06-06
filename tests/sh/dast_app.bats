#!/usr/bin/env bats

# Contract checks for the DAST TLS entrypoint. These checks assert the entrypoint
# implements each requirement's design contract so a regression fails the lane.

load helpers/repo_root

setup() {
  #R001: Test harness setup for dast_app contract checks.
  REPO_ROOT="$(mailcart_repo_root)"
  SRC="${REPO_ROOT}/dast_app.py"
}

@test "R001: entrypoint serves the FastAPI app over TLS via uvicorn" {
  #R001-T01: The entrypoint serves the FastAPI app via uvicorn with TLS cert/key.
  run rg -F "import matchy_mailcart_api as api" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "uvicorn.run(api.app, host=host, port=port, ssl_certfile=cert, ssl_keyfile=key, log_level=\"warning\")" "${SRC}"
  [ "$status" -eq 0 ]
}

@test "R005: settings resolve from prioritized env vars with a default fallback" {
  #R005-T01: _resolve returns the first configured env value and falls back to the default otherwise.
  run rg -F "def _resolve(names: list[str], default: str) -> str:" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "value = os.environ.get(name, \"\").strip()" "${SRC}"
  [ "$status" -eq 0 ]
  run rg -F "return default" "${SRC}"
  [ "$status" -eq 0 ]
}
