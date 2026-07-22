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
