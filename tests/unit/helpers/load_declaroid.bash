# Sourced by every unit .bats file. Sources the real script into the test
# shell instead of re-implementing/mocking its logic -- `main` is a no-op
# here because it's guarded by `[[ "${BASH_SOURCE[0]}" == "${0}" ]]`, which
# is only ever true for a direct execve, never for `source`.
load_declaroid() {
  local script="${DECLAROID_SCRIPT:-$BATS_TEST_DIRNAME/../../declaroid}"
  # shellcheck disable=SC1090
  source "$script"
}

fixture() {
  printf '%s/fixtures/%s\n' "$BATS_TEST_DIRNAME" "$1"
}
