#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
  CONFIG="$(fixture module_rows/basic.yaml)"
}

@test "module_rows: a module with no overrides picks up the documented defaults" {
  run module_rows "$CONFIG"
  [ "$status" -eq 0 ]

  local row
  row="$(printf '%s\n' "${lines[@]}" | grep "^minimal-module${ROW_SEP}")"
  [ "$row" = "minimal-module${ROW_SEP}minimal-module${ROW_SEP}github${ROW_SEP}example/minimal${ROW_SEP}"'\.zip$'"${ROW_SEP}${ROW_SEP}${ROW_SEP}true${ROW_SEP}false" ]
}

@test "module_rows: a module's own name/source/repo/asset/url/path override the defaults" {
  run module_rows "$CONFIG"
  [ "$status" -eq 0 ]

  local row
  row="$(printf '%s\n' "${lines[@]}" | grep "^full-module${ROW_SEP}")"
  [ "$row" = "full-module${ROW_SEP}Full Module${ROW_SEP}local${ROW_SEP}example/full${ROW_SEP}"'\.tar$'"${ROW_SEP}https://example.com/full.zip${ROW_SEP}/sdcard/full.zip${ROW_SEP}true${ROW_SEP}false" ]
}

@test "module_rows: emits exactly one row per configured module" {
  run module_rows "$CONFIG"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "module_rows: state.installed: false and state.disabled: true override their defaults" {
  run module_rows "$(fixture module_rows/state.yaml)"
  [ "$status" -eq 0 ]

  local row
  row="$(printf '%s\n' "${lines[@]}" | grep "^unwanted-module${ROW_SEP}")"
  [ "$row" = "unwanted-module${ROW_SEP}unwanted-module${ROW_SEP}github${ROW_SEP}example/unwanted${ROW_SEP}"'\.zip$'"${ROW_SEP}${ROW_SEP}${ROW_SEP}false${ROW_SEP}false" ]

  row="$(printf '%s\n' "${lines[@]}" | grep "^disabled-module${ROW_SEP}")"
  [ "$row" = "disabled-module${ROW_SEP}disabled-module${ROW_SEP}github${ROW_SEP}example/disabled${ROW_SEP}"'\.zip$'"${ROW_SEP}${ROW_SEP}${ROW_SEP}true${ROW_SEP}true" ]
}
