# NASty CSI Driver Helm Chart

A [CSI](https://kubernetes-csi.github.io/docs/) driver for [NASty](https://github.com/nasty-project/nasty) — dynamic provisioning of storage volumes in Kubernetes from a bcachefs-based NAS.

## Features

- **Multiple Protocols**: NFS, NVMe-oF, iSCSI, SMB
- **Volume Snapshots**: Create, delete, and restore from snapshots
- **Volume Cloning**: Create new volumes from existing snapshots
- **Volume Expansion**: Resize volumes without pod recreation
- **Volume Retention**: `deleteStrategy: retain` to keep volumes on PVC deletion
- **Volume Adoption**: Migrate volumes between clusters with `markAdoptable` / `adoptExisting`
- **Volume Name Templating**: Customize volume names with Go templates or prefix/suffix
- **Encryption**: Filesystem-level bcachefs encryption validation
- **Configurable Mount Options**: Per-StorageClass mount options

## Prerequisites

- Kubernetes 1.26+
- Helm 3.0+
- A running [NASty](https://github.com/nasty-project/nasty) appliance with an API key
- Protocol-specific:
  - **NFS**: `nfs-common` on all nodes
  - **NVMe-oF**: `nvme-tcp` kernel module
  - **iSCSI**: `open-iscsi` on all nodes
  - **SMB**: `cifs-utils` on all nodes
  - **Snapshots**: [VolumeSnapshot CRDs](https://github.com/kubernetes-csi/external-snapshotter) installed

## Quick Start

```bash
helm install nasty-csi oci://ghcr.io/nasty-project/nasty-csi-driver \
  --namespace kube-system \
  --set nasty.url="wss://YOUR-NASTY-IP/ws" \
  --set nasty.apiKey="YOUR-API-KEY" \
  --set storageClasses[0].filesystem="YOUR-FS-NAME" \
  --set storageClasses[0].server="YOUR-NASTY-IP"
```

## Configuration

### Connection

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nasty.url` | WebSocket URL (`wss://host/ws`) | `""` (required) |
| `nasty.apiKey` | API key from NASty Settings | `""` (required) |
| `nasty.existingSecret` | Existing Secret with `url` and `api-key` keys | `""` |
| `nasty.skipTLSVerify` | Skip TLS verification (self-signed certs) | `false` |

### Storage Classes

Each entry in `storageClasses` creates a Kubernetes StorageClass. Multiple entries per protocol are supported.

| Field | Description | Default |
|-------|-------------|---------|
| `name` | StorageClass name | `nasty-nfs` |
| `protocol` | `nfs`, `nvmeof`, `iscsi`, `smb` | — |
| `enabled` | Create this StorageClass | `true` |
| `filesystem` | bcachefs filesystem name on NASty | `"storage"` |
| `server` | NASty IP/hostname | `""` |
| `reclaimPolicy` | `Delete` or `Retain` | `Delete` |
| `allowVolumeExpansion` | Enable PVC resize | `true` |
| `mountOptions` | Additional mount options | `[]` |
| `deleteStrategy` | `delete` or `retain` (NASty-side) | `""` |
| `compression` | bcachefs compression (`lz4`, `zstd`) | `""` |
| `encryption` | Require encrypted filesystem | `""` |
| `nameTemplate` | Go template for volume names | `""` |
| `namePrefix` / `nameSuffix` | Volume name prefix/suffix | `""` |
| `markAdoptable` | Allow cross-cluster adoption | `""` |
| `adoptExisting` | Adopt existing volumes | `""` |

**Block protocol fields** (NVMe-oF, iSCSI):

| Field | Description | Default |
|-------|-------------|---------|
| `transport` | NVMe-oF transport (`tcp`/`rdma`) | `tcp` |
| `port` | Target port | `4420` / `3260` |
| `fsType` | Filesystem on block device | `ext4` |

**Example — multiple classes:**

```yaml
storageClasses:
  - name: nasty-nfs
    protocol: nfs
    filesystem: "storage"
    server: "10.0.0.1"

  - name: nasty-nfs-retain
    protocol: nfs
    filesystem: "storage"
    server: "10.0.0.1"
    reclaimPolicy: Retain
    deleteStrategy: retain

  - name: nasty-nvme
    enabled: true
    protocol: nvmeof
    filesystem: "storage"
    server: "10.0.0.1"
    transport: tcp
    port: "4420"
    fsType: ext4
```

### Snapshots

| Parameter | Description | Default |
|-----------|-------------|---------|
| `snapshots.enabled` | Enable snapshot support | `false` |
| `snapshots.volumeSnapshotClass.create` | Create VolumeSnapshotClass | `true` |
| `snapshots.volumeSnapshotClass.deletionPolicy` | `Delete` or `Retain` | `Delete` |

Install CRDs first:
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/release-8.2/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
```

## Usage

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes: [ReadWriteMany]
  resources:
    requests:
      storage: 10Gi
  storageClassName: nasty-nfs
```

## Troubleshooting

```bash
# Check pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=nasty-csi-driver

# Controller logs
kubectl logs -n kube-system -l app.kubernetes.io/component=controller -c nasty-csi-driver

# Node logs
kubectl logs -n kube-system -l app.kubernetes.io/component=node -c nasty-csi-driver

# Enable debug
helm upgrade nasty-csi ... --set controller.logLevel=4 --set node.logLevel=4
```

## License

GPL-3.0
