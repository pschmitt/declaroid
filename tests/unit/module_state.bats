#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid

  # A bash function stand-in for the real run_root_shell (which shells out
  # to adb) -- records every invocation to $ROOT_SHELL_LOG and answers the
  # two probes is_module_disabled/is_module_installed make based on
  # $FAKE_DISABLE_MARKER/$FAKE_MODULE_DIR ("1" = present). Defined here in
  # setup(), AFTER load_declaroid, not at file top level -- load_declaroid
  # (re-)sources the real declaroid script every test, which would
  # otherwise clobber a top-level mock right back to the real
  # adb-shelling implementation (confirmed empirically: an earlier version
  # of this file defined it before setup() and every test silently ran
  # against the unmocked real run_root_shell instead). Same convention
  # list_extra_pkgs.bats/build_module_plans.bats already follow for their
  # own mocks.
  # shellcheck disable=SC2329
  run_root_shell() {
    printf '%s\n' "$2" >> "$ROOT_SHELL_LOG"
    case "$2" in
      *"[ -f "*"/disable' ]"*)
        [[ "${FAKE_DISABLE_MARKER:-}" == 1 ]] && printf 'yes\n'
        ;;
      *"[ -d "*"' ]"*)
        [[ "${FAKE_MODULE_DIR:-}" == 1 ]] && printf 'yes\n'
        ;;
      *"touch "*)
        return 0
        ;;
      *"rm -f "*)
        return 0
        ;;
    esac
  }
}

@test "is_module_disabled: true when the disable marker file is present" {
  ROOT_SHELL_LOG="$BATS_TEST_TMPDIR/root_shell.log"
  : > "$ROOT_SHELL_LOG"
  FAKE_DISABLE_MARKER=1
  run is_module_disabled fake-device some-module
  [ "$status" -eq 0 ]
}

@test "is_module_disabled: false when the disable marker file is absent" {
  ROOT_SHELL_LOG="$BATS_TEST_TMPDIR/root_shell.log"
  : > "$ROOT_SHELL_LOG"
  FAKE_DISABLE_MARKER=0
  run is_module_disabled fake-device some-module
  [ "$status" -eq 1 ]
}

@test "uninstall_module: touches the remove marker, not rm -rf" {
  ROOT_SHELL_LOG="$BATS_TEST_TMPDIR/root_shell.log"
  : > "$ROOT_SHELL_LOG"

  run uninstall_module fake-device some-module
  [ "$status" -eq 0 ]

  grep -q "touch '/data/adb/modules/some-module/remove'" "$ROOT_SHELL_LOG"
  run grep -c "rm -rf" "$ROOT_SHELL_LOG"
  [ "$output" -eq 0 ]
}

# The remaining tests call the function under test directly, NOT via bats'
# run -- run captures output through a `$(...)` command substitution, which
# forks a subshell, and MODULES_CHANGED_COUNT's increment (a plain shell
# variable mutation) would silently vanish with it. Confirmed empirically
# while writing this file: a `run`-wrapped call left MODULES_CHANGED_COUNT
# unchanged in the test's own shell even though the function body clearly
# ran. Stdout is redirected straight to a file instead of `run`'s $output,
# which is a plain redirect (no subshell) and still lets the "would ..."
# dry-run text be asserted on. Every CURRENT_MODULE_*/DEVICE_SERIAL/DRY_RUN
# assignment below is read dynamically by the sourced production function
# itself (declaroid's own dynamic-scope convention -- see AGENTS.md),
# which shellcheck can't see, hence the several SC2034 disables.

@test "sync_module_disabled_state: touches the disable marker when state.disabled:true and not yet disabled" {
  ROOT_SHELL_LOG="$BATS_TEST_TMPDIR/root_shell.log"
  : > "$ROOT_SHELL_LOG"
  FAKE_DISABLE_MARKER=0
  # shellcheck disable=SC2034
  DEVICE_SERIAL="fake-device"
  # shellcheck disable=SC2034
  CURRENT_MODULE_ID="some-module"
  # shellcheck disable=SC2034
  CURRENT_MODULE_NAME="Some Module"
  # shellcheck disable=SC2034
  CURRENT_MODULE_STATE_DISABLED=true
  # shellcheck disable=SC2034
  DRY_RUN=""
  MODULES_CHANGED_COUNT=0

  sync_module_disabled_state > "$BATS_TEST_TMPDIR/stdout.log"

  grep -q "touch '/data/adb/modules/some-module/disable'" "$ROOT_SHELL_LOG"
  [ "$MODULES_CHANGED_COUNT" -eq 1 ]
}

@test "sync_module_disabled_state: removes the disable marker when state.disabled is false/absent and currently disabled" {
  ROOT_SHELL_LOG="$BATS_TEST_TMPDIR/root_shell.log"
  : > "$ROOT_SHELL_LOG"
  FAKE_DISABLE_MARKER=1
  # shellcheck disable=SC2034
  DEVICE_SERIAL="fake-device"
  # shellcheck disable=SC2034
  CURRENT_MODULE_ID="some-module"
  # shellcheck disable=SC2034
  CURRENT_MODULE_NAME="Some Module"
  # shellcheck disable=SC2034
  CURRENT_MODULE_STATE_DISABLED=false
  # shellcheck disable=SC2034
  DRY_RUN=""
  MODULES_CHANGED_COUNT=0

  sync_module_disabled_state > "$BATS_TEST_TMPDIR/stdout.log"

  grep -q "rm -f '/data/adb/modules/some-module/disable'" "$ROOT_SHELL_LOG"
  [ "$MODULES_CHANGED_COUNT" -eq 1 ]
}

@test "sync_module_disabled_state: a no-op when the device already matches -- no root shell mutation, no count" {
  ROOT_SHELL_LOG="$BATS_TEST_TMPDIR/root_shell.log"
  : > "$ROOT_SHELL_LOG"
  FAKE_DISABLE_MARKER=0
  # shellcheck disable=SC2034
  DEVICE_SERIAL="fake-device"
  # shellcheck disable=SC2034
  CURRENT_MODULE_ID="some-module"
  # shellcheck disable=SC2034
  CURRENT_MODULE_NAME="Some Module"
  # shellcheck disable=SC2034
  CURRENT_MODULE_STATE_DISABLED=false
  # shellcheck disable=SC2034
  DRY_RUN=""
  MODULES_CHANGED_COUNT=0

  sync_module_disabled_state > "$BATS_TEST_TMPDIR/stdout.log"

  run grep -c "touch\|rm -f" "$ROOT_SHELL_LOG"
  [ "$output" -eq 0 ]
  [ "$MODULES_CHANGED_COUNT" -eq 0 ]
}

@test "sync_module_disabled_state: --dry-run prints what would happen and mutates nothing" {
  ROOT_SHELL_LOG="$BATS_TEST_TMPDIR/root_shell.log"
  : > "$ROOT_SHELL_LOG"
  FAKE_DISABLE_MARKER=0
  # shellcheck disable=SC2034
  DEVICE_SERIAL="fake-device"
  # shellcheck disable=SC2034
  CURRENT_MODULE_ID="some-module"
  # shellcheck disable=SC2034
  CURRENT_MODULE_NAME="Some Module"
  # shellcheck disable=SC2034
  CURRENT_MODULE_STATE_DISABLED=true
  DRY_RUN=1

  MODULES_CHANGED_COUNT=0

  sync_module_disabled_state > "$BATS_TEST_TMPDIR/stdout.log"
  grep -q "would disable module some-module" "$BATS_TEST_TMPDIR/stdout.log"

  run grep -c "touch\|rm -f" "$ROOT_SHELL_LOG"
  [ "$output" -eq 0 ]
  [ "$MODULES_CHANGED_COUNT" -eq 0 ]
}

@test "install_module_app: state.installed:false skips entirely, no install attempted" {
  # shellcheck disable=SC2034
  DEVICE_SERIAL="fake-device"
  # shellcheck disable=SC2034
  CURRENT_MODULE_ID="some-module"
  # shellcheck disable=SC2034
  CURRENT_MODULE_NAME="Some Module"
  # shellcheck disable=SC2034
  CURRENT_MODULE_STATE_INSTALLED=false
  # shellcheck disable=SC2034
  CURRENT_MODULE_STATE_DISABLED=false
  # shellcheck disable=SC2034
  DRY_RUN=""
  MODULES_CHANGED_COUNT=0
  FAKE_MODULE_DIR=0

  install_module_app > "$BATS_TEST_TMPDIR/stdout.log"
  [ ! -s "$BATS_TEST_TMPDIR/stdout.log" ]
  [ "$MODULES_CHANGED_COUNT" -eq 0 ]
}

@test "uninstall_module_app: skips a module that isn't actually installed" {
  DEVICE_SERIAL="fake-device"
  CURRENT_MODULE_ID="some-module"
  CURRENT_MODULE_NAME="Some Module"
  DRY_RUN=""
  MODULES_CHANGED_COUNT=0
  FAKE_MODULE_DIR=0

  run uninstall_module_app
  [ "$status" -eq 0 ]
  [[ "$output" == *"not installed"* ]]
}

@test "uninstall_module_app: uninstalls an installed module and counts it" {
  ROOT_SHELL_LOG="$BATS_TEST_TMPDIR/root_shell.log"
  : > "$ROOT_SHELL_LOG"
  # shellcheck disable=SC2034
  DEVICE_SERIAL="fake-device"
  # shellcheck disable=SC2034
  CURRENT_MODULE_ID="some-module"
  # shellcheck disable=SC2034
  CURRENT_MODULE_NAME="Some Module"
  # shellcheck disable=SC2034
  DRY_RUN=""
  MODULES_CHANGED_COUNT=0
  FAKE_MODULE_DIR=1

  uninstall_module_app > "$BATS_TEST_TMPDIR/stdout.log"
  [ "$MODULES_CHANGED_COUNT" -eq 1 ]
  grep -q "touch '/data/adb/modules/some-module/remove'" "$ROOT_SHELL_LOG"
}
