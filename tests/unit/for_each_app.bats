#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
  : > "$BATS_TEST_TMPDIR/calls.log"
}

# A no-op stand-in for the real app_fn callback for_each_app invokes -- reads
# CURRENT_PKG (set by for_each_app before calling it, same dynamic-scope
# convention as install_app/uninstall_app) and records one line per call, so
# tests can assert exactly how many times it actually ran.
# shellcheck disable=SC2329
app_fn() {
  printf '%s\n' "$CURRENT_PKG" >> "$BATS_TEST_TMPDIR/calls.log"
  return 0
}

@test "for_each_app: calls app_fn exactly once per app row in the config" {
  run for_each_app "$(fixture for_each_app/two_apps.yaml)" app_fn
  [ "$status" -eq 0 ]

  local -a calls
  mapfile -t calls < "$BATS_TEST_TMPDIR/calls.log"
  [ "${#calls[@]}" -eq 2 ]
  [ "${calls[0]}" = "com.example.a" ]
  [ "${calls[1]}" = "com.example.b" ]
}

@test "for_each_app: an empty apps: [] config results in zero calls, not one spurious call" {
  # Regresses a real, documented gotcha (see AGENTS.md): yq -r emits one
  # blank line, not zero output, for '(.apps // [])[] | ... | join(...)'
  # over an empty/absent list -- app_rows/for_each_app must guard against
  # that blank-line row turning into one phantom all-empty-fields call.
  run for_each_app "$(fixture for_each_app/empty_apps.yaml)" app_fn
  [ "$status" -eq 0 ]

  local -a calls
  mapfile -t calls < "$BATS_TEST_TMPDIR/calls.log"
  [ "${#calls[@]}" -eq 0 ]
}
