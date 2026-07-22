#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid

  # A bash function, not a PATH stub -- a function is found before any
  # PATH lookup for a plain command name, so it works the same whether or
  # not the environment has a real adb (or even `/usr/bin/env`, which the
  # Nix build sandbox notably doesn't). Invoked indirectly, from inside
  # list_extra_pkgs (sourced from declaroid), not from this file directly.
  # shellcheck disable=SC2329
  adb() {
    if [[ "$3" == "shell" && "$*" == *"pm list packages -3"* ]]
    then
      printf 'package:com.example.a\npackage:com.example.tracked\npackage:com.example.extra\n'
      return 0
    fi
    echo "fake adb: unhandled invocation: $*" >&2
    return 1
  }
}

@test "list_extra_pkgs: apps: and obtainium: pkgs are never reported as extra" {
  # Regresses a real bug: --enforce uninstalled a device app that was only
  # tracked via obtainium:, not apps:, because list_extra_pkgs didn't know
  # about obtainium: pkgs at all.
  run list_extra_pkgs "$(fixture list_extra_pkgs/config.yaml)" fake-device
  [ "$status" -eq 0 ]

  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "com.example.extra" ]
}
