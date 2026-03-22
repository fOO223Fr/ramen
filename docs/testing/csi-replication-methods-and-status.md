# CSI Replication Methods: Flow, Test Design, and Adoption Status

This document describes each CSI replication method, its operational flow, how the test flow should be structured, and the current adoption/support status across the ecosystem.

> **Scope:** These methods are defined by the [CSI Addons](https://github.com/csi-addons/spec) specification and implemented in [kubernetes-csi-addons](https://github.com/csi-addons/kubernetes-csi-addons). They extend the core CSI specification and are **not** part of the standard CSI spec.

---

## Method Overview

| Method | CRDs Used | dataSource / Source | Use Case |
|--------|-----------|---------------------|----------|
| **1. Single VolumeReplication** | VolumeReplication, VolumeReplicationClass | `dataSource.kind: PersistentVolumeClaim` | Replicate one PVC |
| **2. VolumeGroupEnableReplication** | VolumeGroup, VolumeGroupClass, VolumeGroupContent, VolumeReplication, VolumeReplicationClass | `dataSource.kind: VolumeGroup` | Replicate a group via CSI CreateVolumeGroup |
| **3. VolumeGroupReplication** | VolumeGroupReplication, VolumeGroupReplicationClass, VolumeGroupReplicationContent | `source.selector` (label selector over PVCs) | Replicate a group via one VGR CR |

---

## Method 1: Single VolumeReplication

### Flow

1. User creates a PVC (e.g. `storageClassName: rook-ceph-block`).
2. PVC binds to a PV; CSI driver provisions the volume.
3. User creates a **VolumeReplication** with:
   - `dataSource.kind: PersistentVolumeClaim`
   - `dataSource.name: <pvc-name>`
   - `replicationState: primary`
   - `volumeReplicationClassName: <vrc-name>`
4. CSI Addons controller watches VolumeReplication, calls the CSI driver's replication gRPC (EnableVolumeReplication, etc.).
5. Driver enables replication (e.g. RBD mirroring) on the backend.
6. VolumeReplication status reports `state: Primary`.
7. **Failover:** User patches `replicationState: secondary` on primary cluster; creates PV/PVC on DR cluster; creates VolumeReplication with `replicationState: primary` and promotes.

### Test Flow (Expected)

| Step | Action | Validation |
|------|--------|------------|
| 1 | Create PVC | PVC Bound |
| 2 | Create VolumeReplication (dataSource.kind=PersistentVolumeClaim) | VR created |
| 3 | Wait for Primary state | `status.state == Primary` |
| 4 | Verify RBD mirror status | Image replicating to peer |
| 5 | Demote VR on DR1 | `status.state == Secondary` |
| 6 | Create static PV/PVC on DR2 pointing to replicated image | PVC Bound |
| 7 | Create VR on DR2, promote | `status.state == Primary` |
| 8 | Mount PVC, verify data | Data readable |
| 9 | Cleanup | Resources deleted |

**Test script:** [`test/test-csi-replication.sh`](../../test/test-csi-replication.sh) (infrastructure + single VR), [`test/test-dr-flow.sh`](../../test/test-dr-flow.sh) (full failover).

### Adoption / Support Status

| Component | Status |
|-----------|--------|
| **CSI Addons controller** | ✅ Supported (VolumeReplication since early releases) |
| **Ceph CSI (RBD)** | ✅ Full support |
| **IBM Block CSI** | ✅ Supported (policy-based and non-policy modes) |
| **Dell (PowerMax, PowerStore, PowerScale, PowerFlex)** | ✅ Via Dell CSI Extensions (different stack) |
| **Rook/Ceph** | ✅ Uses Ceph CSI; CRDs from kubernetes-csi-addons |

---

## Method 2: VolumeGroupEnableReplication

### Flow

1. User creates multiple PVCs with labels (e.g. `app: vgr-test`, `replication-group: test`).
2. User creates a **VolumeGroup** with `source.selector` matching those labels.
3. **VolumeGroup controller** (from kubernetes-csi-addons) reconciles the VolumeGroup:
   - Calls CSI `CreateVolumeGroup` gRPC.
   - Driver creates a volume group on the backend (e.g. RBD group).
   - VolumeGroup status gets `boundVolumeGroupContentName` and `ready: true`.
4. User creates a **VolumeReplication** with:
   - `dataSource.kind: VolumeGroup`
   - `dataSource.apiGroup: volumegroup.storage.openshift.io`
   - `dataSource.name: <volume-group-name>`
5. CSI Addons controller uses the VolumeGroup as replication source; driver replicates the group.
6. **Failover:** Demote VR, create PVs/PVCs on DR2, create VolumeGroup + VolumeReplication on DR2, promote.

### Test Flow (Expected)

| Step | Action | Validation |
|------|--------|------------|
| 1 | Create 3 PVCs with labels | All PVCs Bound |
| 2 | Create VolumeGroupClass | VGClass exists |
| 3 | Create VolumeGroup with source.selector | VolumeGroup `ready: true` |
| 4 | Create VolumeReplication (dataSource.kind=VolumeGroup) | VR created |
| 5 | Wait for Primary state | `status.state == Primary` |
| 6 | Write data to all PVCs | Data written |
| 7 | Wait for replication | RBD mirror sync |
| 8 | Demote VR on DR1 | `status.state == Secondary` |
| 9 | Create static PVs/PVCs on DR2 | All Bound |
| 10 | Create VolumeGroup + VR on DR2, promote | `status.state == Primary` |
| 11 | Read data on DR2 | Data consistent |
| 12 | Cleanup | Resources deleted |

**Test script:** [`test/test-csi-volumegroup-enablereplication.sh`](../../test/test-csi-volumegroup-enablereplication.sh) — **currently blocked** (see status below).

### Adoption / Support Status

| Component | Status |
|-----------|--------|
| **CSI Addons controller** | ❌ VolumeGroup controller **not** in official release; PR [#402](https://github.com/csi-addons/kubernetes-csi-addons/pull/402) closed; only in forks (e.g. `add_volume_group_controller` branch) |
| **VolumeGroup CRDs** | ⚠️ CRD YAML in hack/test; controller required for reconciliation |

> **PR #402 vs PR #588:** [PR #402](https://github.com/csi-addons/kubernetes-csi-addons/pull/402) ("adding vg api") proposed the VolumeGroup CRD and controller. It was **closed** (Jun 2024) as "too complex" by maintainers, who chose [PR #588](https://github.com/csi-addons/kubernetes-csi-addons/pull/588) instead—**VolumeGroupReplication** (Method 3)—a simpler API that lets CSI drivers handle grouping via `source.selector`. The VolumeGroup functionality from PR #402 was never merged; the group-replication path in kubernetes-csi-addons is **VolumeGroupReplication**, not VolumeGroup + VolumeReplication.
| **Ceph CSI (RBD)** | ✅ Implements CreateVolumeGroup, VolumeGroupServer (PR #4707, #4719, #5221) |
| **IBM Block CSI** | ⚠️ Uses IBM csi-volume-group-operator (proprietary VolumeGroup CRD); policy-based VR with dataSource.kind=VolumeGroup |
| **Dell** | ❌ No VolumeGroup support |
| **RamenDR tests** | ❌ Cannot run; VolumeGroup controller unavailable |

---

## Method 3: VolumeGroupReplication (VGR)

This is the **chosen path** for group replication in kubernetes-csi-addons (merged via [PR #588](https://github.com/csi-addons/kubernetes-csi-addons/pull/588), Jun 2024), replacing the more complex VolumeGroup approach from PR #402.

### Flow

1. User creates multiple PVCs with labels (e.g. `app: vgr-test`, `replication-group: test`).
2. User creates a **VolumeGroupReplication** with:
   - `volumeGroupReplicationClassName: <vgrc-name>`
   - `volumeReplicationClassName: <vrc-name>` (for per-volume replication)
   - `replicationState: primary`
   - `source.selector` matching the PVC labels
3. **VGR controller** (from kubernetes-csi-addons) reconciles the VGR:
   - Finds PVCs matching the selector.
   - Creates **VolumeGroupReplicationContent**; the **VGRC controller** calls CSI **VolumeGroup** gRPC (`CreateVolumeGroup`, membership updates) so the backend has a group handle.
   - After the group handle exists, creates a **VolumeReplication** whose replication source is the **volume group** (not a single PVC); the **VolumeReplication** controller calls **EnableVolumeReplication** (and related RPCs) on that group source.
4. Driver is expected to enable **group-consistent** replication on the backend (e.g. RBD group mirroring). Behavior depends on ceph-csi correctly handling `ReplicationSource_VolumeGroup` in the replication service (see **Known issues** below).
5. **Failover:** Demote VGR on DR1; create PVs/PVCs on DR2; create VGR on DR2 with same selector; promote.

### Test Flow (Expected)

| Step | Action | Validation |
|------|--------|------------|
| 1 | Create VolumeGroupReplicationClass (vgrc-2m) | VGRClass exists |
| 2 | Create 3 PVCs with labels | All PVCs Bound |
| 3 | Create VolumeGroupReplication with source.selector | VGR created |
| 4 | Wait for VGR Primary state | `status.state == Primary` |
| 5 | Verify VolumeGroupReplicationContent created | VGRC exists |
| 6 | Write data to all PVCs | Data written |
| 7 | Wait for replication | RBD mirror sync |
| 8 | Demote VGR on DR1 | `status.state == Secondary` |
| 9 | Create static PVs/PVCs on DR2 | All Bound |
| 10 | Create VGR on DR2 with same selector, promote | `status.state == Primary` |
| 11 | Read data on DR2 | Data consistent |
| 12 | Cleanup | Resources deleted |

**Test script:** [`test/test-csi-volumegroupreplication.sh`](../../test/test-csi-volumegroupreplication.sh) — validates VGR flow (source.selector, VGRC, failover).

### CSI-addons Identity: there is no `VOLUME_GROUP_REPLICATION` capability

The [CSI-addons Identity `GetCapabilities`](https://github.com/csi-addons/spec/blob/main/identity/identity.proto) API does **not** define a separate capability enum for “volume group replication.” Group replication is expressed in the **replication** gRPC (e.g. a volume-group id in `ReplicationSource`), not as a distinct Identity capability string.

**What kubernetes-csi-addons actually requires** (see upstream controllers):

| Controller / step | Identity capability checked |
|-------------------|------------------------------|
| **VolumeGroupReplicationContent** | `VolumeGroup` → **`VOLUME_GROUP`** (and related `volume_group.*` lines the driver registers) |
| **VolumeReplication** (child CR used by VGR) | `VolumeReplication` → **`VOLUME_REPLICATION`** |

On a **Rook/Ceph** cluster, both are expected on the **RBD provisioner** `CSIAddonsNode` (controller pod). Typical `CSIAddonsNode.status.capabilities` strings look like `volume_group.VOLUME_GROUP`, `volume_group.MODIFY_VOLUME_GROUP`, `volume_replication.VOLUME_REPLICATION`, etc.—**not** `volume_group_replication.*`.

**Heuristic scripts** that grep only for a substring such as `volume_group_replication` can report “missing VGR support” even when the driver advertises the **correct pair** above. Prefer checking **`volume_replication` + `volume_group.VOLUME_GROUP`** on the provisioner node, or use the expanded checks in [`scripts/check_cluster_csi_capabilities.sh`](../../scripts/check_cluster_csi_capabilities.sh) (`--mode volumegroupreplication`).

### Known issues (Ceph CSI / VGR)

| Issue | Summary |
|-------|---------|
| [ceph-csi#6190](https://github.com/ceph/ceph-csi/issues/6190) | **`EnableVolumeReplication` with `ReplicationSource_VolumeGroup`:** ceph-csi treats the **group handle as a volume id** (`GetVolumeByID`-style path), causing **NotFound / “volume not found”** and VGR stuck in **Unknown**. The same mishandling may affect other group replication RPCs until fixed in the driver image you run. |

Until the driver handles group replication sources correctly, **VGR can fail at the replication step** even when CRDs, kubernetes-csi-addons, and `CSIAddonsNode` connectivity look healthy.

### Adoption / Support Status

| Component | Status |
|-----------|--------|
| **CSI Addons controller** | ⚠️ VGR controller: scaffolding in v0.9.0; **broken in v0.12.0** (no reaction to VGR events); **working from v0.13.0** |
| **VGR CRDs** | ✅ In official kubernetes-csi-addons releases |
| **Ceph CSI (RBD)** | ⚠️ Implements VolumeGroup + VolumeReplication CSI-addons services and VGRC-oriented flows; **group `EnableVolumeReplication` broken in reported releases** ([#6190](https://github.com/ceph/ceph-csi/issues/6190)). Treat **image tag + release notes** as the source of truth, not a single “minimum version.” |
| **IBM Block CSI** | ❌ Uses VolumeGroup + VR (Method 2), not VGR |
| **Dell** | ❌ Uses DellCSIReplicationGroup; different architecture |
| **RamenDR** | ⚠️ Depends on csi-addons version; sidecar **v0.11.x** may limit VGR behavior vs **v0.13+** |

---

## Summary Table: Method vs Support

| Method | CSI Addons | Ceph CSI | IBM | Dell | Test Status |
|--------|------------|----------|-----|------|-------------|
| **1. Single VR** | ✅ | ✅ | ✅ | ✅ (Dell stack) | ✅ `test-csi-replication`, `test-dr-flow` |
| **2. VolumeGroupEnableReplication** | ❌ (no controller) | ✅ | ⚠️ (IBM operator) | ❌ | ❌ Blocked |
| **3. VolumeGroupReplication** | ⚠️ (v0.13+) | ⚠️ (group replication RPCs: [#6190](https://github.com/ceph/ceph-csi/issues/6190); Identity uses `volume_group.*` + `volume_replication`, not `VOLUME_GROUP_REPLICATION`) | ❌ | ❌ | ✅ `test-csi-volumegroupreplication` (driver must implement group source correctly) |

---

## Footnote: RamenDR VolumeReplicationGroup (VRG)

**RamenDR VolumeReplicationGroup (VRG)** is a **proprietary** RamenDR CRD, not part of the CSI or CSI Addons specifications.

| Attribute | Value |
|-----------|-------|
| **API** | `ramendr.openshift.io/v1alpha1` |
| **Kind** | `VolumeReplicationGroup` |
| **Purpose** | Application-level DR orchestration; groups PVCs and Kubernetes objects for protection |
| **Relationship to CSI** | VRG controller **uses** CSI replication under the hood: it creates and manages **VolumeReplication** or **VolumeGroupReplication** resources based on DRPolicy configuration. RamenDR does not replace CSI; it orchestrates it. |
| **Backends** | Supports async replication via CSI VolumeReplication/VolumeGroupReplication (Ceph RBD), VolSync (rsync), or Velero (snapshot/restore) |

The RamenDR VRG is an orchestration layer that:

- Selects PVCs to protect (e.g. via label selectors or namespace).
- Chooses the replication method (CSI replication, VolSync, or Velero) based on DRPolicy and StorageClass/VolumeReplicationClass labels.
- Creates and reconciles VolumeReplication or VolumeGroupReplication when CSI replication is used.
- Manages failover/failback workflows across clusters.
- Optionally protects Kubernetes objects (ConfigMaps, Secrets, etc.) via Velero with configurable capture/recover order.

For CSI replication testing, the focus is on the underlying CSI methods (1–3 above). RamenDR VRG is the consumer/orchestrator, not the storage replication API itself.

---

## References

- [CSI Addons Specification](https://github.com/csi-addons/spec)
- [kubernetes-csi-addons](https://github.com/csi-addons/kubernetes-csi-addons)
- [PR #402](https://github.com/csi-addons/kubernetes-csi-addons/pull/402) — VolumeGroup API (closed; functionality not merged)
- [PR #588](https://github.com/csi-addons/kubernetes-csi-addons/pull/588) — VolumeGroupReplication scaffolding (merged; chosen path)
- [ceph-csi#6190](https://github.com/ceph/ceph-csi/issues/6190) — VGR: `EnableVolumeReplication` mishandles `ReplicationSource_VolumeGroup` (group handle vs volume id)
- [CSI Replication Testing Guide](./csi-replication-testing.md)
- [RamenDR VRG Type Sequence](../design/VRG-TypeSequence.md)
