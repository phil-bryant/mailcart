#!/usr/bin/env bats

setup() {
  export REPO_ROOT="/Users/phil/local/src/mailcart"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export FIXTURE_ROOT="${TMP_ROOT}/fixture"
  export STUB_BIN="${TMP_ROOT}/bin"
  mkdir -p "${FIXTURE_ROOT}" "${STUB_BIN}"
  cp "${REPO_ROOT}/02_create_venv.sh" "${FIXTURE_ROOT}/02_create_venv.sh"
  chmod +x "${FIXTURE_ROOT}/02_create_venv.sh"
}

teardown() {
  rm -rf "${TMP_ROOT}"
}

@test "fails when sibling prerequisites script is missing" {
  #R001 #R005
  run env PATH="${STUB_BIN}:/usr/bin:/bin" VIRTUAL_ENV="" bash -c "cd '${FIXTURE_ROOT}' && ./02_create_venv.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Prerequisites script not found"* ]]
}

@test "prefers python3.12 when both interpreters exist" {
  #R010 #R035
  touch "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  cat > "${STUB_BIN}/python3.12" <<'EOF'
#!/bin/bash
if [ "$1" = "-m" ] && [ "$2" = "venv" ]; then
  mkdir -p "$3/bin"
  touch "$3/bin/activate"
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/python3.12"
  cat > "${STUB_BIN}/python3" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/python3"

  run env PATH="${STUB_BIN}:/usr/bin:/bin" VIRTUAL_ENV="" bash -c "cd '${FIXTURE_ROOT}' && ./02_create_venv.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Created virtual environment"* ]]
  [ -f "${FIXTURE_ROOT}/fixture-venv/bin/activate" ]
}

@test "fails when neither python3.12 nor python3 exists on PATH" {
  #R015
  touch "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  run env PATH="${STUB_BIN}" VIRTUAL_ENV="" /bin/bash -c "cd '${FIXTURE_ROOT}' && ./02_create_venv.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No suitable Python interpreter found"* ]]
}

@test "refuses to run while another virtualenv is active" {
  #R025
  touch "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  cat > "${STUB_BIN}/python3" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/python3"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" VIRTUAL_ENV="/tmp/other-venv" bash -c "cd '${FIXTURE_ROOT}' && ./02_create_venv.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"A virtual environment is currently active"* ]]
}

@test "returns success without recreating existing venv directory" {
  #R020 #R030 #R040
  touch "${FIXTURE_ROOT}/01_install_prerequisites.sh"
  mkdir -p "${FIXTURE_ROOT}/fixture-venv/bin"
  touch "${FIXTURE_ROOT}/fixture-venv/bin/activate"
  cat > "${STUB_BIN}/python3" <<'EOF'
#!/bin/bash
echo "unexpected-python-call"
exit 1
EOF
  chmod +x "${STUB_BIN}/python3"

  run env PATH="${STUB_BIN}:/usr/bin:/bin" VIRTUAL_ENV="" bash -c "cd '${FIXTURE_ROOT}' && ./02_create_venv.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Virtual environment already exists"* ]]
  [[ "$output" == *"activate"* ]]
}
