#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
}

@test "store_for_installer: com.android.vending maps to gplay" {
  run store_for_installer com.android.vending
  [ "$status" -eq 0 ]
  [ "$output" = "gplay" ]
}

@test "store_for_installer: org.fdroid.fdroid maps to fdroid" {
  run store_for_installer org.fdroid.fdroid
  [ "$status" -eq 0 ]
  [ "$output" = "fdroid" ]
}

@test "store_for_installer: an Obtainium installer id maps to github" {
  run store_for_installer dev.imranr.obtainium
  [ "$status" -eq 0 ]
  [ "$output" = "github" ]

  run store_for_installer dev.imranr.obtainium.fdroid
  [ "$status" -eq 0 ]
  [ "$output" = "github" ]
}

@test "store_for_installer: an unrecognized installer id maps to unknown (empty)" {
  run store_for_installer com.some.random.installer
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
