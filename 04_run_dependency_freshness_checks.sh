#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R001: Resolve repo root from script path for deterministic relative references.
cd "$SCRIPT_DIR"

#R030: Allow report output directory override through DEPENDENCY_REPORT_DIR.
REPORT_DIR="${DEPENDENCY_REPORT_DIR:-./reports/dependency-freshness}"
FAIL_ON_MAJOR="${DEPENDENCY_FAIL_ON_MAJOR:-false}"
CLAMAV_DB_DIR="${CLAMAV_DB_DIR:-/opt/homebrew/var/lib/clamav}"
CLAMAV_SIGNATURE_MAX_AGE_HOURS="${CLAMAV_SIGNATURE_MAX_AGE_HOURS:-72}"

mkdir -p "$REPORT_DIR"

PROJECT_PYTHON="${DEPENDENCY_CHECK_PYTHON:-}"
#R005: Prefer active virtualenv interpreter, then local project venv, then system python.
if [[ -z "$PROJECT_PYTHON" ]]; then
  if [[ -n "${VIRTUAL_ENV:-}" ]] && [[ -x "${VIRTUAL_ENV}/bin/python" ]]; then
    PROJECT_PYTHON="${VIRTUAL_ENV}/bin/python"
  elif [[ -x "./$(basename "$PWD")-venv/bin/python" ]]; then
    PROJECT_PYTHON="./$(basename "$PWD")-venv/bin/python"
  else
    PROJECT_PYTHON="python3"
  fi
fi

if [[ ! -x "$PROJECT_PYTHON" ]] && [[ "$PROJECT_PYTHON" != "python3" ]]; then
  echo "❌ Project python not executable: $PROJECT_PYTHON"
  exit 1
fi

echo "▶ Running dependency freshness checks with ${PROJECT_PYTHON}"
#R010: Require requirements.txt for dependency freshness comparisons.
if [[ ! -f "./requirements.txt" ]]; then
  echo "❌ requirements.txt not found."
  exit 1
fi

#R040: Require ClamAV signatures to be fresh before reporting dependency freshness.
LATEST_CLAM_SIGNATURE_MTIME="$("$PROJECT_PYTHON" - "$CLAMAV_DB_DIR" <<'PY'
import pathlib
import sys

db_dir = pathlib.Path(sys.argv[1])
if not db_dir.is_dir():
    print("")
    raise SystemExit(0)

candidate_suffixes = (".cvd", ".cld", ".cud")
mtimes = []
for path in db_dir.iterdir():
    if path.is_file() and path.suffix.lower() in candidate_suffixes:
        mtimes.append(path.stat().st_mtime)

if not mtimes:
    print("")
    raise SystemExit(0)

print(int(max(mtimes)))
PY
)"

if [[ -z "$LATEST_CLAM_SIGNATURE_MTIME" ]]; then
  echo "❌ ClamAV signature files not found in ${CLAMAV_DB_DIR}."
  echo "   Refresh signatures with: freshclam --stdout"
  exit 1
fi

CLAM_SIGNATURE_AGE_HOURS="$("$PROJECT_PYTHON" - "$LATEST_CLAM_SIGNATURE_MTIME" <<'PY'
import time
import sys

signature_mtime = int(sys.argv[1])
age_hours = max(0, int((time.time() - signature_mtime) // 3600))
print(age_hours)
PY
)"

if (( CLAM_SIGNATURE_AGE_HOURS > CLAMAV_SIGNATURE_MAX_AGE_HOURS )); then
  echo "❌ ClamAV signatures are stale: ${CLAM_SIGNATURE_AGE_HOURS}h old (max ${CLAMAV_SIGNATURE_MAX_AGE_HOURS}h)."
  echo "   Refresh signatures with: freshclam --stdout"
  exit 1
fi

echo "✅ ClamAV signatures are fresh (${CLAM_SIGNATURE_AGE_HOURS}h old)."

#R045: Require Semgrep release freshness before dependency freshness reporting.
SEMGREP_BIN="$(dirname "$PROJECT_PYTHON")/semgrep"
if [[ ! -x "$SEMGREP_BIN" ]]; then
  SEMGREP_BIN="$(command -v semgrep 2>/dev/null || true)"
fi

if [[ -z "$SEMGREP_BIN" ]] || [[ ! -x "$SEMGREP_BIN" ]]; then
  echo "❌ semgrep not found (project venv or PATH)."
  exit 1
fi

CURRENT_SEMGREP_VERSION_RAW="$("$SEMGREP_BIN" show version 2>/dev/null || "$SEMGREP_BIN" --version 2>/dev/null || true)"
CURRENT_SEMGREP_VERSION_RAW="${CURRENT_SEMGREP_VERSION_RAW%%$'\n'*}"
CURRENT_SEMGREP_VERSION="${SEMGREP_CURRENT_VERSION:-$CURRENT_SEMGREP_VERSION_RAW}"
CURRENT_SEMGREP_VERSION="${CURRENT_SEMGREP_VERSION## }"
CURRENT_SEMGREP_VERSION="${CURRENT_SEMGREP_VERSION%% }"
if [[ -z "$CURRENT_SEMGREP_VERSION" ]]; then
  echo "❌ Unable to determine installed Semgrep version."
  exit 1
fi

LATEST_SEMGREP_VERSION="$("$PROJECT_PYTHON" - <<'PY'
import json
import os
import urllib.request

override = os.environ.get("SEMGREP_LATEST_VERSION", "").strip()
if override:
    print(override)
    raise SystemExit(0)

with urllib.request.urlopen("https://pypi.org/pypi/semgrep/json", timeout=10) as response:
    payload = json.loads(response.read().decode("utf-8"))
print(str(payload.get("info", {}).get("version", "")).strip())
PY
)"

if [[ -z "$LATEST_SEMGREP_VERSION" ]]; then
  echo "❌ Unable to determine latest available Semgrep version."
  exit 1
fi

if "$PROJECT_PYTHON" - "$CURRENT_SEMGREP_VERSION" "$LATEST_SEMGREP_VERSION" <<'PY'
import re
import sys

current = sys.argv[1].strip()
latest = sys.argv[2].strip()

def normalize(version: str):
    parts = []
    for token in re.split(r"[^0-9]+", version):
        if token:
            parts.append(int(token))
    return tuple(parts)

raise SystemExit(0 if normalize(latest) > normalize(current) else 1)
PY
then
  echo "❌ Semgrep is outdated: installed ${CURRENT_SEMGREP_VERSION}, latest ${LATEST_SEMGREP_VERSION}."
  echo "   Rerun ./01_install_prerequisites.sh to upgrade semgrep, then rerun this check."
  echo "   Active semgrep binary: ${SEMGREP_BIN}"
  exit 1
fi

echo "✅ Semgrep is fresh (installed ${CURRENT_SEMGREP_VERSION}, latest ${LATEST_SEMGREP_VERSION})."

OUTDATED_JSON="${REPORT_DIR}/dependency-freshness.json"
RAW_OUTDATED_JSON="${REPORT_DIR}/dependency-freshness-all.json"

#R015: Generate machine-readable outdated-package report through pip JSON output.
"$PROJECT_PYTHON" -m pip list --outdated --format=json > "$RAW_OUTDATED_JSON"

#R015: Scope outdated report to dependencies declared in requirements.txt.
"$PROJECT_PYTHON" - "$RAW_OUTDATED_JSON" "$OUTDATED_JSON" "./requirements.txt" <<'PY'
import json
import re
import sys
from pathlib import Path

raw_path = Path(sys.argv[1])
filtered_path = Path(sys.argv[2])
requirements_path = Path(sys.argv[3])

rows = json.loads(raw_path.read_text(encoding="utf-8") or "[]")
required_names = set()
for raw_line in requirements_path.read_text(encoding="utf-8").splitlines():
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    line = line.split("#", 1)[0].strip()
    line = line.split(";", 1)[0].strip()
    name = re.split(r"(==|>=|<=|~=|!=|>|<)", line, maxsplit=1)[0].strip().lower()
    if name:
        required_names.add(name)

filtered_rows = [row for row in rows if str(row.get("name", "")).strip().lower() in required_names]
filtered_path.write_text(json.dumps(filtered_rows, indent=2), encoding="utf-8")
PY

#R020: Generate human-readable dependency freshness summary and print inline output.
"$PROJECT_PYTHON" - "$OUTDATED_JSON" <<'PY'
import json
import sys
from pathlib import Path

json_path = Path(sys.argv[1])
rows = json.loads(json_path.read_text(encoding="utf-8") or "[]")
if not rows:
    print("All installed Python dependencies are up to date.")
    raise SystemExit(0)

rows = sorted(rows, key=lambda item: str(item.get("name", "")).lower())
print(f"Outdated packages: {len(rows)}")
for row in rows:
    print(f"- {row.get('name', '<unknown>')}: {row.get('version', '?')} -> {row.get('latest_version', '?')}")
PY

#R035: Count outdated dependencies to enforce failure on any stale package.
OUTDATED_COUNT="$("$PROJECT_PYTHON" - "$OUTDATED_JSON" <<'PY'
import json
import sys
from pathlib import Path

rows = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8") or "[]")
print(len(rows))
PY
)"

#R025: Optionally emit major-version diagnostics for outdated packages.
if [[ "$FAIL_ON_MAJOR" == "true" ]]; then
  "$PROJECT_PYTHON" - "$OUTDATED_JSON" <<'PY'
import json
import re
import sys
from pathlib import Path

def major(version: str) -> int:
    match = re.match(r"^\s*(\d+)", str(version))
    if not match:
        return 0
    return int(match.group(1))

rows = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8") or "[]")
for row in rows:
    current = major(row.get("version", "0"))
    latest = major(row.get("latest_version", "0"))
    if latest > current:
        print(
            f"❌ Major update detected: {row.get('name', '<unknown>')} "
            f"{row.get('version', '?')} -> {row.get('latest_version', '?')}"
        )
        raise SystemExit(1)
print("✅ No major-version updates detected.")
PY
fi

#R035: Fail script when outdated dependencies exist to avoid green status on stale packages.
if [[ "$OUTDATED_COUNT" -gt 0 ]]; then
  echo "❌ Dependency freshness check failed: ${OUTDATED_COUNT} outdated package(s) found."
  echo "   - json: ${OUTDATED_JSON}"
  exit 1
fi

echo "✅ Dependency freshness checks completed."
echo "   - json: ${OUTDATED_JSON}"
#R050: Advise next step after a green dependency freshness run.
echo "➡️  Next step: run \`make\`."
