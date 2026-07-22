#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
}

@test "obtainium_rows: emits one row per explicit entry, settings as compact JSON" {
  run obtainium_rows "$(fixture obtainium_rows/explicit.yaml)"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "com.example.a${ROW_SEP}https://github.com/example/a${ROW_SEP}{}" ]
  [ "${lines[1]}" = "com.example.b${ROW_SEP}https://github.com/example/b${ROW_SEP}"'{"includePrereleases":true}' ]
}

@test "effective_obtainium_rows: explicit entry wins over auto-track for the same pkg" {
  run effective_obtainium_rows "$(fixture obtainium_rows/auto_track.yaml)"
  [ "$status" -eq 0 ]

  local a_row
  a_row="$(printf '%s\n' "${lines[@]}" | grep "^com.example.a${ROW_SEP}")"
  [ "$a_row" = "com.example.a${ROW_SEP}https://github.com/example/a-custom${ROW_SEP}"'{"includePrereleases":true}' ]
}

@test "effective_obtainium_rows: per-app obtainium: false excludes it even with auto_track on" {
  run effective_obtainium_rows "$(fixture obtainium_rows/auto_track.yaml)"
  [ "$status" -eq 0 ]

  # Not `run !` -- that would only negate printf's own status, since `|`
  # binds before `run` ever sees it, turning this into piping run's output
  # into grep instead of negating the whole pipeline. A bare `!` in front
  # of a real shell pipeline correctly negates the pipeline's overall exit
  # status per normal shell grammar (and is exempt from set -e regardless
  # of that status, so it's safe here even with declaroid's sourced
  # set -euo pipefail active).
  # shellcheck disable=SC2314
  ! printf '%s\n' "${lines[@]}" | grep -q "^com.example.b${ROW_SEP}"
}

@test "effective_obtainium_rows: non-github apps are never auto-tracked" {
  run effective_obtainium_rows "$(fixture obtainium_rows/auto_track.yaml)"
  [ "$status" -eq 0 ]

  # shellcheck disable=SC2314
  ! printf '%s\n' "${lines[@]}" | grep -q "^com.example.c${ROW_SEP}"
}

@test "effective_obtainium_rows: auto_track adds a github app with no explicit entry or override" {
  run effective_obtainium_rows "$(fixture obtainium_rows/auto_track.yaml)"
  [ "$status" -eq 0 ]

  printf '%s\n' "${lines[@]}" | grep -q "^com.example.d${ROW_SEP}https://github.com/example/d${ROW_SEP}{}\$"
}

@test "effective_obtainium_rows: total row count matches exactly a, d (b excluded, c not github)" {
  run effective_obtainium_rows "$(fixture obtainium_rows/auto_track.yaml)"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "effective_obtainium_rows: per-app obtainium: true tracks it even with auto_track off/unset" {
  run effective_obtainium_rows "$(fixture obtainium_rows/override_true_without_global_flag.yaml)"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "com.example.e${ROW_SEP}https://github.com/example/e${ROW_SEP}{}" ]
}
