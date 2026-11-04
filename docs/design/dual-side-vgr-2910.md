# Dual-side VolumeGroupReplication (Ramen #2910 / VIRTDR-375)

**Status:** Draft / WIP design stub (Phase 1)  
**Issue:** [RamenDR/ramen#2910](https://github.com/RamenDR/ramen/issues/2910)  
**Depends on:** [csi-addons#1180](https://github.com/csi-addons/kubernetes-csi-addons/issues/1180) / [PR #1190](https://github.com/csi-addons/kubernetes-csi-addons/pull/1190)  
**Related:** Global VGR ([PR #2426](https://github.com/RamenDR/ramen/pull/2426), [design](./global-vgr-design-doc.md)), MDR left-behind PVs ([PR #2934](https://github.com/RamenDR/ramen/pull/2934))

This document is the in-repo design stub for protect-time secondary VGR so stop-protection can Disable destination volume groups (PowerStore orphan VG today). Implementation is not complete; expect a feature flag in Phase 2.

## Problem

After stop-protection, destination storage must return to pre-replication for the **volume group**. With only a primary-side VGR, deleting the primary session leaves the dest VG orphaned. Lab proof: secondary VGR + Disable removes the dest VG; primary-only stop does not.

Secondary VRG ManifestWork already exists at protect-time (`EnsureSecondaryReplicationSetup`), but VGR/VGRC/VR and Retain PVs are **not** created on the peer until failover restore or demotion with local PVCs.

## Target object model (protect-time)

| Cluster | Objects |
|---------|---------|
| Primary | VRG primary, PVCs, VGR primary (`external: false`), VGRC + DestInfo, VR primary |
| Secondary | VRG secondary, VGR secondary (`external: false`), pre-bound VGRC (dest handles), VR secondary, **Retain PVs** (`claimRef` nil), **no PVCs** |

## Locked design defaults

1. **Gate:** Non-offloaded `PeerClass.Grouping` + provisioner allowlist (PowerStore). Not Ceph by default. Not Global/offloaded (`external: true`) path.
2. **Dest handles:** Primary VGRC DestInfo → S3 → existing restore helpers; defensive strip of `/arrayId` on secondary group handle.
3. **Retain PVs:** From S3 PV archive + mapping list; reclaimPolicy Retain; claimRef nil at protect-time.
4. **OwnerRef:** Prefer VGR ownerRef for secondary protect-time PVs; learn Retain-safe delete rule from #2934 without conflating Sync left-behind labeling.
5. **DoD:** Dest VG cleanup only (VIRTDR-375); dest volume orphan out of scope.
6. **vs Global VGR:** Shared persist/upload helpers; separate non-external protect-time path.

## Stop-protection order

1. Primary teardown (session gone).
2. Secondary VGR delete → child VR Disable → dest VG gone.
3. Secondary PV delete while keeping reclaimPolicy=Retain (ownerRef GC or explicit).

## Code insertion points (Phase 2+)

| Area | Primary hooks |
|------|----------------|
| Hub secondary MW | `EnsureSecondaryReplicationSetup`, `refreshVRGSecondarySpec` (`drplacementcontrolvolsync.go`) |
| Secondary reconcile | `processAsSecondary`, `reconcileVolGroupRepsAsSecondary` (today no-ops without PVCs) |
| Create VGR | `createOrUpdateVGR` / `createVGR` (`vrg_volgrouprep.go`) with archive-driven handles |
| Dest-info restore | `cleanupVGRCForRestore`, `updateVGRCVolumeHandlesForRestore`, `cleanupPVForRestore` |
| S3 I/O | `uploadVGRandVGRCtoS3Stores`, `UploadVGRC` / `downloadVGRCs`, PV upload/download |
| Gate | PeerClass routing in `drpolicy_peerclass.go` / `separatePVCUsingPeerClassAndSC` |
| Teardown | `processForDeletion` → `reconcileVGRForDeletion` / `deleteVGR` |

Search for `TODO(#2910)` in the tree for marked stubs.

## Non-goals / out of scope for this stub

- Implementing protect-time CR creation (Phase 2)
- Failover binding of PVCs to pre-created PVs (Phase 3)
- Dest array **volume** reclaim policy product decision
- Merging into Global VGR `external: true` machinery

## References

- Work notes: `obsidian/.../virtdr375-dual-side-vgr/phase1-design-notes.md`
- Cursor plan: `.cursor/plans/ramen-2910-dual-side-vgr.plan.md` (local planning only)
