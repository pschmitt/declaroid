#!/usr/bin/env bats

load helpers/load_e2e

setup_file() {
  DEVICE="$(e2e_device)"
  export DEVICE
  local config
  config="$(fixture config.yaml)"
  export CONFIG="$config"
}

@test "apply installs a store: github app and seeds its configured obtainium: repo" {
  echo "GITHUB_TOKEN set: ${GITHUB_TOKEN:+yes}"
  run "$(declaroid_bin)" apply --config "$CONFIG" --device "$DEVICE" -y -v
  echo "apply output:"
  echo "$output"
  [ "$status" -eq 0 ]

  run adb -s "$DEVICE" shell pm list packages
  [[ "$output" == *"package:dev.imranr.obtainium.fdroid"* ]]

  # sync_obtainium_repos launches Obtainium once (if needed) to create its
  # app_data dir, then writes one JSON file per tracked pkg -- this is the
  # exact end-to-end path that two real bugs slipped through earlier (a
  # missing app_data dir right after install, and --enforce uninstalling a
  # tracked-only app), so a real device/emulator run is the point, not
  # just checking the file exists.
  run adb -s "$DEVICE" shell cat "/storage/emulated/0/Android/data/dev.imranr.obtainium.fdroid/files/app_data/org.breezyweather.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"id": "org.breezyweather"'* ]]
  [[ "$output" == *'"url": "https://github.com/breezy-weather/breezy-weather"'* ]]
}

@test "apply is idempotent -- rerunning makes no further changes" {
  run "$(declaroid_bin)" apply --config "$CONFIG" --device "$DEVICE" -y
  [ "$status" -eq 0 ]
}
