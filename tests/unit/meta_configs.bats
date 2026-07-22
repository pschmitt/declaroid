#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
}

@test "is_meta_config: false for a plain leaf config" {
  run is_meta_config "$(fixture meta_configs/leaf_a.yaml)"
  [ "$status" -eq 1 ]
}

@test "is_meta_config: true for a config with a non-empty configs: list" {
  run is_meta_config "$(fixture meta_configs/meta.yaml)"
  [ "$status" -eq 0 ]
}

@test "collect_meta_configs: expands configs: into leaf paths, in listed order" {
  declare -A META_SEEN=()
  run collect_meta_configs "$(fixture meta_configs/meta.yaml)"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *leaf_a.yaml ]]
  [[ "${lines[1]}" == *leaf_b.yaml ]]
}

@test "collect_meta_configs: a leaf with no configs: of its own prints itself" {
  declare -A META_SEEN=()
  run collect_meta_configs "$(fixture meta_configs/leaf_a.yaml)"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *leaf_a.yaml ]]
}

@test "collect_meta_configs: a real cycle is detected and rejected" {
  declare -A META_SEEN=()
  run collect_meta_configs "$(fixture meta_configs/meta_cycle_a.yaml)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Cycle detected"* ]]
}

@test "run_meta_config: rejects configs: combined with device: in the same file" {
  run run_meta_config cmd_diff "$(fixture meta_configs/meta_with_device.yaml)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot be combined with apps:/device:"* ]]
}

@test "run_meta_config: rejects configs: combined with apps: in the same file" {
  run run_meta_config cmd_diff "$(fixture meta_configs/meta_with_apps.yaml)"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot be combined with apps:/device:"* ]]
}

# A stand-in for cmd_apply/cmd_diff/etc: records how it was called and fails
# for exactly one leaf (leaf_b), so the aggregation test below can check
# both "every leaf still runs" and "one failure makes the overall result
# non-zero" without needing a real device.
fake_cmd() {
  printf '%s\n' "$*" >> "$FAKE_CMD_LOG"
  [[ "$*" == *leaf_b.yaml* ]] && return 1
  return 0
}

@test "run_meta_config: runs every leaf, forwards extra args, aggregates a failure" {
  FAKE_CMD_LOG="$BATS_TEST_TMPDIR/fake_cmd.log"
  : > "$FAKE_CMD_LOG"
  export FAKE_CMD_LOG

  run run_meta_config fake_cmd "$(fixture meta_configs/meta.yaml)" -y --enforce
  [ "$status" -eq 1 ]

  local -a calls
  mapfile -t calls < "$FAKE_CMD_LOG"
  [ "${#calls[@]}" -eq 2 ]
  [[ "${calls[0]}" == "-c "*"leaf_a.yaml -y --enforce" ]]
  [[ "${calls[1]}" == "-c "*"leaf_b.yaml -y --enforce" ]]
}

@test "strip_config_flag: removes -c/--config VALUE and keeps everything else" {
  run strip_config_flag -c old.yaml -y --enforce -d foo
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "-y" ]
  [ "${lines[1]}" = "--enforce" ]
  [ "${lines[2]}" = "-d" ]
  [ "${lines[3]}" = "foo" ]
}
