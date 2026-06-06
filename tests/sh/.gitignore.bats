#!/usr/bin/env bats

load helpers/repo_root

setup() {
  REPO_ROOT="$(mailcart_repo_root)"
  GITIGNORE="${REPO_ROOT}/.gitignore"
}

@test "R001: local build output under .build/ is git-ignored" {
  #R001
  run git -C "${REPO_ROOT}" check-ignore -q ".build/outlook_integration_test"
  [ "$status" -eq 0 ]
}

@test "R005: Xcode DerivedData and user-specific metadata are git-ignored" {
  #R005
  run git -C "${REPO_ROOT}" check-ignore -q "DerivedData/Build/x"
  [ "$status" -eq 0 ]
  run git -C "${REPO_ROOT}" check-ignore -q "macos_app/UserData.xcuserstate"
  [ "$status" -eq 0 ]
  run git -C "${REPO_ROOT}" check-ignore -q "macos_app/foo.xcuserdatad/x"
  [ "$status" -eq 0 ]
}

@test "R010: project source and shared project configuration stay tracked (not ignored)" {
  #R010
  run git -C "${REPO_ROOT}" check-ignore -q "macos_app/UI/OutlookMailApp.swift"
  [ "$status" -ne 0 ]
  run git -C "${REPO_ROOT}" check-ignore -q "macos_app/OutlookMailApp.xcodeproj/project.pbxproj"
  [ "$status" -ne 0 ]
}

@test "R015: cached-removal cleanup invariant is documented (operational git procedure)" {
  #R015
  skip "R015 is an operational cleanup procedure (git rm -r --cached) that mutates the index; running it in a unit test would stage deletions. The post-cleanup invariant (ignored artifact paths stay untracked) is behaviorally enforced by R020."
}

@test "R020: ignored build artifact paths are not tracked in the index" {
  #R020
  run git -C "${REPO_ROOT}" ls-files ".build/"
  [ "$status" -eq 0 ]
  [ -z "${output}" ]
}

@test "R025: local virtualenv directories are git-ignored" {
  #R025
  run git -C "${REPO_ROOT}" check-ignore -q ".venv/lib/x"
  [ "$status" -eq 0 ]
  run git -C "${REPO_ROOT}" check-ignore -q "mailcart-venv/bin/python"
  [ "$status" -eq 0 ]
}

@test "R030: generated dependency freshness reports are git-ignored" {
  #R030
  run git -C "${REPO_ROOT}" check-ignore -q "reports/dependency-freshness/report.txt"
  [ "$status" -eq 0 ]
}

@test "R035: .gitignore excludes default profiler artifact" {
  #R035
  run rg '^default\.profraw$' "${GITIGNORE}"
  [ "$status" -eq 0 ]
  run git -C "${REPO_ROOT}" check-ignore -q "default.profraw"
  [ "$status" -eq 0 ]
}

@test "R040: .gitignore excludes Python bytecode cache directories" {
  #R040
  run rg '^__pycache__/$' "${GITIGNORE}"
  [ "$status" -eq 0 ]
  run git -C "${REPO_ROOT}" check-ignore -q "scripts/__pycache__/mod.cpython-312.pyc"
  [ "$status" -eq 0 ]
}

@test "R045: .gitignore excludes standalone Python bytecode files" {
  #R045
  run rg '^\*\.pyc$' "${GITIGNORE}"
  [ "$status" -eq 0 ]
  run git -C "${REPO_ROOT}" check-ignore -q "scripts/mod.pyc"
  [ "$status" -eq 0 ]
}
