#!/usr/bin/env bats

load helpers/load_e2e

setup_file() {
  DEVICE="$(e2e_device)"
  export DEVICE
  local config
  config="$(fixture config.yaml)"
  export CONFIG="$config"
}

@test "apply --enforce removes an unconfigured app while leaving configured ones installed" {
  # A real, unconfigured app -- sideloaded directly via adb, outside
  # declaroid entirely, so this doesn't depend on any declaroid install
  # path succeeding. Needs to be a genuine non-system pkg, not something
  # is_system_plumbing_pkg would already exempt.
  local apk="$BATS_FILE_TMPDIR/fdroid.apk"
  run curl -fsSL -o "$apk" "https://f-droid.org/F-Droid.apk"
  [ "$status" -eq 0 ]
  run adb -s "$DEVICE" install -r "$apk"
  [ "$status" -eq 0 ]

  run adb -s "$DEVICE" shell pm list packages
  [[ "$output" == *"package:org.fdroid.fdroid"* ]]

  run "$(declaroid_bin)" apply --config "$CONFIG" --device "$DEVICE" --enforce -y -v
  echo "apply --enforce output:"
  echo "$output"
  [ "$status" -eq 0 ]

  run adb -s "$DEVICE" shell pm list packages
  [[ "$output" != *"package:org.fdroid.fdroid"* ]]
  [[ "$output" == *"package:dev.imranr.obtainium.fdroid"* ]]
}
