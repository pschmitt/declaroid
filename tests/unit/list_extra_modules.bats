#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid

  # Stubs list_root_modules directly (one call-site closer to the thing
  # under test than mocking adb/run_root_shell) -- same convention
  # build_plans.bats uses for is_installed. Framework param is unused by
  # the stub since list_extra_modules only ever forwards it.
  # shellcheck disable=SC2329
  list_root_modules() {
    printf 'tracked-module\tTracked\t1.0\tyes\n'
    printf 'extra-module\tExtra\t2.0\tyes\n'
  }
}

@test "list_extra_modules: modules configured by id are never reported as extra" {
  run list_extra_modules "$(fixture list_extra_modules/config.yaml)" fake-device magisk
  [ "$status" -eq 0 ]

  [ "${#lines[@]}" -eq 1 ]
  [ "$output" = $'extra-module\tExtra' ]
}
