#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
}

@test "is_system_plumbing_pkg: com.android.vending is denylisted" {
  run is_system_plumbing_pkg com.android.vending
  [ "$status" -eq 0 ]
}

@test "is_system_plumbing_pkg: com.google.android.gms is denylisted" {
  run is_system_plumbing_pkg com.google.android.gms
  [ "$status" -eq 0 ]
}

@test "is_system_plumbing_pkg: com.google.android.webview is denylisted" {
  run is_system_plumbing_pkg com.google.android.webview
  [ "$status" -eq 0 ]
}

@test "is_system_plumbing_pkg: com.google.ar.core is denylisted" {
  run is_system_plumbing_pkg com.google.ar.core
  [ "$status" -eq 0 ]
}

@test "is_system_plumbing_pkg: an arbitrary real-looking app id is not denylisted" {
  run is_system_plumbing_pkg com.example.myapp
  [ "$status" -eq 1 ]
}
