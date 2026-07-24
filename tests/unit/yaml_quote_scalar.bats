#!/usr/bin/env bats

load helpers/load_declaroid

setup() {
  load_declaroid
}

@test "yaml_quote_scalar: a plain string passes through unescaped" {
  run yaml_quote_scalar "Simple App"
  [ "$status" -eq 0 ]
  [ "$output" = '"Simple App"' ]
}

@test "yaml_quote_scalar: a literal double quote is escaped" {
  run yaml_quote_scalar 'App "Special" Edition'
  [ "$status" -eq 0 ]
  [ "$output" = '"App \"Special\" Edition"' ]
}

@test "yaml_quote_scalar: a backslash is escaped" {
  run yaml_quote_scalar 'C:\Path\App'
  [ "$status" -eq 0 ]
  [ "$output" = '"C:\\Path\\App"' ]
}

@test "yaml_quote_scalar: backslash and double quote together are both escaped" {
  run yaml_quote_scalar 'Weird\Name "Quoted"'
  [ "$status" -eq 0 ]
  [ "$output" = '"Weird\\Name \"Quoted\""' ]
}
