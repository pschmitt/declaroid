#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
  # add_app_to_config mutates $config in place via `yq -i` -- always
  # operate on a throwaway copy, never the checked-in fixture.
  CONFIG="$BATS_TEST_TMPDIR/config.yaml"
  cp "$(fixture add_app_to_config/base.yaml)" "$CONFIG"
}

@test "add_app_to_config: adding a genuinely new pkg appends it, omitting store: since it matches the config default" {
  DRY_RUN=""
  run add_app_to_config "$CONFIG" "New App" com.example.new fdroid
  [ "$status" -eq 0 ]
  [[ "$output" == *"Added"* ]]

  run yq -r '.apps | length' "$CONFIG"
  [ "$output" -eq 2 ]

  run yq -r '.apps[-1].pkg' "$CONFIG"
  [ "$output" = "com.example.new" ]

  run yq -r '.apps[-1].name' "$CONFIG"
  [ "$output" = "New App" ]

  run yq -r '.apps[-1] | has("store")' "$CONFIG"
  [ "$output" = "false" ]
}

@test "add_app_to_config: adding a pkg with a store differing from the config default includes store:" {
  DRY_RUN=""
  run add_app_to_config "$CONFIG" "GitHub App" com.example.gh github
  [ "$status" -eq 0 ]

  run yq -r '.apps[-1].store' "$CONFIG"
  [ "$output" = "github" ]
}

@test "add_app_to_config: adding a pkg that already exists is skipped, not appended twice" {
  DRY_RUN=""
  run add_app_to_config "$CONFIG" "Duplicate" com.example.existing fdroid
  [ "$status" -eq 0 ]
  [[ "$output" == *"already in"* ]]

  run yq -r '.apps | length' "$CONFIG"
  [ "$output" -eq 1 ]
}

@test "add_app_to_config --dry-run: prints the entry without mutating the file, omitting store: when it matches the default" {
  # Read dynamically by add_app_to_config itself (declaroid's own
  # CURRENT_*/DRY_RUN/DEVICE_SERIAL dynamic-scope convention -- see
  # AGENTS.md), not used anywhere else in this file; shellcheck can't see
  # the sourced production function that reads it.
  # shellcheck disable=SC2034
  DRY_RUN=1
  run add_app_to_config "$CONFIG" "New App" com.example.new fdroid
  [ "$status" -eq 0 ]
  [[ "$output" == *'name: "New App"'* ]]
  [[ "$output" == *"pkg: com.example.new"* ]]
  [[ "$output" != *"store:"* ]]

  # Never actually mutated.
  run yq -r '.apps | length' "$CONFIG"
  [ "$output" -eq 1 ]
}

@test "add_app_to_config --dry-run: includes store: when it differs from the config default" {
  # See the previous test's comment.
  # shellcheck disable=SC2034
  DRY_RUN=1
  run add_app_to_config "$CONFIG" "GitHub App" com.example.gh github
  [ "$status" -eq 0 ]
  [[ "$output" == *"store: github"* ]]

  run yq -r '.apps | length' "$CONFIG"
  [ "$output" -eq 1 ]
}
