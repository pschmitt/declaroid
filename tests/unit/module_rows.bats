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
  [ "$row" = "minimal-module${ROW_SEP}minimal-module${ROW_SEP}github${ROW_SEP}example/minimal${ROW_SEP}"'\.zip$'"${ROW_SEP}${ROW_SEP}" ]
}

@test "module_rows: a module's own name/source/repo/asset/url/path override the defaults" {
  run module_rows "$CONFIG"
  [ "$status" -eq 0 ]

  local row
  row="$(printf '%s\n' "${lines[@]}" | grep "^full-module${ROW_SEP}")"
  [ "$row" = "full-module${ROW_SEP}Full Module${ROW_SEP}local${ROW_SEP}example/full${ROW_SEP}"'\.tar$'"${ROW_SEP}https://example.com/full.zip${ROW_SEP}/sdcard/full.zip" ]
}

@test "module_rows: emits exactly one row per configured module" {
  run module_rows "$CONFIG"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}
