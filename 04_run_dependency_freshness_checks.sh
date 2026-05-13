#!/usr/bin/env bash
umask 007
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R001: Resolve repo root from script path for deterministic relative references.
cd "$SCRIPT_DIR"

#R030: Allow report output directory override through DEPENDENCY_REPORT_DIR.
REPORT_DIR="${DEPENDENCY_REPORT_DIR:-./reports/dependency-freshness}"
FAIL_ON_MAJOR="${DEPENDENCY_FAIL_ON_MAJOR:-false}"

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

OUTDATED_JSON="${REPORT_DIR}/dependency-freshness.json"

#R015: Generate machine-readable outdated-package report through pip JSON output.
"$PROJECT_PYTHON" -m pip list --outdated --format=json > "$OUTDATED_JSON"

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
