#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
}

@test "resolve_config: no imports returns the config unchanged" {
  local config
  config="$(fixture resolve_config/base.yaml)"

  run resolve_config "$config"
  [ "$status" -eq 0 ]
  [ "$output" = "$config" ]
}

@test "resolve_config: apps concatenate import-then-own, in import order" {
  run resolve_config "$(fixture resolve_config/device_inherits_scalars.yaml)"
  [ "$status" -eq 0 ]
  local resolved="$output"

  run yq -r '.apps[].pkg' "$resolved"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "com.example.base" ]
  [ "${lines[1]}" = "com.example.shared" ]
  [ "${lines[2]}" = "com.example.device" ]
}

@test "resolve_config: scalar with no own value inherits the last import that sets it" {
  # base.yaml (store: gplay) is listed before shared.yaml (store: fdroid) --
  # shared.yaml must win since it's the later import.
  run resolve_config "$(fixture resolve_config/device_inherits_scalars.yaml)"
  [ "$status" -eq 0 ]

  run yq -r '.store' "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "fdroid" ]
}

@test "resolve_config: scalar only set by one import is inherited" {
  run resolve_config "$(fixture resolve_config/device_inherits_scalars.yaml)"
  [ "$status" -eq 0 ]
  local resolved="$output"

  run yq -r '.enforce' "$resolved"
  [ "$output" = "true" ]

  run yq -r '.grant_permissions' "$resolved"
  [ "$output" = "true" ]
}

@test "resolve_config: a device's own scalar value wins over any import" {
  run resolve_config "$(fixture resolve_config/device_own_scalar.yaml)"
  [ "$status" -eq 0 ]

  run yq -r '.store' "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "local" ]
}

@test "resolve_config: a device's own apps: entry replaces an imported one for the same pkg" {
  # Regresses what would otherwise be a real bug: without dedup, apply
  # would install this pkg (the imported, wanted row) and then immediately
  # uninstall it again in the same run (the device's own state.installed:
  # false row) -- forever, on every single apply.
  run resolve_config "$(fixture resolve_config/dedup_device.yaml)"
  [ "$status" -eq 0 ]
  local resolved="$output"

  run yq -r '.apps | length' "$resolved"
  [ "$output" = "2" ]

  run yq -r '.apps[] | select(.pkg == "com.example.override") | .name' "$resolved"
  [ "$output" = "Not Wanted Here" ]

  run yq -r '.apps[] | select(.pkg == "com.example.override") | .state.installed' "$resolved"
  [ "$output" = "false" ]

  run yq -r '.apps[] | select(.pkg == "com.example.keep") | .name' "$resolved"
  [ "$output" = "Kept As-Is" ]
}

@test "resolve_config: imports: resolve against a symlink's target directory, not the symlink's own" {
  # Regresses a real bug: a Home Manager mkOutOfStoreSymlink at, say,
  # ~/.config/declaroid/apps.yaml pointing at a live git checkout elsewhere
  # made every relative imports:/configs: entry resolve against
  # ~/.config/declaroid instead of the checkout, failing with "entry not
  # found" for every single one.
  local link="$BATS_TEST_TMPDIR/apps.yaml"
  ln -s "$(fixture resolve_config/device_inherits_scalars.yaml)" "$link"

  run resolve_config "$link"
  [ "$status" -eq 0 ]

  run yq -r '.apps[].pkg' "$output"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "com.example.base" ]
  [ "${lines[1]}" = "com.example.shared" ]
  [ "${lines[2]}" = "com.example.device" ]
}

@test "resolve_config: a meta-config's scalar (via META_CONFIG_SCALAR_SOURCE) is inherited when the leaf has no imports: of its own" {
  # Also regresses the no-imports fast path: without extending its guard to
  # check META_CONFIG_SCALAR_SOURCE too, resolve_config would return the
  # leaf unchanged before ever reaching the scalar_key loop.
  # Read dynamically by resolve_config itself (dynamic-scope, same
  # convention as DEVICE_SERIAL in build_plans.bats -- see its comment);
  # static analysis can't see the sourced production function that reads
  # it.
  # shellcheck disable=SC2034
  META_CONFIG_SCALAR_SOURCE="$(fixture resolve_config/meta_enforce_true.yaml)"

  run resolve_config "$(fixture resolve_config/leaf_no_imports.yaml)"
  [ "$status" -eq 0 ]

  run yq -r '.enforce' "$output"
  [ "$output" = "true" ]
}

@test "resolve_config: a leaf's own imports: still win over a meta-config's scalar" {
  # device_inherits_scalars.yaml imports base.yaml (enforce: true) and sets
  # no enforce: of its own -- the meta source below deliberately disagrees
  # (enforce: false) so a naive "meta always wins" implementation would be
  # caught here.
  # shellcheck disable=SC2034
  META_CONFIG_SCALAR_SOURCE="$(fixture resolve_config/meta_enforce_false.yaml)"

  run resolve_config "$(fixture resolve_config/device_inherits_scalars.yaml)"
  [ "$status" -eq 0 ]

  run yq -r '.enforce' "$output"
  [ "$output" = "true" ]
}

@test "resolve_config: a leaf's own top-level scalar still wins over a meta-config's" {
  # own_enforce_false.yaml sets enforce: false itself (and also imports
  # base.yaml, which sets enforce: true, already covered by the device's-
  # own-value-wins test above) -- the meta source here deliberately
  # disagrees with both.
  # shellcheck disable=SC2034
  META_CONFIG_SCALAR_SOURCE="$(fixture resolve_config/meta_enforce_true.yaml)"

  run resolve_config "$(fixture resolve_config/own_enforce_false.yaml)"
  [ "$status" -eq 0 ]

  run yq -r '.enforce' "$output"
  [ "$output" = "false" ]
}
