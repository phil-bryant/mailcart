#!/usr/bin/env bats

setup() {
  export REPO_ROOT="/Users/phil/local/src/mailcart"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export FIXTURE_ROOT="${TMP_ROOT}/fixture"
  export STUB_BIN="${TMP_ROOT}/bin"
  export CALLS_LOG="${TMP_ROOT}/calls.log"
  mkdir -p "${FIXTURE_ROOT}" "${STUB_BIN}"
  : > "${CALLS_LOG}"
  cp "${REPO_ROOT}/03_load_requirements.sh" "${FIXTURE_ROOT}/03_load_requirements.sh"
  chmod +x "${FIXTURE_ROOT}/03_load_requirements.sh"
}

teardown() {
  rm -rf "${TMP_ROOT}"
}

@test "fails when expected venv directory is missing" {
  #R001 #R005 #R010
  run bash -c "cd '${FIXTURE_ROOT}' && ./03_load_requirements.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Virtual environment not found"* ]]
  [[ "$output" == *"02_create_venv.sh"* ]]
}

@test "fails when no virtual environment is active" {
  #R015
  mkdir -p "${FIXTURE_ROOT}/fixture-venv/bin"
  run bash -c "cd '${FIXTURE_ROOT}' && unset VIRTUAL_ENV && ./03_load_requirements.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No virtual environment is currently active"* ]]
  [[ "$output" == *"activate"* ]]
}

@test "fails when active venv does not match project venv" {
  #R020
  mkdir -p "${FIXTURE_ROOT}/fixture-venv" "${TMP_ROOT}/other-venv"
  run bash -c "cd '${FIXTURE_ROOT}' && export VIRTUAL_ENV='${TMP_ROOT}/other-venv' && ./03_load_requirements.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match project venv"* ]]
}

@test "prefers requirements.txt and installs with venv python" {
  #R025 #R035
  local venv
  venv="${FIXTURE_ROOT}/fixture-venv"
  mkdir -p "${venv}/bin"
  echo "requests==2.0.0" > "${FIXTURE_ROOT}/requirements.txt"
  cat > "${venv}/bin/python" <<EOF
#!/bin/bash
echo "python \$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${venv}/bin/python"

  run bash -c "cd '${FIXTURE_ROOT}' && export VIRTUAL_ENV='${venv}' && ./03_load_requirements.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"requirements.txt"* ]]
  run rg "^python -m pip install --upgrade pip$" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
  run rg "^python -m pip install -r requirements.txt$" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
}

@test "requires cpu or gpu selector with split requirements files" {
  #R030
  local venv
  venv="${FIXTURE_ROOT}/fixture-venv"
  mkdir -p "${venv}/bin"
  echo "ok" > "${FIXTURE_ROOT}/requirements-cpu.txt"
  echo "ok" > "${FIXTURE_ROOT}/requirements-gpu.txt"
  cat > "${venv}/bin/python" <<EOF
#!/bin/bash
echo "python \$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${venv}/bin/python"

  run bash -c "cd '${FIXTURE_ROOT}' && export VIRTUAL_ENV='${venv}' && ./03_load_requirements.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing cpu/gpu selector"* ]]

  run bash -c "cd '${FIXTURE_ROOT}' && export VIRTUAL_ENV='${venv}' && ./03_load_requirements.sh no"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid selector"* ]]

  run bash -c "cd '${FIXTURE_ROOT}' && export VIRTUAL_ENV='${venv}' && ./03_load_requirements.sh cpu"
  [ "$status" -eq 0 ]
  run rg "^python -m pip install -r requirements-cpu.txt$" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
}
