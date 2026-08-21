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
    | awk 'NF { print }' \
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
if ! grep -qx 'provisioner: storage.example.com' "$actual_dir/custom-driver.yaml"; then
  echo "custom-driver did not use csiDriverName for the StorageClass" >&2
  exit 1
fi

render_case release-namespace \
  --show-only templates/secret.yaml \
  --show-only templates/metrics-service.yaml

assert_namespace() {
  local expected=$1
  shift
  local output="$actual_dir/namespace-$expected.yaml"

  helm template golden "$repo_root" \
    --namespace golden-system \
    --values "$repo_root/tests/cases/release-namespace.yaml" \
    --set controller.dashboard.enabled=true \
    --set controller.dashboard.ingress.enabled=true \
    --set-string controller.dashboard.filesystem=dashboard-tank \
    --set controller.metrics.serviceMonitor.enabled=true \
    --set grafana.dashboards.enabled=true \
    --set openshift.enabled=true \
    --set-string 'storageClasses[0].protocol=smb' \
    --set-string 'storageClasses[0].smbCredentialsSecret.name=smb-credentials' \
    "$@" \
    >"$output"

  if invalid=$(grep -E '(^[[:space:]]+namespace: |system:serviceaccount:)' "$output" \
      | grep -Ev "namespace: \"?$expected\"?$|system:serviceaccount:$expected:"); then
    echo "rendered resources outside the expected namespace $expected:" >&2
    echo "$invalid" >&2
    exit 1
  fi
  if ! grep -q -- '--dashboard-filesystem=dashboard-tank' "$output"; then
    echo "controller.dashboard.filesystem was not rendered" >&2
    exit 1
  fi
}

assert_namespace golden-system
assert_namespace override-system --set-string namespace=override-system

render_case explicit-false \
  --show-only templates/storageclass.yaml
if ! grep -qx 'allowVolumeExpansion: false' "$actual_dir/explicit-false.yaml"; then
  echo "explicit-false did not preserve allowVolumeExpansion=false" >&2
  exit 1
fi

render_case metrics-disabled \
  --show-only templates/controller.yaml

metrics_output="$actual_dir/metrics-disabled-all.yaml"
helm template golden "$repo_root" \
  --namespace golden-system \
  --values "$repo_root/tests/cases/metrics-disabled.yaml" \
  >"$metrics_output"
if grep -Eq -- '--metrics-addr|name: golden-nasty-csi-metrics|kind: ServiceMonitor' "$metrics_output"; then
  echo "metrics-disabled rendered a metrics endpoint or resource" >&2
  exit 1
fi

render_case all-protocols \
  --show-only templates/storageclass.yaml

render_case upgrade-compatibility \
  --is-upgrade \
  --show-only templates/csidriver.yaml \
  --show-only templates/storageclass.yaml \
  --show-only templates/node.yaml \
  --show-only templates/volumesnapshotclass.yaml

if grep -q 'legacy.example.com' "$actual_dir/upgrade-compatibility.yaml"; then
  echo "upgrade-compatibility used the legacy driverName value" >&2
  exit 1
fi
if ! grep -qx 'provisioner: storage.example.com' "$actual_dir/upgrade-compatibility.yaml"; then
  echo "upgrade-compatibility did not preserve csiDriverName" >&2
  exit 1
fi
if ! grep -qx 'allowVolumeExpansion: false' "$actual_dir/upgrade-compatibility.yaml"; then
  echo "upgrade-compatibility did not preserve allowVolumeExpansion=false" >&2
  exit 1
fi
if ! grep -qx '  namespace: kube-system' "$actual_dir/upgrade-compatibility.yaml"; then
  echo "upgrade-compatibility did not preserve the explicit namespace" >&2
  exit 1
fi

helm template install-matrix "$repo_root" \
  --namespace golden-system \
  --values "$repo_root/tests/cases/all-protocols.yaml" \
  >/dev/null

upgrade_output="$actual_dir/upgrade-compatibility-all.yaml"
helm template upgrade-matrix "$repo_root" \
  --namespace golden-system \
  --is-upgrade \
  --values "$repo_root/tests/cases/upgrade-compatibility.yaml" \
  >"$upgrade_output"
if grep -Eq -- '--metrics-addr|name: upgrade-matrix-nasty-csi-metrics|kind: ServiceMonitor' "$upgrade_output"; then
  echo "upgrade-compatibility re-enabled metrics" >&2
  exit 1
fi
