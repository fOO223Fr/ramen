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