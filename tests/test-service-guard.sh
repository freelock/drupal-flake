#!/usr/bin/env bash
# Verify CLI-only hosts cannot start drupal-flake services through public entry points.
set -euo pipefail

expect_blocked() {
  local label="$1"
  shift
  local output
  if output=$(DRUPAL_FLAKE_SERVICES_DISABLED=1 timeout 10s "$@" 2>&1); then
    echo "FAIL: $label succeeded while services were disabled" >&2
    exit 1
  fi
  if ! grep -Fq 'service startup is disabled' <<<"$output"; then
    echo "FAIL: $label did not report the service policy" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

expect_blocked start start
expect_blocked start-detached start-detached
expect_blocked start-demo start-demo
expect_blocked start-config start-config
expect_blocked demo demo

SYSTEM=$(nix eval --impure --raw --expr builtins.currentSystem)
for spec in \
  'default:start-guarded:start-guarded' \
  'detached:detached-guarded:detached-guarded' \
  'config:config-guarded:config-guarded'; do
  IFS=: read -r app package binary <<<"$spec"
  output=$(nix build --impure --no-link --print-out-paths ".#packages.${SYSTEM}.${package}")
  program="$output/bin/$binary"
  declared_program=$(nix eval --impure --raw ".#apps.${SYSTEM}.${app}.program")
  [ "$declared_program" = "$program" ]
  expect_blocked "nix run .#${app}" "$program"
done

echo 'PASS: CLI-only policy blocks all public Drupal service start commands'
