#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid

  # declaroid's own top-level `declare -A PROFILE_ALIASES=()` runs inside
  # load_declaroid's own function frame here (since `source` was itself
  # invoked from a function, not top-level bats code) -- a bare `declare`
  # (no -g) always scopes to its immediately enclosing function, so that
  # declaration (and its associative-array-ness) is destroyed the moment
  # load_declaroid returns, even though the exact same statement behaves as
  # a real global when declaroid is run normally (main() is called directly
  # from top-level code, never from inside another function). Confirmed via
  # a standalone repro: an outer function sourcing a `declare -A FOO=()`
  # one-liner, then reading `${FOO[x]}` from a still-further-removed
  # function, hits "unbound variable" -- indexing a plain/non-associative
  # array with a string key evaluates that string as an arithmetic
  # expression instead. Re-declaring it here with -g restores a genuine
  # global associative array for the rest of this test file to use, without
  # touching declaroid itself (this is purely a `source`-inside-a-function
  # test-harness artifact, not a production bug -- production always calls
  # main() from real top-level code, so `declare -A` there always lands in
  # the real global scope to begin with).
  declare -g -A PROFILE_ALIASES=()
}

@test "load_profile_aliases: a profiles: list populates PROFILE_ALIASES name -> id" {
  load_profile_aliases "$(fixture load_profile_aliases/with_profiles.yaml)"

  [ "${#PROFILE_ALIASES[@]}" -eq 2 ]
  [ "${PROFILE_ALIASES[personal]}" = "0" ]
  [ "${PROFILE_ALIASES[work]}" = "10" ]
}

@test "load_profile_aliases: a config with no profiles: key leaves the array empty, no error" {
  # PROFILE_ALIASES is declared at top level regardless, so re-populate it
  # with something first to prove load_profile_aliases actually resets it
  # rather than just never touching it.
  PROFILE_ALIASES=([stale]="99")

  run load_profile_aliases "$(fixture load_profile_aliases/no_profiles.yaml)"
  [ "$status" -eq 0 ]

  load_profile_aliases "$(fixture load_profile_aliases/no_profiles.yaml)"
  [ "${#PROFILE_ALIASES[@]}" -eq 0 ]
}
