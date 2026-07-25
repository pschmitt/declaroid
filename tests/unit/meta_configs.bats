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

@test "expand_meta_configs: expands configs: into leaf paths, in listed order" {
  run expand_meta_configs "$(fixture meta_configs/meta.yaml)"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *leaf_a.yaml ]]
  [[ "${lines[1]}" == *leaf_b.yaml ]]
}

@test "expand_meta_configs: a leaf with no configs: of its own prints itself" {
  run expand_meta_configs "$(fixture meta_configs/leaf_a.yaml)"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *leaf_a.yaml ]]
}

@test "expand_meta_configs: configs: resolves against a symlink's target directory, not the symlink's own" {
  # Same regression as resolve_config's identical test: a Home Manager
  # mkOutOfStoreSymlink pointing a meta-config at a live checkout elsewhere
  # must still find leaf_a.yaml/leaf_b.yaml next to the *real* file, not
  # next to wherever the symlink itself happens to sit.
  local link="$BATS_TEST_TMPDIR/all.yaml"
  ln -s "$(fixture meta_configs/meta.yaml)" "$link"

  run expand_meta_configs "$link"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *leaf_a.yaml ]]
  [[ "${lines[1]}" == *leaf_b.yaml ]]
}

@test "expand_meta_configs: a real cycle is detected and rejected" {
  run expand_meta_configs "$(fixture meta_configs/meta_cycle_a.yaml)"
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
  # shellcheck disable=SC2030
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

# A second stand-in, this one asserting META_CONFIG_SCALAR_SOURCE (see
# run_meta_config's comment) is actually visible -- dynamic scope, not an
# explicit parameter -- inside every leaf call, and holds the *meta*
# config's own path, not the leaf's. FAKE_CMD_LOG is read back from disk
# via mapfile below, not the shell variable itself, so shellcheck's
# subshell-staleness worry (SC2031) doesn't apply here -- same false
# positive as fake_cmd above, just newly triggered by this second
# assignment existing in the same file (shellcheck analyzes the whole
# file as one scope; each @test only actually runs in its own bats
# subprocess).
# shellcheck disable=SC2031
fake_cmd_records_meta_source() {
  printf '%s\t%s\n' "$*" "${META_CONFIG_SCALAR_SOURCE:-<unset>}" >> "$FAKE_CMD_LOG"
}

@test "run_meta_config: META_CONFIG_SCALAR_SOURCE is visible to every leaf call and holds the meta-config's own path" {
  # shellcheck disable=SC2030
  FAKE_CMD_LOG="$BATS_TEST_TMPDIR/fake_cmd.log"
  : > "$FAKE_CMD_LOG"
  export FAKE_CMD_LOG

  local meta
  meta="$(fixture meta_configs/meta.yaml)"

  run run_meta_config fake_cmd_records_meta_source "$meta"
  [ "$status" -eq 0 ]

  local -a calls
  mapfile -t calls < "$FAKE_CMD_LOG"
  [ "${#calls[@]}" -eq 2 ]

  local call_a_source call_b_source
  call_a_source="${calls[0]#*$'\t'}"
  call_b_source="${calls[1]#*$'\t'}"
  [ "$call_a_source" = "$meta" ]
  [ "$call_b_source" = "$meta" ]
}

@test "strip_config_flag: removes -c/--config VALUE and keeps everything else" {
  run strip_config_flag -c old.yaml -y --enforce -d foo
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "-y" ]
  [ "${lines[1]}" = "--enforce" ]
  [ "${lines[2]}" = "-d" ]
  [ "${lines[3]}" = "foo" ]
}
