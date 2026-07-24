#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache_home"
  load_declaroid

  mkdir -p "$CACHE_ROOT/com.example.a" "$CACHE_ROOT/com.example.b"
  : > "$CACHE_ROOT/com.example.a/app.apk"
  : > "$CACHE_ROOT/com.example.b/app.apk"
}

@test "cmd_clear_cache --dry-run (no args): previews the whole-cache removal without deleting anything" {
  run cmd_clear_cache --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would remove entire cache"* ]]

  [ -d "$CACHE_ROOT/com.example.a" ]
  [ -d "$CACHE_ROOT/com.example.b" ]
}

@test "cmd_clear_cache -y <pkg>: removes only that package's cache dir, leaves the others" {
  run cmd_clear_cache -y com.example.a
  [ "$status" -eq 0 ]

  [ ! -d "$CACHE_ROOT/com.example.a" ]
  [ -d "$CACHE_ROOT/com.example.b" ]
}

@test "cmd_clear_cache -y <nonexistent pkg>: no-op, no error, other caches untouched" {
  run cmd_clear_cache -y com.example.nonexistent
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing cached"* ]]

  [ -d "$CACHE_ROOT/com.example.a" ]
  [ -d "$CACHE_ROOT/com.example.b" ]
}
