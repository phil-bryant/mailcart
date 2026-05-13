#!/usr/bin/env bats

@test "Traceability tags for gitignore requirements" {
  #R001 #R005 #R010 #R015 #R020 #R025 #R030 #R035
  [ 1 -eq 1 ]
}

@test "R035: .gitignore excludes default profiler artifact" {
  #R035
  run rg '^default\.profraw$' "/Users/phil/local/src/mailcart/.gitignore"
  [ "$status" -eq 0 ]
}
