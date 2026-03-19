# CSI Replication Testing Guide

This guide covers setting up and testing CSI volume replication functionality using RamenDR's Rook/Ceph environment.

> **Relationship to RamenDR tests:** These tests are **CSI replication testing additions** – scripts added in forks or branches for CSI-specific replication. They are distinct from the upstream RamenDR tests (basic test, E2E, addon tests) described in [RamenDRTests.md](./RamenDRTests.md#what-this-document-covers). See the "CSI replication testing additions" bullet in that document.

> **Replication methods reference:** For a detailed explanation of each CSI replication method (single VR, VolumeGroup+VR, VolumeGroupReplication), their flows, expected test design, and adoption status, see [CSI Replication Methods and Status](./csi-replication-methods-and-status.md).

## Test Scenario Map

The following scripts cover CSI replication scenarios. Use this map to choose which test to run for a given scenario:

| Scenario | Script | Make Target | What It Covers |
|----------|--------|-------------|----------------|
| **Infrastructure validation** | [`test/test-csi-replication.sh`](../../test/test-csi-replication.sh) | `make test-csi-replication` | CSI Addons controller, VolumeReplicationClass, StorageClass; PVC creation; VolumeReplication (primary); RBD mirror status; cross-cluster image verification |
| **Volume state transitions** | [`test/test-csi-failover.sh`](../../test/test-csi-failover.sh) | `make test-csi-failover` | Demote (primary → secondary); promote (secondary → primary); failback; VR state validation; RBD mirror state across clusters |
| **Full DR failover flow** | [`test/test-dr-flow.sh`](../../test/test-dr-flow.sh) | `make test-dr-flow` | Primary workload on DR1 with RBD mirroring; failover to DR2; K8s object (PVC/VR) recreation on DR2; application access to replicated data |
| **VolumeGroupReplication (VGR)** | [`test/test-csi-volumegroupreplication.sh`](../../test/test-csi-volumegroupreplication.sh) | `make test-csi-volumegroupreplication` | Validate VolumeGroupReplication. One VGR CR with source.selector; controller creates VGRC and per-volume VRs. Requires CSI Addons v0.13+. |
| **VolumeGroupEnableReplication** | [`test/test-csi-volumegroup-enablereplication.sh`](../../test/test-csi-volumegroup-enablereplication.sh) | `make test-csi-volumegroup-enablereplication` | Validate VolumeGroup + VolumeReplication. (1) VolumeGroup via CSI CreateVolumeGroup, (2) VolumeReplication with dataSource.kind=VolumeGroup. **Blocked:** requires VolumeGroup CRD/controller from kubernetes-csi-addons PR #402 fork. |

### Quick Reference

| Scenario | Command |
|----------|---------|
| Validate replication setup | `make test-csi-replication` |
| Test demote/promote | `make test-csi-failover` |
| Test complete DR failover | `make test-dr-flow` |
| Validate VolumeGroupReplication (VGR) | `make test-csi-volumegroupreplication` |
| Validate VolumeGroupEnableReplication (blocked) | `make test-csi-volumegroup-enablereplication` |

---

## Overview

The CSI replication testing environment provides:
- **Two Kubernetes clusters** (dr1, dr2) with Ceph RBD storage
- **Cross-cluster RBD mirroring** for volume replication
- **CSI Addons controllers** for volume replication management
- **Ready-to-use test framework** for validating replication functionality

## Quick Start

### 1. Setup Environment

```bash
# Setup complete CSI replication environment (20-30 minutes)
make setup-csi-replication
```

This command automatically:
- ✅ Creates dr1 + dr2 Kubernetes clusters with Rook/Ceph
- ✅ Deploys CSI Addons controllers with TLS fixes applied
- ✅ Sets up RBD storage classes and pools (`rook-ceph-block`)
- ✅ Creates Volume Replication Classes (`vrc-1m`, `vrc-5m`)
- ✅ Configures cross-cluster RBD mirroring
- ✅ Validates all components are working

**Fast reset (clusters already running):** Use `make reset-csi-replication-state` (~2-5 min) to clean test resources and re-apply storage + RBD mirroring without full setup.

### 2. Run Tests

```bash
# Test CSI replication functionality
make test-csi-replication

# Test volume failover (demote/promote workflow)
make test-csi-failover

# Or run directly
bash test/test-csi-replication.sh
bash test/test-csi-failover.sh
```

### 3. Check Status

```bash
# Check cluster and resource status
make status-csi-replication

# Check specific resources
kubectl --context=dr1 get storageclass
kubectl --context=dr1 get volumereplicationclass
kubectl --context=dr1 get csiaddonsnode -A
```

## What Gets Tested

The test script validates:

### ✅ **Infrastructure Components**
1. **CSI Addons Controller**: Verifies controller is running and accessible
2. **Volume Replication Classes**: Confirms VRCs are available for replication
3. **Storage Classes**: Validates Ceph RBD storage classes are functional

### ✅ **Volume Operations**
4. **PVC Creation**: Creates and binds a test PVC to Ceph RBD storage
5. **Volume Replication**: Creates VolumeReplication resource for cross-cluster sync
6. **Replication Status**: Validates primary/secondary replication state
7. **Failover Testing**: Demotes primary to secondary, promotes secondary to primary
8. **Failback Testing**: Reverses the failover to original state

### ✅ **Cross-Cluster Verification**
7. **RBD Mirroring**: Checks RBD mirror daemon and peer connectivity  
8. **Mirror Status**: Displays detailed replication status and health
9. **Secondary Cluster**: Verifies replicated resources exist on dr2
10. **Failover Flow**: Tests demote/promote operations between clusters

### ✅ **Cleanup**
11. **Resource Cleanup**: Properly removes test resources with finalizer handling

## Expected Test Output

```
=== CSI Replication Health Check ===

1. Checking CSI Addons Controller...
NAME                                             READY   STATUS    RESTARTS   AGE
csi-addons-controller-manager-xxx               1/1     Running   0          2h

2. Checking VolumeReplicationClass...
NAME                            PROVISIONER                  AGE
vrc-1m                          rook-ceph.rbd.csi.ceph.com   45m
vrc-5m                          rook-ceph.rbd.csi.ceph.com   45m

3. Creating test PVC...
persistentvolumeclaim/test-replication-pvc created

4. Waiting for PVC to be Bound...
persistentvolumeclaim/test-replication-pvc condition met

5. Creating VolumeReplication...
volumereplication.replication.storage.openshift.io/test-volume-replication created

6. Checking VolumeReplication status...
NAME                      AGE   VOLUMEREPLICATIONCLASS   SOURCEKIND              SOURCENAME             DESIREDSTATE   CURRENTSTATE
test-volume-replication   10s   vrc-1m                   PersistentVolumeClaim   test-replication-pvc   primary        Primary

VolumeReplication detailed status:
  state: Primary
  message: volume is promoted to primary and replicating to secondary

7. Checking RBD image replication status...
RBD Image: csi-vol-def1f65a-bfd2-4759-a65f-4f1c9424de4f
  state:       up+stopped
  description: local image is primary
  peer_sites:
    state: up+replaying
    description: replaying (receiving replication data)

8. Verifying cross-cluster replication...
✓ DR2 RBD image found: csi-vol-def1f65a-bfd2-4759-a65f-4f1c9424de4f
✓ DR2 mirror status: up+replaying

=== Cleanup ===
✓ VolumeReplication removed
✓ PVC removed
```

### Failover Test Output

The `make test-csi-failover` command demonstrates a complete disaster recovery scenario:

```
=== CSI Volume Replication Failover Test ===

🔄 ================ STARTING FAILOVER PROCESS ================

6. DEMOTING volume on DR1 (primary → secondary)...
✓ Demote request sent

==================== POST-DEMOTE STATE - DR1 NOW SECONDARY ====================

📊 VOLUME REPLICATION STATUS (dr1):
NAME                        AGE   VOLUMEREPLICATIONCLASS   SOURCEKIND              SOURCENAME         DESIREDSTATE   CURRENTSTATE
test-failover-replication   2m    vrc-1m                   PersistentVolumeClaim   test-failover-pvc  secondary      Secondary

🌐 RBD MIRROR STATUS (dr1):
  state:       up+replaying
  description: replaying (receiving replication data from peer)

8. PROMOTING volume on DR2 (creating as primary)...
✓ Promote request sent

==================== POST-PROMOTE STATE - DR2 NOW PRIMARY ====================

📊 VOLUME REPLICATION STATUS (dr2):
NAME                        AGE   VOLUMEREPLICATIONCLASS   SOURCEKIND              SOURCENAME         DESIREDSTATE   CURRENTSTATE
test-failover-replication   1m    vrc-1m                   PersistentVolumeClaim   test-failover-pvc  primary        Primary

🌐 RBD MIRROR STATUS (dr2):
  state:       up+stopped
  description: local image is primary (sending replication data)

🔄 ================ STARTING FAILBACK PROCESS ================

🎉 ================ DEMOTE/PROMOTE TEST COMPLETED ================

📊 SUMMARY:
✅ Initial setup: DR1 Primary with cross-cluster RBD mirroring
✅ Demote: DR1 → Secondary (volume becomes degraded)  
✅ Promote: DR1 → Primary (volume restored to healthy)
✅ RBD mirroring maintained throughout state changes
```

**Key Observations:**
- **State Transitions**: Primary → Secondary → Primary work correctly
- **Volume Status**: Shows "degraded" when secondary, "healthy" when primary
- **RBD Mirroring**: Cross-cluster replication maintained throughout
- **Detailed Logging**: Complete status before/after each operation
- **Fast Recovery**: State changes complete in ~5 seconds each

## Manual Testing Scenarios

### Scenario 1: Basic Volume Replication

```bash
# Create PVC
kubectl --context=dr1 apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-test-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 2Gi
  storageClassName: rook-ceph-block
EOF

# Create VolumeReplication
kubectl --context=dr1 apply -f - <<EOF
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplication
metadata:
  name: my-test-replication
spec:
  volumeReplicationClass: vrc-1m
  dataSource:
    kind: PersistentVolumeClaim
    name: my-test-pvc
  replicationState: primary
  autoResync: true
EOF

# Monitor status
kubectl --context=dr1 get volumereplication my-test-replication -w
```

### Scenario 2: Failover Testing

```bash
# Change to secondary state (simulates failover)
kubectl --context=dr1 patch volumereplication my-test-replication \
  --type='merge' -p='{"spec":{"replicationState":"secondary"}}'

# Promote on dr2 (create corresponding VR as primary)
kubectl --context=dr2 apply -f - <<EOF
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplication
metadata:
  name: my-test-replication
spec:
  volumeReplicationClass: vrc-1m
  dataSource:
    kind: PersistentVolumeClaim
    name: my-test-pvc
  replicationState: primary
  autoResync: true
EOF
```

### Capability Check Script

The script `scripts/check_cluster_csi_capabilities.sh` (renamed from `check_networkfence.sh`) detects cluster capabilities for CSI replication. Use `--mode` to select checks:

| Mode | Description |
|------|-------------|
| `networkfence` (default) | NetworkFence CRDs, CSIAddonsNode, NetworkFence RPC capabilities |
| `replication` | VolumeReplication CRD, VolumeReplicationClass CRD, CSIAddonsNode capability for replication |
| `volumegroupreplication` | VGR/VGRC/VGRClass CRDs, replication capability, VolumeGroupReplication capability in CSIAddonsNode |
| `all` | All of the above |

```bash
# Check network fence (default)
./scripts/check_cluster_csi_capabilities.sh

# Check CSI replication addon
./scripts/check_cluster_csi_capabilities.sh --mode replication

# Check VolumeGroupReplication support
./scripts/check_cluster_csi_capabilities.sh --mode volumegroupreplication

# Check all capabilities
./scripts/check_cluster_csi_capabilities.sh --mode all
```

### CRD and Controller Source

VolumeReplication and VolumeGroupReplication CRDs come from **kubernetes-csi-addons**, not from Ceph or Rook.

- **Rook PR #10777** (Sept 2022): Rook removed the volume replication sidecar and CRDs from its build. Users must install CRDs from kubernetes-csi-addons.
- **Ceph CSI driver** still supports replication via gRPC APIs; the CRDs and controller come from kubernetes-csi-addons.
- If CRDs are missing, install from kubernetes-csi-addons (e.g. `deploy/controller/crds.yaml` or equivalent from release manifests).

### Scenario 3: Application with Replicated Storage

```bash
# Deploy application using replicated PVC
kubectl --context=dr1 apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-app
  template:
    metadata:
      labels:
        app: test-app
    spec:
      containers:
      - name: app
        image: busybox:latest
        command: ["/bin/sh", "-c", "while true; do echo $(date) >> /data/log.txt; sleep 5; done"]
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: my-test-pvc
EOF

# Verify data is being written
kubectl --context=dr1 exec deploy/test-app -- tail /data/log.txt

# Check that data is being replicated to dr2
# (after failover, the data should be available)
```

### Scenario 4: Group Replication (VolumeGroup + VolumeReplication)

**Context:** Uses VolumeGroup (not VolumeGroupReplication) and VolumeReplication. Flow: (1) Create VolumeGroup via CSI CreateVolumeGroup, (2) Create VolumeReplication with dataSource.kind=VolumeGroup. Ceph-csi implements VolumeGroupServer and VolumeReplicationServer (with volumegroup support).

**Target approach:** VolumeGroup CRD + VolumeReplication with dataSource.kind=VolumeGroup.

#### Test Flow

| Step | Action |
|------|--------|
| 1 | Create PVCs with labels (app: vgr-test, replication-group: test) |
| 2 | Create VolumeGroup with source.selector matching those labels |
| 3 | VolumeGroup controller: CreateVolumeGroup via CSI → status.boundVolumeGroupContentName |
| 4 | Create VolumeReplication with dataSource.kind=VolumeGroup, dataSource.name=<VolumeGroup name> |
| 5 | Wait for VolumeReplication Primary state |
| 6 | Failover: demote VR, create PVs/PVCs on DR2, create VolumeGroup + VolumeReplication on DR2 |

#### Key Requirements

- VolumeGroup CRD (volumegroup.storage.openshift.io) - from kubernetes-csi-addons PR #402 (closed) or fork
- VolumeReplication with dataSource.apiGroup=volumegroup.storage.openshift.io, dataSource.kind=VolumeGroup
- VolumeGroup controller must be deployed (from kubernetes-csi-addons fork with add_volume_group_controller branch)

#### Example VolumeReplication

```yaml
apiVersion: replication.storage.openshift.io/v1alpha1
kind: VolumeReplication
spec:
  replicationState: primary
  dataSource:
    apiGroup: volumegroup.storage.openshift.io
    kind: VolumeGroup
    name: "volume-group-name"
  volumeReplicationClassName: "rbd-volumereplicationclass"
  autoResync: true
```

## Environment Management

### Available Make Targets

```bash
# Setup and management
make setup-csi-replication         # Complete environment setup (20-30 min)
make start-csi-replication        # Start existing clusters
make reset-csi-replication-state  # Fast reset (~2-5 min): clean VRs/VGRs/PVCs, re-apply storage + RBD mirroring
make stop-csi-replication         # Stop clusters (keep VMs)
make delete-csi-replication       # Delete clusters completely

# Configuration and fixes
make fix-csi-addons-tls         # Apply TLS configuration fixes
make setup-csi-storage-resources # Setup storage classes and VRCs

# Testing and status
make test-csi-replication       # Run replication tests
make test-csi-volumegroupreplication  # Validate VolumeGroupReplication (VGR)
make status-csi-replication     # Check cluster status
make check-csi-capabilities     # Check cluster CSI capabilities (mode: all)
```

### Advanced Setup Options

```bash
# Use different VM driver (if available)
export vm=docker
make setup-csi-replication

# Use different network configuration
export network=custom-bridge
make setup-csi-replication
```

## Troubleshooting

### Common Issues

#### 1. PVC Not Binding
```bash
# Check storage class
kubectl --context=dr1 get storageclass

# Check provisioner logs  
kubectl --context=dr1 -n rook-ceph logs deploy/csi-rbdplugin-provisioner

# If storage classes missing, run:
make setup-csi-storage-resources
```

#### 2. VolumeReplication Stuck in Unknown State
```bash
# Check VR status details
kubectl --context=dr1 describe volumereplication <name>

# Check CSI Addons controller logs
kubectl --context=dr1 -n csi-addons-system logs deploy/csi-addons-controller-manager

# Apply TLS fix if needed
make fix-csi-addons-tls
```

#### 3. RBD Mirroring Not Working
```bash
# Check mirror daemon status
kubectl --context=dr1 -n rook-ceph get pods | grep mirror
kubectl --context=dr2 -n rook-ceph get pods | grep mirror

# Check mirror pool status
kubectl --context=dr1 -n rook-ceph exec -it deploy/rook-ceph-tools -- \
  rbd mirror pool status replicapool
```

#### 4. VolumeReplication: Unknown State / "image not found"

If VolumeReplication resources show `Unknown` state with "image not found" or "rbd: ret=-2, No such file or directory":

- **VolumeReplicationClass**: Ensure `rbd-volumereplicationclass` exists with `mirroringMode: snapshot` and `schedulingInterval` (e.g. 2m). Run `make setup-csi-storage-resources` if needed.
- **RBD metadata**: Allow 30s after PVC creation before creating VRs. The test script includes this wait.
- **Re-run setup**: Run `make reset-csi-replication-state` and retry.

#### 4b. VolumeReplication / VGR: Empty State / "no leader for the ControllerService"

If VR or VGR state is empty and CSI Addons logs show "no leader for the ControllerService of driver rook-ceph.rbd.csi.ceph.com":

**Root cause:** The CSI Addons controller cannot reach the RBD sidecar. The controller needs a CSIAddonsNode for the **deployment** (csi-rbdplugin-provisioner), not just the daemonset. When only the daemonset CSIAddonsNode exists, the controller has no CONTROLLER_SERVICE/VolumeGroup capability.

**Fix:** The reset script now waits up to 45s for the sidecar leader and restarts the CSI Addons controller to force reconnection. If you still see the error:

```bash
make restart-csi-service   # Forces leader re-election and controller reconnection
make test-csi-volumegroupreplication
```

**Recommended flow:** `make reset-csi-replication-state && make test-csi-volumegroupreplication` (reset includes controller restart now).

**Detailed guide:** See [VGR No Leader Fix Guide](./VGR-NO-LEADER-FIX-GUIDE.md) for full diagnostic steps, expected vs problem state, and architecture context.

#### 5. DR Flow: VR Never Reaches Primary on DR2

If `test-dr-flow` fails at step 17 (VolumeReplication on DR2 stays empty) and CSI Addons logs show "no leader for the ControllerService" or "no connection":

**Root cause:** The csi-addons addon was switched from the cg-support fork (Nikhil-Ladha) back to official kubernetes-csi-addons. The cg-support fork broke single VolumeReplication flow. `make reset-csi-replication-state` and `make start-csi-replication` now run fix-csi-addons-versions and fix-csi-addons-tls automatically.

```bash
make fix-csi-addons-tls
make restart-csi-service
make reset-csi-replication-state
make test-dr-flow
```

#### 6. Mirroring Health WARNING (1 unknown)

If `image_health: WARNING` and `states: {'unknown': 1}` block setup or tests:

```bash
# Clean all mirrored images (removes unknown/error state)
make cleanup-replicated-images

# Or run full reset
make reset-csi-replication-state
```

The `test-dr-flow` cleanup now runs `cleanup-replicated-images` automatically to avoid leaving orphaned images.

#### 7. VR Degraded / "mirroring is not enabled" / "failed to get last sync info"

If VolumeReplication shows Degraded or briefly "mirroring is not enabled":

- **flattenMode**: The VRC now includes `flattenMode: force` to handle parent images. Run `make reset-csi-replication-state` to pick up the updated VRC.
- **Check CSI logs** (from project root):
  ```bash
  # CSI Addons controller
  kubectl --context=dr1 logs -n csi-addons-system deploy/csi-addons-controller-manager --tail=100
  kubectl --context=dr2 logs -n csi-addons-system deploy/csi-addons-controller-manager --tail=100

  # csi-addons and csi-rbdplugin containers (replication/mirroring)
  RBD_POD=$(kubectl --context=dr1 get pods -n rook-ceph -l app=csi-rbdplugin-provisioner -o jsonpath='{.items[0].metadata.name}')
  kubectl --context=dr1 logs -n rook-ceph $RBD_POD -c csi-addons --tail=80
  kubectl --context=dr1 logs -n rook-ceph $RBD_POD -c csi-rbdplugin --tail=80 | grep -iE "mirror|replicat|error"
  ```
- **RBD mirror pool status**:
  ```bash
  kubectl --context=dr1 -n rook-ceph exec deploy/rook-ceph-tools -- rbd mirror pool status replicapool --verbose
  ```

#### 8. Cleanup Issues (Finalizers)
```bash
# Remove finalizers if resources stuck
kubectl --context=dr1 patch volumereplication <name> \
  --type='merge' -p='{"metadata":{"finalizers":[]}}'

kubectl --context=dr1 patch pvc <name> \
  --type='merge' -p='{"metadata":{"finalizers":[]}}'
```

### Diagnostic Commands

```bash
# Check all CSI and replication resources
kubectl --context=dr1 get csiaddonsnode,volumereplicationclass,storageclass -A
kubectl --context=dr2 get csiaddonsnode,volumereplicationclass,storageclass -A

# Check Ceph cluster health
kubectl --context=dr1 -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
kubectl --context=dr2 -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status

# Check RBD images and mirroring
kubectl --context=dr1 -n rook-ceph exec -it deploy/rook-ceph-tools -- \
  rbd ls replicapool
kubectl --context=dr1 -n rook-ceph exec -it deploy/rook-ceph-tools -- \
  rbd mirror pool info replicapool
```

## Architecture Details

### Components Overview

```
┌─────────────────┐         ┌─────────────────┐
│   Cluster DR1   │◄────────┤   Cluster DR2   │
│                 │ Mirror  │                 │
│ ┌─────────────┐ │  Sync   │ ┌─────────────┐ │
│ │   Rook      │ │◄────────┤ │   Rook      │ │
│ │   Ceph      │ │         │ │   Ceph      │ │
│ │   Storage   │ │         │ │   Storage   │ │
│ └─────────────┘ │         │ └─────────────┘ │
│                 │         │                 │
│ ┌─────────────┐ │         │ ┌─────────────┐ │
│ │CSI Addons   │ │         │ │CSI Addons   │ │
│ │Controller   │ │         │ │Controller   │ │
│ └─────────────┘ │         │ └─────────────┘ │
│                 │         │                 │
│ ┌─────────────┐ │         │ ┌─────────────┐ │
│ │Volume       │ │         │ │Volume       │ │
│ │Replication  │ │         │ │Replication  │ │
│ │Resources    │ │         │ │Resources    │ │
│ └─────────────┘ │         │ └─────────────┘ │
└─────────────────┘         └─────────────────┘
```

### Storage Flow

1. **PVC Creation** → Ceph RBD volume provisioned
2. **VolumeReplication** → CSI Addons controller enables RBD mirroring  
3. **RBD Mirroring** → Cross-cluster replication starts
4. **Status Updates** → Controllers report replication health

### Replication States

- **Primary**: Volume accepts writes and replicates to peer
- **Secondary**: Volume receives replication data from primary  
- **Unknown**: Initial state or error condition

## Integration with RamenDR

This CSI replication testing environment provides the foundation for RamenDR's disaster recovery capabilities:

- **Volume Replication**: Validates underlying CSI replication API
- **Cross-cluster Storage**: Tests Rook/Ceph mirroring functionality  
- **Failover Scenarios**: Provides basis for DR failover testing
- **Performance Testing**: Framework for replication performance validation

For full RamenDR disaster recovery testing, see [local-environment-setup.md](./local-environment-setup.md).

## Contributing

When extending the CSI replication testing:

1. **Test Scripts**: Add new test scenarios to `test/test-csi-replication.sh`
2. **Make Targets**: Add convenience targets to the main `Makefile`
3. **Documentation**: Update this guide with new testing procedures
4. **Examples**: Provide working examples for complex scenarios

## References

- **CSI Volume Replication**: [CSI Addons Documentation](https://github.com/csi-addons/kubernetes-csi-addons)
- **Rook Ceph**: [Rook Documentation](https://rook.io/docs/rook/latest/)
- **RBD Mirroring**: [Ceph RBD Mirroring Guide](https://docs.ceph.com/en/latest/rbd/rbd-mirroring/)
- **RamenDR**: [RamenDR Documentation](https://github.com/RamenDR/ramen)