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
  cp "${REPO_ROOT}/04_run_dependency_freshness_checks.sh" "${FIXTURE_ROOT}/04_run_dependency_freshness_checks.sh"
  chmod +x "${FIXTURE_ROOT}/04_run_dependency_freshness_checks.sh"
  mkdir -p "${FIXTURE_ROOT}/clamav-db"
  : > "${FIXTURE_ROOT}/clamav-db/main.cvd"
  cat > "${FIXTURE_ROOT}/requirements.txt" <<'EOF'
requests==2.33.1
fastapi==0.136.1
EOF
}

teardown() {
  rm -rf "${TMP_ROOT}"
}

create_python_stub() {
  cat > "${STUB_BIN}/python-stub" <<EOF
#!/bin/bash
echo "python \$*" >> "${CALLS_LOG}"
if [ "\$1" = "-m" ] && [ "\$2" = "pip" ] && [ "\$3" = "list" ] && [ "\$4" = "--outdated" ] && [ "\$5" = "--format=json" ]; then
  if [ "\${PYTHON_STUB_MODE:-normal}" = "major" ]; then
    echo '[{"name":"requests","version":"1.0.0","latest_version":"2.0.0"}]'
  elif [ "\${PYTHON_STUB_MODE:-normal}" = "tooling-only" ]; then
    echo '[{"name":"mcp","version":"1.0.0","latest_version":"2.0.0"}]'
  elif [ "\${PYTHON_STUB_MODE:-normal}" = "none" ]; then
    echo '[]'
  else
    echo '[{"name":"requests","version":"2.33.1","latest_version":"2.34.0"}]'
  fi
  exit 0
fi
if [ "\$1" = "-" ]; then
  /usr/bin/python3 "\$@"
  exit \$?
fi
echo "unexpected call" >&2
exit 1
EOF
  chmod +x "${STUB_BIN}/python-stub"
}

create_semgrep_stub() {
  cat > "${STUB_BIN}/semgrep" <<'EOF'
#!/bin/bash
if [ "$1" = "show" ] && [ "$2" = "version" ]; then
  echo "${SEMGREP_STUB_CURRENT_VERSION:-1.157.0}"
  exit 0
fi
if [ "$1" = "--version" ]; then
  echo "${SEMGREP_STUB_CURRENT_VERSION:-1.157.0}"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/semgrep"
}

@test "fails when outdated packages are detected and still writes artifacts" {
  #R001 #R005 #R010 #R015 #R020 #R035 #R040 #R045
  create_python_stub
  create_semgrep_stub
  run bash -c "cd '${TMP_ROOT}' && PATH='${STUB_BIN}:/usr/bin:/bin' CLAMAV_DB_DIR='${FIXTURE_ROOT}/clamav-db' SEMGREP_LATEST_VERSION='1.157.0' DEPENDENCY_CHECK_PYTHON='${STUB_BIN}/python-stub' '${FIXTURE_ROOT}/04_run_dependency_freshness_checks.sh'"
  freshness_output="${output}"
  [ "$status" -eq 1 ]
  [ -f "${FIXTURE_ROOT}/reports/dependency-freshness/dependency-freshness.json" ]
  [ ! -f "${FIXTURE_ROOT}/reports/dependency-freshness/dependency-freshness.txt" ]
  [[ "$freshness_output" == *"Outdated packages: 1"* ]]
  [[ "$freshness_output" == *"requests: 2.33.1 -> 2.34.0"* ]]
  [[ "$freshness_output" == *"Dependency freshness check failed"* ]]
}

@test "fails fast for non-executable explicit interpreter path" {
  #R005
  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON=./missing-python ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Project python not executable"* ]]
}

@test "fails when requirements.txt is missing" {
  #R010
  create_python_stub
  rm -f "${FIXTURE_ROOT}/requirements.txt"
  run bash -c "cd '${FIXTURE_ROOT}' && DEPENDENCY_CHECK_PYTHON='${STUB_BIN}/python-stub' ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"requirements.txt not found"* ]]
}

@test "fails on major updates when gate is enabled" {
  #R025 #R035 #R040 #R045
  create_python_stub
  create_semgrep_stub
  run bash -c "cd '${FIXTURE_ROOT}' && PATH='${STUB_BIN}:/usr/bin:/bin' CLAMAV_DB_DIR='${FIXTURE_ROOT}/clamav-db' SEMGREP_LATEST_VERSION='1.157.0' PYTHON_STUB_MODE=major DEPENDENCY_CHECK_PYTHON='${STUB_BIN}/python-stub' DEPENDENCY_FAIL_ON_MAJOR=true ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Major update detected"* ]]
}

@test "uses custom dependency report directory when configured" {
  #R030 #R040 #R045
  create_python_stub
  create_semgrep_stub
  run bash -c "cd '${FIXTURE_ROOT}' && PATH='${STUB_BIN}:/usr/bin:/bin' CLAMAV_DB_DIR='${FIXTURE_ROOT}/clamav-db' SEMGREP_LATEST_VERSION='1.157.0' PYTHON_STUB_MODE=none DEPENDENCY_CHECK_PYTHON='${STUB_BIN}/python-stub' DEPENDENCY_REPORT_DIR='./tmp-reports' ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/tmp-reports/dependency-freshness.json" ]
  [ ! -f "${FIXTURE_ROOT}/tmp-reports/dependency-freshness.txt" ]
}

@test "passes when no outdated packages are found" {
  #R035 #R040 #R045 #R050
  create_python_stub
  create_semgrep_stub
  run bash -c "cd '${FIXTURE_ROOT}' && PATH='${STUB_BIN}:/usr/bin:/bin' CLAMAV_DB_DIR='${FIXTURE_ROOT}/clamav-db' SEMGREP_LATEST_VERSION='1.157.0' PYTHON_STUB_MODE=none DEPENDENCY_CHECK_PYTHON='${STUB_BIN}/python-stub' ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ClamAV signatures are fresh"* ]]
  [[ "$output" == *"Semgrep is fresh"* ]]
  [[ "$output" == *"Dependency freshness checks completed."* ]]
  [[ "$output" == *"Next step: run \`make\`."* ]]
}

@test "passes when only non-project tooling packages are outdated" {
  #R015 #R035
  create_python_stub
  create_semgrep_stub
  run bash -c "cd '${FIXTURE_ROOT}' && PATH='${STUB_BIN}:/usr/bin:/bin' CLAMAV_DB_DIR='${FIXTURE_ROOT}/clamav-db' SEMGREP_LATEST_VERSION='1.157.0' PYTHON_STUB_MODE=tooling-only DEPENDENCY_CHECK_PYTHON='${STUB_BIN}/python-stub' ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All installed Python dependencies are up to date."* ]]
  [[ "$output" == *"Dependency freshness checks completed."* ]]
}

@test "fails when ClamAV signatures are stale" {
  #R040
  create_python_stub
  create_semgrep_stub
  touch -t 200001010000 "${FIXTURE_ROOT}/clamav-db/main.cvd"
  run bash -c "cd '${FIXTURE_ROOT}' && PATH='${STUB_BIN}:/usr/bin:/bin' CLAMAV_DB_DIR='${FIXTURE_ROOT}/clamav-db' CLAMAV_SIGNATURE_MAX_AGE_HOURS=1 PYTHON_STUB_MODE=none DEPENDENCY_CHECK_PYTHON='${STUB_BIN}/python-stub' ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ClamAV signatures are stale"* ]]
  [[ "$output" == *"freshclam --stdout"* ]]
}

@test "fails when a newer semgrep version is available" {
  #R045
  create_python_stub
  create_semgrep_stub
  run bash -c "cd '${FIXTURE_ROOT}' && PATH='${STUB_BIN}:/usr/bin:/bin' CLAMAV_DB_DIR='${FIXTURE_ROOT}/clamav-db' SEMGREP_STUB_CURRENT_VERSION='1.157.0' SEMGREP_LATEST_VERSION='1.158.0' PYTHON_STUB_MODE=none DEPENDENCY_CHECK_PYTHON='${STUB_BIN}/python-stub' ./04_run_dependency_freshness_checks.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Semgrep is outdated"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}
