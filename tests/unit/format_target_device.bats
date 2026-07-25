#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid

  # Same convention as list_extra_pkgs.bats stubbing adb directly -- a
  # plain bash function, found before any PATH lookup.
  # shellcheck disable=SC2329
  adb() {
    if [[ "$1" == "devices" && "$2" == "-l" ]]
    then
      printf 'mi-pad-4.lan:35429 device usb: product:clover model:MI_PAD_4 device:clover transport_id:5\n'
      printf 'no-model-serial device\n'
      return 0
    fi
    echo "fake adb: unhandled invocation: $*" >&2
    return 1
  }
}

@test "format_target_device: MODEL (CODENAME) at SERIAL for a device adb knows about" {
  run format_target_device "mi-pad-4.lan:35429"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MI_PAD_4 (clover) at mi-pad-4.lan:35429"* ]]
}

@test "format_target_device: falls back to the bare serial when adb has no model:/device: for it" {
  run format_target_device "no-model-serial"
  [ "$status" -eq 0 ]
  [ "$output" = "no-model-serial" ]
}

@test "format_target_device: falls back to the bare serial when adb doesn't know the serial at all" {
  run format_target_device "totally-unknown-serial"
  [ "$status" -eq 0 ]
  [ "$output" = "totally-unknown-serial" ]
}
