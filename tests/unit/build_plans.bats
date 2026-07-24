#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
  CONFIG="$(fixture build_plans/mixed.yaml)"
  # Read dynamically by build_install_plan/build_removal_plan themselves
  # (declaroid's own DEVICE_SERIAL dynamic-scope convention, set once per
  # device by cmd_apply in real usage -- see AGENTS.md); shellcheck can't
  # see the sourced production functions that read it.
  # shellcheck disable=SC2034
  DEVICE_SERIAL="fake-device"

  # Overrides the real is_installed (which shells out to adb) with a plain
  # bash function -- same convention as list_extra_pkgs.bats stubbing adb
  # itself, just one call-site closer to the thing under test since
  # build_install_plan/build_removal_plan only ever call is_installed, never
  # adb directly.
  # shellcheck disable=SC2329
  is_installed() {
    case "$2" in
      com.example.installed | com.example.remove)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  }
}

@test "build_install_plan: splits pending vs already-installed, excludes state.installed:false entirely" {
  build_install_plan "$CONFIG"

  [ "$PLAN_SKIP_COUNT" -eq 1 ]
  [ "${#PLAN_PENDING[@]}" -eq 1 ]
  [[ "${PLAN_PENDING[0]}" == *$'\t'"com.example.pending"$'\t'* ]]
}

@test "build_removal_plan: only apps with state.installed:false that are still actually present are pending" {
  build_removal_plan "$CONFIG"

  [ "${#REMOVAL_PLAN_PENDING[@]}" -eq 1 ]
  [[ "${REMOVAL_PLAN_PENDING[0]}" == *$'\t'"com.example.remove" ]]
}
