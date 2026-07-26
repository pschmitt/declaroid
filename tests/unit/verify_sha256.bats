#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
  APK="$BATS_TEST_TMPDIR/some-app.apk"
  printf 'not a real apk, just some bytes' > "$APK"
  APK_SHA256="$(sha256sum "$APK" | cut -d' ' -f1)"
}

@test "verify_sha256: a matching digest succeeds" {
  run verify_sha256 "$APK" "$APK_SHA256" com.example.app
  [ "$status" -eq 0 ]
}

@test "verify_sha256: matching is case-insensitive" {
  run verify_sha256 "$APK" "${APK_SHA256^^}" com.example.app
  [ "$status" -eq 0 ]
}

@test "verify_sha256: a mismatching digest fails with a descriptive error" {
  run verify_sha256 "$APK" "0000000000000000000000000000000000000000000000000000000000000000" com.example.app
  [ "$status" -eq 1 ]
  [[ "$output" == *"com.example.app"* ]]
  [[ "$output" == *"sha256 mismatch"* ]]
  [[ "$output" == *"some-app.apk"* ]]
}

# CURRENT_PKG/CURRENT_PATH/CURRENT_SHA256 below are read dynamically by the
# sourced production install_local (declaroid's own dynamic-scope
# convention -- see AGENTS.md), which shellcheck can't see, hence the
# SC2034 disables (same pattern as module_state.bats).

@test "install_local: sha256 configured and matching allows the single-file install to proceed" {
  # No real adb/device involved -- install_apk_files is stubbed to just
  # record what it would have installed, so this only exercises the
  # sha256 gate in install_local itself, not the actual adb call.
  # shellcheck disable=SC2329
  install_apk_files() {
    shift
    printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/installed.log"
  }

  # shellcheck disable=SC2034
  CURRENT_PKG=com.example.app
  # shellcheck disable=SC2034
  CURRENT_PATH="$APK"
  # shellcheck disable=SC2034
  CURRENT_SHA256="$APK_SHA256"

  run install_local
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/installed.log")" = "$APK" ]
}

@test "install_local: sha256 configured and mismatching refuses to install" {
  # shellcheck disable=SC2329
  install_apk_files() {
    printf 'should not have been called\n' > "$BATS_TEST_TMPDIR/installed.log"
  }

  # shellcheck disable=SC2034
  CURRENT_PKG=com.example.app
  # shellcheck disable=SC2034
  CURRENT_PATH="$APK"
  # shellcheck disable=SC2034
  CURRENT_SHA256="0000000000000000000000000000000000000000000000000000000000000000"

  run install_local
  [ "$status" -eq 1 ]
  [[ "$output" == *"sha256 mismatch"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/installed.log" ]
}

@test "install_local: sha256 configured against a multi-file path errors instead of guessing" {
  mkdir "$BATS_TEST_TMPDIR/splits"
  printf 'a' > "$BATS_TEST_TMPDIR/splits/base.apk"
  printf 'b' > "$BATS_TEST_TMPDIR/splits/config.apk"

  # shellcheck disable=SC2329
  install_apk_files() {
    printf 'should not have been called\n' > "$BATS_TEST_TMPDIR/installed.log"
  }

  # shellcheck disable=SC2034
  CURRENT_PKG=com.example.app
  # shellcheck disable=SC2034
  CURRENT_PATH="$BATS_TEST_TMPDIR/splits"
  # shellcheck disable=SC2034
  CURRENT_SHA256="$APK_SHA256"

  run install_local
  [ "$status" -eq 1 ]
  [[ "$output" == *"exactly one file"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/installed.log" ]
}
