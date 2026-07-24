#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
}

@test "build_searchable: tokenizes a realistic 'adb devices -l' line for device-query matching" {
  run build_searchable "10.5.0.159:35036 device usb:1-2 product:clover model:MI_PAD_4 device:clover transport_id:5"
  [ "$status" -eq 0 ]
  [[ "$output" == *"10.5.0.159:35036"* ]]
  [[ "$output" == *"1-2"* ]]
  [[ "$output" == *"clover"* ]]
  [[ "$output" == *"MI_PAD_4"* ]]
}

@test "build_searchable: output is consumed as a case-insensitive substring match, same as resolve_devices does" {
  # Mirrors resolve_devices's own usage: build_searchable's result is never
  # field-parsed back out, only substring-matched via
  # [[ "${searchable,,}" == *"${query,,}"* ]] -- verify that actually holds
  # for a query matching the model, case-insensitively (query "mi_pad_4"
  # against a searchable string containing "MI_PAD_4").
  run build_searchable "10.5.0.159:35036 device usb:1-2 product:clover model:MI_PAD_4 device:clover transport_id:5"
  [ "$status" -eq 0 ]
  local searchable="$output"

  [[ "${searchable,,}" == *"mi_pad_4"* ]]
  [[ "${searchable,,}" != *"nonexistent-query"* ]]
}

@test "build_searchable: a line with a field missing (no usb:) still produces the fields that are present" {
  run build_searchable "emulator-5554 device product:sdk_gphone64_x86_64 model:sdk_gphone64_x86_64 device:emu64xa"
  [ "$status" -eq 0 ]
  [[ "$output" == *"emulator-5554"* ]]
  [[ "$output" == *"sdk_gphone64_x86_64"* ]]
  [[ "$output" == *"emu64xa"* ]]
}
