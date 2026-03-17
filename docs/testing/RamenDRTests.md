<!--
SPDX-FileCopyrightText: The RamenDR authors
SPDX-License-Identifier: Apache-2.0
-->

# RamenDR Tests Overview

## What This Document Covers

This document describes the **existing functional and integration tests** in the upstream RamenDR project related to **Disaster Recovery (DR) and Replication scenarios**. It does **not** cover:

- **Unit tests** – Controller logic tests in `*_test.go` files (see [testing.md](../testing.md))
- **CSI replication testing additions** – Tests and scripts added in forks or branches for CSI-specific replication (e.g. `test-csi-replication.sh`, `test-csi-failover.sh`, `test-dr-flow.sh`). See [csi-replication-testing.md](./csi-replication-testing.md#test-scenario-map) for a map of scenarios and scripts.

This document focuses on:

- **Basic test** – Python-based DR flow test ([`test/basic-test/`](../../test/basic-test/))
- **End-to-end (E2E) tests** – Go-based DR tests with configurable deployers and workloads ([`e2e/`](../../e2e/))
- **Addon integration tests** – Tests run as part of the drenv environment setup ([`test/addons/*/test`](../../test/addons/))
- **Stress test** – Infrastructure robustness testing ([`test/stress-test/`](../../test/stress-test/))

---

## Test Framework and Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Environment bootstrap** | Python (drenv) | Creates clusters, deploys addons (Rook, OCM, Submariner, etc.) |
| **Basic test** | Python (drenv.test, ramen module) | Orchestrates DR flow; calls kubectl, waits for DRPC status |
| **E2E tests** | Go (standard `testing` package) | Full DR test logic; creates DRPC, validates VRG, performs failover/relocate |
| **Unit tests** (controllers) | Go (Ginkgo/Gomega) | Controller logic; not covered in this document |

**Key point:** The E2E DR tests use Go's standard `testing` package, **not** Ginkgo. Ginkgo is used elsewhere (e.g. controller unit tests). Python is used for environment setup and the basic-test orchestration; Go is used for the E2E test code.

---

## Modules and Components Under Test

| Module | What Is Tested | How |
|--------|----------------|-----|
| **RamenDR Hub Operator** | Running and reachable | TestValidation checks pod in hub |
| **RamenDR DR Cluster Operator** | Running on each managed cluster | TestValidation checks pods in c1, c2 |
| **DRPlacementControl (DRPC)** | Create, update, delete; failover/relocate | E2E dractions create/update DRPC |
| **VolumeReplicationGroup (VRG)** | Status and conditions | E2E reads VRG on managed clusters |
| **Placement (OCM)** | Scheduling, annotations | E2E creates/updates Placement |
| **Application deployment** | Deploy via AppSet/Subscription/DiscoveredApp | E2E deployers |
| **Storage** | StorageClass existence | validateStorageClasses; no direct RBD/CephFS mirror checks |

---

## Storage and CSI Driver Scope: Rook/Ceph Only

**RamenDR tests are not multi-vendor or CSI driver–agnostic.** They assume **Rook/Ceph** storage and are tightly coupled to the regional-dr environment. This differs from the [kubernetes-csi-addons Replication E2E Suite](https://github.com/nadavleva/kubernetes-csi-addons/blob/main/docs/testing/replication-e2e-suite.md), which is **driver-agnostic** and exercises the VolumeReplication CRD and CSI replication APIs against any driver that implements replication (Ceph RBD is one example; others could be used via `STORAGE_CLASS` and `CSI_PROVISIONER`).

| Aspect | RamenDR Tests | kubernetes-csi-addons Replication E2E |
|--------|---------------|--------------------------------------|
| **Storage backend** | Rook/Ceph only (rook-ceph-block, rook-cephfs-fs1) | Any CSI driver with replication support |
| **CRDs under test** | RamenDR (DRPC, VRG, Placement) | VolumeReplication, VolumeReplicationClass |
| **API focus** | RamenDR orchestration, DR lifecycle | CSI replication gRPC APIs (Enable, Disable, Promote, Demote, Resync, GetInfo) |
| **Infrastructure** | Hub, OCM, Submariner, ArgoCD, Velero required | Single cluster or two clusters (DR1_CONTEXT, DR2_CONTEXT) |
| **Test framework** | Go `testing`, Python (drenv) | Ginkgo v2 |
| **Edge scenarios** | None (no NetworkFence, no disconnect) | NetworkFence (L1-E-003), peer unreachable, force modes |
| **Layer-1 test matrix** | Not implemented | Implements Layer-1 CSI Replication Add-on Test Matrix |

---

## Storage Assumptions

### Ceph-Only

All tests assume **Ceph (Rook)** storage:

- **RBD:** `rook-ceph-block` StorageClass
- **CephFS:** `rook-cephfs-fs1` StorageClass

No other storage backends (e.g. NFS, local, other CSI) are exercised.

### RBD Mirror vs CephFS

- **RBD:** Uses Ceph RBD mirroring. The `rbd-mirror` addon configures cross-cluster mirroring. The **rbd-mirror addon test** directly creates a VolumeReplication, waits for primary state, and checks `rbd mirror image status`. The **E2E and basic tests** do not verify RBD mirror status; they rely on RamenDR VRG/DRPC status.
- **CephFS:** Uses VolSync (rsync-based replication) in the regional-dr environment (`volsync: true`). CephFS does not have native cross-cluster mirroring like RBD. The **rook-cephfs addon test** only validates CephFS PVC and snapshot provisioning (single cluster). E2E tests validate that CephFS workloads complete the DR flow.

### What Tests Validate

- StorageClass exists in both managed clusters
- PVCs bind and workloads run
- DR flow completes (Deploy → Enable → Failover → Relocate → Disable → Undeploy)

### What Tests Do Not Validate

- RBD mirror daemon health or image replication state
- CephFS replication mechanism (VolSync)
- Storage-level consistency or RPO/RTO

---

## RamenDR CRDs vs CSI Replication CRDs

Tests use **RamenDR operators and CRDs**, not raw CSI replication CRDs:

| CRD / API | Used by Tests? | Notes |
|-----------|----------------|-------|
| **DRPlacementControl** | Yes | Created/updated by E2E; drives DR lifecycle |
| **VolumeReplicationGroup (VRG)** | Yes | Read by E2E to check replication status |
| **Placement** (OCM) | Yes | Created/updated for scheduling |
| **DRPolicy** | Yes | Referenced in DRPC; validated in ClusterSet |
| **VolumeReplication** (CSI) | No (directly) | RamenDR creates VRs internally; tests do not create or assert on them |
| **VolumeReplicationClass** | No (directly) | Used by RamenDR; tests assume they exist |

RamenDR may use **VolSync** or **CSI replication** under the hood depending on configuration. The regional-dr environment uses VolSync (`volsync: true`). Tests are agnostic to the underlying replication mechanism.

---

## Infrastructure Dependencies: Hub, OCM, Submariner

Tests **require** the full RamenDR stack:

| Component | Required? | Role |
|-----------|-----------|------|
| **Hub cluster** | Yes | OCM hub, Ramen hub operator, Placement, DRPC |
| **OCM (Open Cluster Management)** | Yes | Cluster registration, Placement, managed clusters |
| **Submariner** | Yes | Cross-cluster networking (dr1 ↔ dr2) |
| **ArgoCD** | Yes | Application deployment (AppSet, Subscription) |
| **Velero** | Yes | Backup/restore for DR |
| **MinIO** | Yes | Object storage for Velero |
| **RBD mirror** | Yes | RBD replication between clusters |
| **VolSync** | Yes (regional-dr) | CephFS and other replication |

There is **no** "CSI-only" or "two-cluster-only" mode. All tests expect hub + OCM + Submariner.

---

## Edge Scenarios and Disconnected Clusters

**Disconnected cluster, NetworkFence, and similar edge cases are not covered** by the existing tests.

Tests assume:

- All clusters are reachable
- No network partitions or fencing
- No simulated cluster failures
- No NetworkFence CRs

Scenarios such as:

- Cluster unreachable or fenced
- Split-brain
- Delayed or degraded replication
- Manual demotion/promotion without RamenDR

are **not** tested by the basic test or E2E suite.

---

## E2E Test Specification

### Test Flow (All DR Tests)

Each TestDR subtest runs the same six steps:

1. **Deploy** – Deploy workload (busybox or VM) via the configured deployer
2. **Enable** – Create DRPC, wait for VRG ready, workload healthy
3. **Failover** – Update DRPC preferred cluster to secondary; wait for failover
4. **Relocate** – Update DRPC preferred cluster back to primary; wait for relocate
5. **Disable** – Delete DRPC, wait for cleanup
6. **Undeploy** – Remove workload and related resources

### Test Generation

Tests are generated from [`config.yaml`](../../e2e/config.yaml.sample):

```yaml
tests:
  - deployer: appset
    workload: deploy
    pvcspec: rbd
  - deployer: subscr
    workload: deploy
    pvcspec: cephfs
  # ...
```

**Test name pattern:** `TestDR/{deployer}-{workload}-{pvcspec}-busybox`

### Default Test Matrix (config.yaml.sample)

| Deployer | Workload | Storage | Test Name |
|----------|----------|---------|-----------|
| appset | deploy | rbd | appset-deploy-rbd-busybox |
| appset | deploy | cephfs | appset-deploy-cephfs-busybox |
| subscr | deploy | rbd | subscr-deploy-rbd-busybox |
| subscr | deploy | cephfs | subscr-deploy-cephfs-busybox |
| disapp | deploy | rbd | disapp-deploy-rbd-busybox |
| disapp | deploy | cephfs | disapp-deploy-cephfs-busybox |

### VM Workload (config-vm.yaml.sample)

| Deployer | Workload | Storage | Test Name |
|----------|----------|---------|-----------|
| disapp | vm-pvc | rbd | disapp-vm-pvc-rbd-busybox |
| appset | vm-pvc | rbd | appset-vm-pvc-rbd-busybox |
| subscr | vm-pvc | rbd | subscr-vm-pvc-rbd-busybox |

Requires KubeVirt addon and `envs/regional-dr-kubevirt.yaml`.

### Validation Steps (TestValidation)

- **hub:** Ramen hub operator pod running
- **c1:** Ramen DR cluster operator pod running
- **c2:** Ramen DR cluster operator pod running

### E2E Implementation Notes

- Uses `go test` (see [`e2e/run.sh`](../../e2e/run.sh))
- Config: `config.yaml` (cluster kubeconfigs)
- Channel: Ensures OCM channel for ocm-ramen-samples; cleaned up after tests
- Parallel: Subtests run in parallel (`t.Parallel()`)

---

## Prerequisites

All tests require a running multi-cluster environment. See:

- [local-environment-setup.md](./local-environment-setup.md) – Full regional DR setup (hub, dr1, dr2)
- [test/README.md](../../test/README.md) – Tool installation and drenv usage

---

## 1. Basic Test

**Location:** [`test/basic-test/`](../../test/basic-test/)  
**Type:** Functional integration test  
**Purpose:** Validates a complete DR lifecycle for a busybox application.

### Test Flow

1. **Deploy** – Deploys a busybox application
2. **Enable DR** – Enables disaster recovery for the application
3. **Failover** – Fails over the application to the other cluster
4. **Relocate** – Relocates the application back to the original cluster
5. **Disable DR** – Disables DR protection
6. **Undeploy** – Removes the application

### Requirements

- Regional DR environment (hub, dr1, dr2) with OCM, Submariner, Velero, Ceph
- Channel pointing to [ocm-ramen-samples](https://github.com/RamenDR/ocm-ramen-samples):

  ```sh
  kubectl apply -k https://github.com/RamenDR/ocm-ramen-samples.git/channel?ref=main --context hub
  ```

### Running the Test

```sh
cd test
source ../venv
test/basic-test/run test/envs/regional-dr.yaml
```

### Running Individual Steps

```sh
env=$PWD/test/envs/regional-dr.yaml
test/basic-test/deploy $env
test/basic-test/enable-dr $env
test/basic-test/failover $env  # or relocate, etc.
test/basic-test/undeploy $env
```

For more details, see [testing.md](../testing.md#end-to-end-tests).

---

## 2. End-to-End (E2E) Tests

**Location:** [`e2e/`](../../e2e/)  
**Type:** Functional integration tests (Go, standard testing package)  
**Purpose:** Validates DR flows across multiple deployment methods, workloads, and storage configurations.

### Test Matrix

| Test | Description |
|------|-------------|
| **TestValidation** | Validates hub and managed clusters are accessible and Ramen operators are running ([`e2e/validation_test.go`](../../e2e/validation_test.go)) |
| **TestDR** | Full DR flow per configuration: Deploy → Enable → Failover → Relocate → Disable → Undeploy ([`e2e/dr_test.go`](../../e2e/dr_test.go)) |

### Configuration

Tests are driven by `config.yaml` (see [`e2e/config.yaml.sample`](../../e2e/config.yaml.sample)):

- **Deployers:** `appset`, `subscr`, `disapp` (ApplicationSet, Subscription, Discovered Application)
- **Workloads:** `deploy` (Deployment), `vm-pvc` (VirtualMachine with PVC)
- **Storage (PVCSpecs):** `rbd` (Rook Ceph block), `cephfs` (Rook CephFS)

Test names are generated as `{deployer}-{workload}-{pvcspec}-busybox` (e.g. `subscr-deploy-rbd-busybox`).

### Requirements

- Regional DR environment (hub, dr1, dr2) with OCM, Submariner, Velero, Ceph
- `config.yaml` with cluster kubeconfig paths (see [e2e.md](../e2e.md))

### Running the Tests

```sh
cd e2e
```

**Validate clusters:**

```sh
./run.sh -test.run TestValidation
```

**Run all DR tests:**

```sh
./run.sh -test.run TestDR
```

**Run specific tests:**

```sh
./run.sh -test.run TestDR/subscr-deploy-rbd-busybox
./run.sh -test.run TestDR/appset
./run.sh -test.run TestDR/rbd
```

**VM workload tests** (requires KubeVirt addon):

```sh
./run.sh -config config.yaml  # with config-vm.yaml.sample as template
```

### Typical Duration

~10 minutes for full TestDR suite, depending on hardware.

For full details, see [e2e.md](../e2e.md).

---

## 3. Addon Integration Tests

**Location:** [`test/addons/*/test`](../../test/addons/)  
**Type:** Integration tests (run as part of drenv)  
**Purpose:** Verify each addon deploys and functions correctly.

### Addons with Tests

| Addon | Test | Purpose |
|-------|------|---------|
| **rook-cephfs** | [`test/addons/rook-cephfs/test`](../../test/addons/rook-cephfs/test) | CephFS PVC and VolumeSnapshot provisioning (single cluster) |
| **rbd-mirror** | [`test/addons/rbd-mirror/test`](../../test/addons/rbd-mirror/test) | **Uses CSI VolumeReplication CRD directly** – creates PVC + VR, waits for primary state, verifies RBD image appears on secondary, checks `rbd mirror image status` |
| **submariner** | [`test/addons/submariner/test`](../../test/addons/submariner/test) | Cross-cluster connectivity |
| **velero** | [`test/addons/velero/test`](../../test/addons/velero/test) | Backup/restore |

**Note:** The rbd-mirror addon test is the only one that directly exercises the CSI VolumeReplication CRD and RBD mirror image status. The rook-cephfs test validates CephFS provisioning and snapshots only (no cross-cluster replication).

### How They Run

These tests are invoked automatically when starting an environment:

```sh
drenv start envs/regional-dr.yaml
```

Each addon runs its `start` script, then its `test` script. Failures are reported in the drenv output.

### Manual Execution

```sh
./addons/rook-cephfs/test dr1
./addons/rbd-mirror/test
./addons/submariner/test
./addons/velero/test
```

---

## 4. Stress Test

**Location:** [`test/stress-test/`](../../test/stress-test/)  
**Type:** Infrastructure robustness test  
**Purpose:** Evaluates drenv environment startup reliability over many runs.

### Usage

```sh
cd test
stress-test/run -r 100 ../envs/regional-dr.yaml
```

- Collects stats from multiple runs (e.g. success rate, timing)
- On failure, can delete clusters and continue, or stop for debugging (`-x`)

```sh
stress-test/run -r 100 -x ../envs/regional-dr.yaml  # Stop on first failure for debugging
```

See [`test/stress-test/README.md`](../../test/stress-test/README.md) for details.

---

## Summary

| Test Type | Location | DR/Replication Focus | Typical Use |
|-----------|----------|----------------------|-------------|
| Basic test | [`test/basic-test/`](../../test/basic-test/) | Full DR lifecycle | Quick smoke test |
| E2E tests | [`e2e/`](../../e2e/) | Full DR lifecycle, multiple deployers/workloads | Comprehensive validation |
| Addon tests | [`test/addons/*/test`](../../test/addons/) | RBD mirroring, CephFS, Submariner, Velero | Integration verification |
| Stress test | [`test/stress-test/`](../../test/stress-test/) | Environment startup | Reliability evaluation |

---

## Related Documentation

- [testing.md](../testing.md) – Unit tests and basic test overview
- [e2e.md](../e2e.md) – E2E test configuration and execution
- [local-environment-setup.md](./local-environment-setup.md) – Environment setup for regional DR
- [test/README.md](../../test/README.md) – drenv tool and environment setup
