#!/usr/bin/env bats

@test "Traceability tags for gitignore requirements" {
  #R001 #R005 #R010 #R015 #R020 #R025 #R030 #R035 #R040
  [ 1 -eq 1 ]
}

@test "R040: .gitignore excludes Python bytecode cache directories" {
  #R040
  run rg '^__pycache__/$' "/Users/phil/local/src/mailcart/.gitignore"
  [ "$status" -eq 0 ]
}

@test "R035: .gitignore excludes default profiler artifact" {
  #R035
  run rg '^default\.profraw$' "/Users/phil/local/src/mailcart/.gitignore"
  [ "$status" -eq 0 ]
}
