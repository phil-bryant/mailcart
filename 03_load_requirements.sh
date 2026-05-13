#!/usr/bin/env bash
umask 007
#R001: Use strict mode to fail fast on dependency setup errors.
set -euo pipefail

CURRENT_DIRECTORY_NAME="$(basename "$(pwd)")"
#R005: Resolve project venv name from current directory basename.
VENV_DIR="${CURRENT_DIRECTORY_NAME}-venv"

#R010: Require the expected local project virtual environment directory.
if [ ! -d "$VENV_DIR" ]; then
    echo "❌ ERROR: Virtual environment not found."
    echo "Run ./02_create_venv.sh first to create: $VENV_DIR"
    exit 1
fi

#R015: Require an active virtual environment before package installation.
if [ -z "${VIRTUAL_ENV:-}" ]; then
    echo "❌ ERROR: No virtual environment is currently active."
    echo "Run: activate"
    exit 1
fi

EXPECTED_VENV_PATH="$(cd "$VENV_DIR" && pwd -P)"
CURRENT_VENV_PATH="$(cd "$VIRTUAL_ENV" && pwd -P 2>/dev/null || echo "$VIRTUAL_ENV")"
#R020: Require active virtual environment to match this project's expected venv.
if [ "$CURRENT_VENV_PATH" != "$EXPECTED_VENV_PATH" ]; then
    echo "❌ ERROR: Active virtual environment does not match project venv."
    echo "Expected: $EXPECTED_VENV_PATH"
    echo "Current:  $CURRENT_VENV_PATH"
    exit 1
fi

usage() {
    echo "Usage: $0 {cpu|gpu}"
    exit 1
}

REQUIREMENTS_FILE=""
#R025: Prefer requirements.txt over split cpu/gpu requirements files.
if [ -f "requirements.txt" ]; then
    REQUIREMENTS_FILE="requirements.txt"
elif [ -f "requirements-cpu.txt" ] || [ -f "requirements-gpu.txt" ]; then
    #R030: Require one valid cpu/gpu selector argument for split requirements files.
    if [ "$#" -ne 1 ]; then
        echo "❌ ERROR: Missing cpu/gpu selector."
        usage
    fi
    case "$1" in
        cpu) REQUIREMENTS_FILE="requirements-cpu.txt" ;;
        gpu) REQUIREMENTS_FILE="requirements-gpu.txt" ;;
        *)
            echo "❌ ERROR: Invalid selector: $1"
            usage
            ;;
    esac
else
    echo "❌ ERROR: No requirements file found."
    exit 1
fi

if [ ! -f "$REQUIREMENTS_FILE" ]; then
    echo "❌ ERROR: Requirements file not found: $REQUIREMENTS_FILE"
    exit 1
fi

PYTHON_BIN="${VIRTUAL_ENV}/bin/python"
if [ ! -x "$PYTHON_BIN" ]; then
    echo "❌ ERROR: Active virtualenv python not executable: $PYTHON_BIN"
    exit 1
fi

echo "Installing requirements from ${REQUIREMENTS_FILE}"
#R035: Upgrade pip and install selected requirements with active virtualenv python.
"$PYTHON_BIN" -m pip install --upgrade pip
"$PYTHON_BIN" -m pip install -r "$REQUIREMENTS_FILE"