#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
values="$repo_root/tests/cases/all-protocols.yaml"
error_output=$(mktemp)
trap 'rm -f "$error_output"' EXIT

expect_failure() {
  local name=$1
  shift

  if helm template schema-test "$repo_root" --values "$values" "$@" > /dev/null 2>"$error_output"; then
    echo "$name unexpectedly passed schema validation" >&2
    exit 1
  fi
  if ! grep -q "values don't meet the specifications" "$error_output"; then
    echo "$name failed outside schema validation" >&2
    printf '%s\n' "$(<"$error_output")" >&2
    exit 1
  fi
}

expect_failure string-boolean --set-string controller.metrics.enabled=false
expect_failure invalid-log-level --set controller.logLevel=6
expect_failure invalid-protocol --set-string 'storageClasses[0].protocol=bogus'
expect_failure missing-credentials --set-string nasty.existingSecret=
expect_failure missing-filesystem --set-string 'storageClasses[0].filesystem='
expect_failure missing-server --set-string 'storageClasses[0].server='
