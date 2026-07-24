#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
}

@test "known_pkg_override: org.fdroid.fdroid resolves to a url-store override" {
  run known_pkg_override org.fdroid.fdroid
  [ "$status" -eq 0 ]

  local store url repo asset
  IFS="$ROW_SEP" read -r store url repo asset <<< "$output"
  [ "$store" = "url" ]
  [ "$url" = "https://f-droid.org/F-Droid.apk" ]
  [ "$repo" = "" ]
  [ "$asset" = "" ]
}

@test "known_pkg_override: com.topjohnwu.magisk resolves to the versioned-release asset pattern" {
  run known_pkg_override com.topjohnwu.magisk
  [ "$status" -eq 0 ]

  local store url repo asset
  IFS="$ROW_SEP" read -r store url repo asset <<< "$output"
  [ "$store" = "github" ]
  [ "$repo" = "topjohnwu/Magisk" ]
  [ "$asset" = '^Magisk-v.*\.apk$' ]
}

@test "known_pkg_override: dev.imranr.obtainium.fdroid and dev.imranr.obtainium resolve to DIFFERENT, correct assets (regression guard)" {
  # Real historical bug (see AGENTS.md / commit f562442): a single merged
  # case arm covering both Obtainium package id variants pointed both at
  # the same app-release.apk asset -- which is the WRONG package for the
  # .fdroid variant. That installed the wrong app, which --enforce then
  # immediately uninstalled again on the same apply run since the
  # installed pkg didn't match what was configured. Guard against that
  # merge ever happening again: assert both pkg ids resolve to their own,
  # distinct, correct asset pattern.
  run known_pkg_override dev.imranr.obtainium.fdroid
  [ "$status" -eq 0 ]
  local fdroid_variant_output="$output"

  local store url repo asset
  IFS="$ROW_SEP" read -r store url repo asset <<< "$fdroid_variant_output"
  [ "$store" = "github" ]
  [ "$repo" = "ImranR98/Obtainium" ]
  [ "$asset" = 'app-fdroid-release\.apk$' ]

  run known_pkg_override dev.imranr.obtainium
  [ "$status" -eq 0 ]
  local base_variant_output="$output"

  IFS="$ROW_SEP" read -r store url repo asset <<< "$base_variant_output"
  [ "$store" = "github" ]
  [ "$repo" = "ImranR98/Obtainium" ]
  [ "$asset" = 'app-release\.apk$' ]

  # The actual regression shape: a merged case arm would make these equal.
  [ "$fdroid_variant_output" != "$base_variant_output" ]
}

@test "known_pkg_override: an unrecognized pkg id returns non-zero" {
  run known_pkg_override com.example.totally.unknown
  [ "$status" -eq 1 ]
}
