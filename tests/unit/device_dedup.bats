#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
}

@test "real_device_serial: returns ro.serialno when adb resolves it" {
  # Called indirectly, by real_device_serial inside the sourced declaroid
  # script, not directly in this file.
  # shellcheck disable=SC2329
  adb() {
    [[ "$*" == *"-s dev1 shell getprop ro.serialno"* ]] && printf 'abc123\n'
  }

  run real_device_serial dev1
  [ "$status" -eq 0 ]
  [ "$output" = "abc123" ]
}

@test "real_device_serial: falls back to ro.boot.serialno when ro.serialno is empty" {
  # shellcheck disable=SC2329
  adb() {
    case "$*" in
      *"getprop ro.serialno"*) ;;
      *"getprop ro.boot.serialno"*) printf 'boot123\n' ;;
    esac
  }

  run real_device_serial dev1
  [ "$status" -eq 0 ]
  [ "$output" = "boot123" ]
}

@test "real_device_serial: falls back to the connection string if adb resolves neither prop" {
  # shellcheck disable=SC2329
  adb() { :; }

  run real_device_serial 10.5.0.159:35036
  [ "$status" -eq 0 ]
  [ "$output" = "10.5.0.159:35036" ]
}

@test "dedupe_matched_devices: two connections to the same real device collapse to one" {
  # Mirrors a real, confirmed case: 10.5.0.159:35036 (raw IP) and
  # mi-pad-4.lan:35036 (mDNS hostname) are simultaneously open connections
  # to the identical physical tablet -- both report ro.serialno=dcd9de41.
  # shellcheck disable=SC2329
  adb() {
    case "$*" in
      *"-s 10.5.0.159:35036 shell getprop ro.serialno"*) printf 'dcd9de41\n' ;;
      *"-s mi-pad-4.lan:35036 shell getprop ro.serialno"*) printf 'dcd9de41\n' ;;
    esac
  }

  run dedupe_matched_devices "10.5.0.159:35036 device product:clover model:MI_PAD_4" "mi-pad-4.lan:35036 device product:clover model:MI_PAD_4"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == "10.5.0.159:35036"* ]]
}

@test "dedupe_matched_devices: genuinely distinct devices are all kept" {
  # shellcheck disable=SC2329
  adb() {
    case "$*" in
      *"-s devA shell getprop ro.serialno"*) printf 'serialA\n' ;;
      *"-s devB shell getprop ro.serialno"*) printf 'serialB\n' ;;
    esac
  }

  run dedupe_matched_devices "devA device model:X" "devB device model:Y"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}
