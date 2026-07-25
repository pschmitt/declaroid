#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
}

@test "is_module_plumbing_id: zn_magisk_compat is denylisted" {
  run is_module_plumbing_id zn_magisk_compat
  [ "$status" -eq 0 ]
}

@test "is_module_plumbing_id: an arbitrary real-looking module id is not denylisted" {
  run is_module_plumbing_id specter
  [ "$status" -eq 1 ]
}
