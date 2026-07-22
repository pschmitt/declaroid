#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
  CONFIG="$(fixture app_rows/basic.yaml)"
}

@test "app_rows: an app with no overrides picks up the top-level defaults" {
  run app_rows "$CONFIG"
  [ "$status" -eq 0 ]

  local row
  row="$(printf '%s\n' "${lines[@]}" | grep "^A${ROW_SEP}com.example.a${ROW_SEP}")"
  [ "$row" = "A${ROW_SEP}com.example.a${ROW_SEP}fdroid${ROW_SEP}${ROW_SEP}"'\.apk$'"${ROW_SEP}${ROW_SEP}0${ROW_SEP}${ROW_SEP}true${ROW_SEP}false" ]
}

@test "app_rows: an app's own store/repo/profile override the defaults" {
  run app_rows "$CONFIG"
  [ "$status" -eq 0 ]

  local row
  row="$(printf '%s\n' "${lines[@]}" | grep "^B${ROW_SEP}com.example.b${ROW_SEP}")"
  [ "$row" = "B${ROW_SEP}com.example.b${ROW_SEP}github${ROW_SEP}example/b${ROW_SEP}"'\.apk$'"${ROW_SEP}${ROW_SEP}all${ROW_SEP}${ROW_SEP}true${ROW_SEP}false" ]
}

@test "app_rows: state.installed: false is reported, not coalesced away" {
  run app_rows "$CONFIG"
  [ "$status" -eq 0 ]

  local row
  row="$(printf '%s\n' "${lines[@]}" | grep "^C${ROW_SEP}com.example.c${ROW_SEP}")"
  [[ "$row" == *"${ROW_SEP}false${ROW_SEP}false" ]]
}

@test "app_rows: state.disabled: true is reported" {
  run app_rows "$CONFIG"
  [ "$status" -eq 0 ]

  local row
  row="$(printf '%s\n' "${lines[@]}" | grep "^D${ROW_SEP}com.example.d${ROW_SEP}")"
  [[ "$row" == *"${ROW_SEP}true${ROW_SEP}true" ]]
}
