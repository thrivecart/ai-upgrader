#!/usr/bin/env bats

load helpers/setup

setup() {
  setup_ai_test
}

track_files() {
  git add -- "$@"
  git commit -qm "synthetic-$(printf '%s' "$*" | tr ' /' '--')"
}

assert_stack() {
  local runtime="$1" framework="$2" source="$3"
  [ "$status" -eq 0 ]
  grep -q "id: $runtime" .upgrade/manifest.yml
  grep -q "id: $framework" .upgrade/manifest.yml
  grep -q "$source" .upgrade/manifest.yml
  ! grep -Eq 'imaginary|unrelated_stack' .upgrade/manifest.yml
}

@test "synthetic npm package.json and package-lock persist Node and Vue" {
  cat > package.json <<'JSON'
{
  "name": "fixture-app",
  "engines": { "node": "20.11.1" },
  "dependencies": { "vue": "3.4.21" }
}
JSON
  cat > package-lock.json <<'JSON'
{
  "name": "fixture-app",
  "lockfileVersion": 3,
  "packages": {
    "": { "engines": { "node": "20.11.1" } },
    "node_modules/vue": { "version": "3.4.21" }
  }
}
JSON
  track_files package.json package-lock.json
  write_stack_plan node_runtime runtime 20.11.1 22 package.json \
    vue frontend_framework 3.4.21 3.4.21 package-lock.json

  cli_ok init claude
  run_cli plan
  assert_stack node_runtime vue package.json
  grep -q 'package-lock.json' .upgrade/manifest.yml
  ! grep -Eq 'ruby|rails|php|laravel' .upgrade/manifest.yml
}

@test "synthetic Composer composer.json persists PHP and Laravel" {
  cat > composer.json <<'JSON'
{
  "name": "fixture/app",
  "require": {
    "php": "8.2.20",
    "laravel/framework": "10.48.0"
  }
}
JSON
  cat > composer.lock <<'JSON'
{
  "content-hash": "fixture",
  "packages": []
}
JSON
  track_files composer.json composer.lock
  write_stack_plan php runtime 8.2.20 8.3 composer.json \
    laravel framework 10.48.0 10.48.0 composer.json

  cli_ok init claude
  run_cli plan
  assert_stack php laravel composer.json
  grep -q 'composer.lock' .upgrade/manifest.yml
  ! grep -Eq 'node_runtime|vue|ruby|rails' .upgrade/manifest.yml
}

@test "synthetic Gemfile and Gemfile.lock persist Ruby and Rails" {
  cat > Gemfile <<'GEM'
source "https://rubygems.org"
ruby "3.3.5"
gem "rails", "7.2.1"
GEM
  cat > Gemfile.lock <<'LOCK'
GEM
  remote: https://rubygems.org/
  specs:
    rails (7.2.1)
RUBY VERSION
   ruby 3.3.5
LOCK
  track_files Gemfile Gemfile.lock
  write_stack_plan ruby runtime 3.3.5 3.4 Gemfile \
    rails framework 7.2.1 7.2.1 Gemfile.lock

  cli_ok init claude
  run_cli plan
  assert_stack ruby rails Gemfile
  grep -q 'Gemfile.lock' .upgrade/manifest.yml
  ! grep -Eq 'node_runtime|php|laravel' .upgrade/manifest.yml
}

@test "synthetic go.mod persists Go without inventing a framework" {
  cat > go.mod <<'MOD'
module example.com/fixture
go 1.22.5
require golang.org/x/sync v0.8.0
MOD
  track_files go.mod
  write_stack_plan go runtime 1.22.5 1.23 go.mod \
    toolchain other 1.22.5 1.22.5 go.mod

  cli_ok init claude
  run_cli plan

  [ "$status" -eq 0 ]
  grep -q 'id: go' .upgrade/manifest.yml
  grep -q 'go.mod' .upgrade/manifest.yml
  ! grep -Eq 'node_runtime|ruby|php|django|vue' .upgrade/manifest.yml
}

@test "synthetic Cargo.toml persists Rust without cataloguing crates" {
  cat > Cargo.toml <<'TOML'
[package]
name = "fixture"
edition = "2021"
rust-version = "1.80.0"

[dependencies]
serde = "1.0.210"
TOML
  track_files Cargo.toml
  write_stack_plan rust language 1.80.0 1.81 Cargo.toml \
    cargo package_manager 1.80.0 1.80.0 Cargo.toml

  cli_ok init claude
  run_cli plan

  [ "$status" -eq 0 ]
  grep -q 'id: rust' .upgrade/manifest.yml
  grep -q 'Cargo.toml' .upgrade/manifest.yml
  ! grep -q 'serde' .upgrade/manifest.yml
  ! grep -Eq 'node_runtime|rails|laravel' .upgrade/manifest.yml
}

@test "synthetic pyproject.toml persists Python and Django" {
  cat > pyproject.toml <<'TOML'
[project]
name = "fixture"
requires-python = ">=3.11"
dependencies = ["django==5.1.1"]
TOML
  track_files pyproject.toml
  write_stack_plan python runtime 3.11 3.12 pyproject.toml \
    django framework 5.1.1 5.1.1 pyproject.toml

  cli_ok init claude
  run_cli plan
  assert_stack python django pyproject.toml
  ! grep -Eq 'node_runtime|ruby|php' .upgrade/manifest.yml
}

@test "synthetic mix.exs persists Elixir and Phoenix" {
  cat > mix.exs <<'EXS'
defmodule Fixture.MixProject do
  def project do
    [elixir: "~> 1.16", deps: [{:phoenix, "1.7.14"}]]
  end
end
EXS
  track_files mix.exs
  write_stack_plan elixir runtime 1.16 1.17 mix.exs \
    phoenix framework 1.7.14 1.7.14 mix.exs

  cli_ok init claude
  run_cli plan
  assert_stack elixir phoenix mix.exs
  ! grep -Eq 'node_runtime|rails|laravel' .upgrade/manifest.yml
}
