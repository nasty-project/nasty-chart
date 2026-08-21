#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
actual_dir=$(mktemp -d)
trap 'rm -rf "$actual_dir"' EXIT

render_case() {
  local name=$1
  shift

  helm template golden "$repo_root" \
    --namespace golden-system \
    --values "$repo_root/tests/cases/$name.yaml" \
    --set-string image.tag=GOLDEN \
    "$@" \
    | sed -E \
        -e 's/(helm.sh\/chart: nasty-csi-driver-).*/\1VERSION/' \
        -e 's/(app.kubernetes.io\/version: ).*/\1"VERSION"/' \
    | awk 'NF { while (blank > 0) { print ""; blank-- } print; next } { blank++ }' \
        >"$actual_dir/$name.yaml"

  if [[ ${UPDATE_GOLDEN:-0} == 1 ]]; then
    cp "$actual_dir/$name.yaml" "$repo_root/tests/golden/$name.yaml"
  else
    diff -u "$repo_root/tests/golden/$name.yaml" "$actual_dir/$name.yaml"
  fi
}

render_case custom-driver \
  --show-only templates/csidriver.yaml \
  --show-only templates/storageclass.yaml \
  --show-only templates/node.yaml \
  --show-only templates/volumesnapshotclass.yaml
render_case release-namespace \
  --show-only templates/secret.yaml \
  --show-only templates/metrics-service.yaml
render_case explicit-false \
  --show-only templates/storageclass.yaml
render_case metrics-disabled \
  --show-only templates/controller.yaml

if helm template golden "$repo_root" \
  --namespace golden-system \
  --values "$repo_root/tests/cases/metrics-disabled.yaml" \
  | grep -Eq -- '--metrics-addr|name: golden-nasty-csi-metrics|kind: ServiceMonitor'; then
  echo "metrics-disabled rendered a metrics endpoint or resource" >&2
  exit 1
fi

render_case all-protocols \
  --show-only templates/storageclass.yaml
