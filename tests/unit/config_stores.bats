#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
}

@test "config_stores: extracts the distinct set of stores actually used, resolving app-level defaults" {
  run config_stores "$(fixture config_stores/mixed.yaml)"
  [ "$status" -eq 0 ]

  # A (no override) -> gplay (top-level default), B -> fdroid, C -> github.
  local -a sorted
  mapfile -t sorted < <(printf '%s\n' "${lines[@]}" | sort)
  [ "${#sorted[@]}" -eq 3 ]
  [ "${sorted[0]}" = "fdroid" ]
  [ "${sorted[1]}" = "github" ]
  [ "${sorted[2]}" = "gplay" ]
}
