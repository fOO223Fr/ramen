#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Script to setup storage classes, pools, and volume replication classes on both clusters

set -e

echo "Creating RBD storage classes and pools on both clusters..."

# Setup rook-pool addon on dr1
echo "Setting up storage resources on dr1..."
cd test/addons/rook-pool && ./start dr1
cd - >/dev/null

echo "✓ Storage resources created on dr1"

# Setup rook-pool addon on dr2  
echo "Setting up storage resources on dr2..."
cd test/addons/rook-pool && ./start dr2
cd - >/dev/null

echo "✓ Storage resources created on dr2"
echo ""

echo "Installing VolumeGroupReplication CRDs (if not present)..."
VGR_CRDS="hack/test/replication.storage.openshift.io_volumegroupreplications.yaml \
          hack/test/replication.storage.openshift.io_volumegroupreplicationclasses.yaml \
          hack/test/replication.storage.openshift.io_volumegroupreplicationcontents.yaml"
for ctx in dr1 dr2; do
  for crd in $VGR_CRDS; do
    kubectl --context=$ctx apply -f "$crd" 2>/dev/null || true
  done
done
echo "✓ VGR CRDs applied"

echo "Installing VolumeGroup CRDs (if present - from kubernetes-csi-addons PR #402 fork)..."
VG_CRDS="hack/test/volumegroup.storage.openshift.io_volumegroups.yaml \
         hack/test/volumegroup.storage.openshift.io_volumegroupclasses.yaml \
         hack/test/volumegroup.storage.openshift.io_volumegroupcontents.yaml"
for ctx in dr1 dr2; do
  for crd in $VG_CRDS; do
    if [[ -f "$crd" ]]; then
      kubectl --context=$ctx apply -f "$crd" 2>/dev/null || true
    fi
  done
done
echo "✓ VolumeGroup CRDs applied (if available)"
echo ""

echo "Creating Volume Replication Classes on both clusters..."

# Create VolumeReplicationClass resources on dr1
kubectl --context=dr1 apply -f test/yaml/objects/volume-replication-class.yaml
echo "✓ Volume Replication Classes created on dr1"

# Create VolumeReplicationClass resources on dr2
kubectl --context=dr2 apply -f test/yaml/objects/volume-replication-class.yaml  
echo "✓ Volume Replication Classes created on dr2"
echo ""

echo "Verifying storage setup..."
echo "DR1 Storage Classes:"
kubectl --context=dr1 get storageclass | grep rook-ceph || echo "  No Ceph storage classes found"
echo "DR1 Volume Replication Classes:"
kubectl --context=dr1 get volumereplicationclass || echo "  No volume replication classes found"
echo "DR2 Storage Classes:" 
kubectl --context=dr2 get storageclass | grep rook-ceph || echo "  No Ceph storage classes found"
echo "DR2 Volume Replication Classes:"
kubectl --context=dr2 get volumereplicationclass || echo "  No volume replication classes found"