#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
  CONFIG="$(fixture build_plans/mixed_modules.yaml)"
  # shellcheck disable=SC2034
  DEVICE_SERIAL="fake-device"

  # Same convention as build_plans.bats stubbing is_installed -- one
  # call-site closer to the thing under test than mocking adb/run_root_shell.
  # shellcheck disable=SC2329
  is_module_installed() {
    case "$2" in
      installed-module | remove-module)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }
}

@test "build_module_plan: splits pending vs already-installed, excludes state.installed:false entirely" {
  build_module_plan "$CONFIG"

  [ "$MODULE_PLAN_SKIP_COUNT" -eq 1 ]
  [ "${#MODULE_PLAN_PENDING[@]}" -eq 1 ]
  [[ "${MODULE_PLAN_PENDING[0]}" == *$'\t'"pending-module"$'\t'* ]]
}

@test "build_module_removal_plan: only modules with state.installed:false that are still actually present are pending" {
  build_module_removal_plan "$CONFIG"

  [ "${#MODULE_REMOVAL_PLAN_PENDING[@]}" -eq 1 ]
  [[ "${MODULE_REMOVAL_PLAN_PENDING[0]}" == *$'\t'"remove-module" ]]
}
