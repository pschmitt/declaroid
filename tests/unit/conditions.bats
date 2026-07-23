#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
}

@test "config_has_conditions: false for a config with no if: anywhere" {
  run config_has_conditions "$(fixture conditions/no_conditions.yaml)"
  [ "$status" -eq 1 ]
}

@test "config_has_conditions: true when an apps:/modules: entry has if:" {
  run config_has_conditions "$(fixture conditions/apps_and_modules.yaml)"
  [ "$status" -eq 0 ]
}

@test "device_props_json: parses getprop's [key]: [value] lines into a JSON object" {
  # shellcheck disable=SC2329
  adb() {
    [[ "$*" == *"-s dev1 shell getprop"* ]] && printf '[ro.product.device]: [clover]\n[ro.build.characteristics]: [tablet]\n'
  }

  run device_props_json dev1
  [ "$status" -eq 0 ]

  run jq -r '.["ro.product.device"]' <<< "$output"
  [ "$output" = "clover" ]
}

@test "device_props_json: prints {} if adb/getprop itself fails" {
  # shellcheck disable=SC2329
  adb() { return 1; }

  run device_props_json dev1
  [ "$status" -eq 0 ]
  [ "$output" = "{}" ]
}

@test "condition_matches: empty condition always matches" {
  run condition_matches '{}' '{"ro.product.device":"clover"}'
  [ "$status" -eq 0 ]
}

@test "condition_matches: single-key exact match" {
  run condition_matches '{"ro.product.device":"clover"}' '{"ro.product.device":"clover"}'
  [ "$status" -eq 0 ]
}

@test "condition_matches: single-key mismatch fails" {
  run condition_matches '{"ro.product.device":"redfin"}' '{"ro.product.device":"clover"}'
  [ "$status" -eq 1 ]
}

@test "condition_matches: multiple keys are ANDed" {
  local props='{"ro.product.device":"clover","ro.build.characteristics":"tablet"}'
  run condition_matches '{"ro.product.device":"clover","ro.build.characteristics":"tablet"}' "$props"
  [ "$status" -eq 0 ]
  run condition_matches '{"ro.product.device":"clover","ro.build.characteristics":"phone"}' "$props"
  [ "$status" -eq 1 ]
}

@test "condition_matches: not: negates its nested condition" {
  local props='{"ro.product.device":"clover"}'
  run condition_matches '{"not":{"ro.product.device":"redfin"}}' "$props"
  [ "$status" -eq 0 ]
  run condition_matches '{"not":{"ro.product.device":"clover"}}' "$props"
  [ "$status" -eq 1 ]
}

@test "condition_matches: or: is true if any nested condition is true" {
  local props='{"ro.product.device":"clover"}'
  run condition_matches '{"or":[{"ro.product.device":"redfin"},{"ro.product.device":"clover"}]}' "$props"
  [ "$status" -eq 0 ]
  run condition_matches '{"or":[{"ro.product.device":"redfin"},{"ro.product.device":"other"}]}' "$props"
  [ "$status" -eq 1 ]
}

@test "condition_matches: not:/or: can be nested and mixed with plain keys" {
  local props='{"ro.product.device":"clover","ro.build.characteristics":"tablet"}'
  run condition_matches '{"ro.build.characteristics":"tablet","not":{"ro.product.device":"redfin"}}' "$props"
  [ "$status" -eq 0 ]
}

@test "filter_config_for_device: no if: anywhere returns the config unchanged, no adb call" {
  # No adb mock at all -- if filter_config_for_device called it despite
  # config_has_conditions being false, the real adb binary would either
  # error (not on PATH in the test sandbox) or hang; either way this test
  # would fail, proving the fast path really skips it.
  local config
  config="$(fixture conditions/no_conditions.yaml)"

  run filter_config_for_device "$config" some-device
  [ "$status" -eq 0 ]
  [ "$output" = "$config" ]
}

@test "filter_config_for_device: keeps only entries matching redfin" {
  # shellcheck disable=SC2329
  adb() {
    [[ "$*" == *"shell getprop"* ]] && printf '[ro.product.device]: [redfin]\n'
  }

  run filter_config_for_device "$(fixture conditions/apps_and_modules.yaml)" fake-redfin
  [ "$status" -eq 0 ]
  local filtered="$output"

  run yq -r '.apps[].name' "$filtered"
  [ "${lines[0]}" = "APatch" ]
  [ "${lines[1]}" = "Always" ]
  [ "${#lines[@]}" -eq 2 ]

  run yq -r '.modules[].id' "$filtered"
  [ "${lines[0]}" = "apatch-only-module" ]
  [ "${lines[1]}" = "always-module" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "filter_config_for_device: keeps only entries matching clover" {
  # shellcheck disable=SC2329
  adb() {
    [[ "$*" == *"shell getprop"* ]] && printf '[ro.product.device]: [clover]\n'
  }

  run filter_config_for_device "$(fixture conditions/apps_and_modules.yaml)" fake-clover
  [ "$status" -eq 0 ]
  local filtered="$output"

  run yq -r '.apps[].name' "$filtered"
  [ "${lines[0]}" = "Magisk" ]
  [ "${lines[1]}" = "Always" ]
  [ "${#lines[@]}" -eq 2 ]

  run yq -r '.modules[].id' "$filtered"
  [ "${lines[0]}" = "always-module" ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "filter_config_for_device: a device matching neither condition only keeps the unconditional entries" {
  # shellcheck disable=SC2329
  adb() {
    [[ "$*" == *"shell getprop"* ]] && printf '[ro.product.device]: [someother]\n'
  }

  run filter_config_for_device "$(fixture conditions/apps_and_modules.yaml)" fake-other
  [ "$status" -eq 0 ]
  local filtered="$output"

  run yq -r '.apps[].name' "$filtered"
  [ "${lines[0]}" = "Always" ]
  [ "${#lines[@]}" -eq 1 ]
}
