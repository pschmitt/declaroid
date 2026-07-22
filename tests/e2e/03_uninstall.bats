#!/usr/bin/env bats

load helpers/load_e2e

setup_file() {
  DEVICE="$(e2e_device)"
  export DEVICE
  local config
  config="$(fixture config.yaml)"
  export CONFIG="$config"
}

@test "uninstall removes every configured app" {
  run "$(declaroid_bin)" uninstall --config "$CONFIG" --device "$DEVICE" -y
  [ "$status" -eq 0 ]

  run adb -s "$DEVICE" shell pm list packages
  [[ "$output" != *"package:dev.imranr.obtainium.fdroid"* ]]
}
