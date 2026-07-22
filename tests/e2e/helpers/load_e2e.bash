# Sourced by every e2e .bats file. Unlike the unit suite (which sources
# declaroid and calls its functions directly, no device needed), e2e runs
# the real built binary as a subprocess against a real booted device/
# emulator -- exercising the actual adb/install/uninstall code paths, not
# just the yq/config logic.

fixture() {
  printf '%s/fixtures/%s\n' "$BATS_TEST_DIRNAME" "$1"
}

# Resolves to the sole connected device -- CI boots exactly one emulator,
# and a local run against real hardware should also only ever have one
# device attached while running this suite (declaroid itself would
# otherwise prompt interactively, which bats can't answer).
e2e_device() {
  local serials
  mapfile -t serials < <(adb devices | awk 'NR>1 && $2=="device" {print $1}')
  if [[ ${#serials[@]} -ne 1 ]]
  then
    echo "e2e: expected exactly one connected adb device, found ${#serials[@]}" >&2
    return 1
  fi
  printf '%s\n' "${serials[0]}"
}

declaroid_bin() {
  printf '%s\n' "${DECLAROID_BIN:-declaroid}"
}
