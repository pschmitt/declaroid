#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  # CACHE_ROOT is derived from XDG_CACHE_HOME at source time (top-level
  # assignment near the top of declaroid) -- set this before load_declaroid
  # actually sources the script so CACHE_ROOT points at an isolated tmpdir,
  # not the real user cache.
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache_home"
  load_declaroid
}

@test "cache_dir_for: a normal pkg id produces the expected path under CACHE_ROOT" {
  run cache_dir_for com.example.myapp
  [ "$status" -eq 0 ]
  [ "$output" = "$CACHE_ROOT/com.example.myapp" ]
}

@test "cache_dir_for: a key containing a slash is rejected" {
  run cache_dir_for "com.example/../evil"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe package id"* ]]
}

@test "cache_dir_for: a key that is exactly '.' is rejected" {
  run cache_dir_for "."
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe package id"* ]]
}

@test "cache_dir_for: a key that is exactly '..' is rejected" {
  run cache_dir_for ".."
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe package id"* ]]
}

@test "module_cache_dir_for: a normal module id produces a path with the /modules/ segment" {
  run module_cache_dir_for my-module
  [ "$status" -eq 0 ]
  [ "$output" = "$CACHE_ROOT/modules/my-module" ]
}

@test "module_cache_dir_for: a key containing a slash is rejected" {
  run module_cache_dir_for "../escape"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe module id"* ]]
}

@test "module_cache_dir_for: a key that is exactly '..' is rejected" {
  run module_cache_dir_for ".."
  [ "$status" -eq 1 ]
  [[ "$output" == *"unsafe module id"* ]]
}

@test "label_cache_file_for: builds the .label path under the pkg's own cache dir" {
  run label_cache_file_for com.example.myapp
  [ "$status" -eq 0 ]
  [ "$output" = "$CACHE_ROOT/com.example.myapp/.label" ]
}
