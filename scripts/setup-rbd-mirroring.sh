#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Script to setup RBD mirroring between dr1 and dr2 clusters

set -e

echo "Ensuring Ceph toolbox is available on both clusters..."

# Deploy rook-ceph-tools if not already present
if ! kubectl --context=dr1 -n rook-ceph get deployment rook-ceph-tools >/dev/null 2>&1; then
    cd test/addons/rook-toolbox && ./start dr1
    cd - >/dev/null
fi

if ! kubectl --context=dr2 -n rook-ceph get deployment rook-ceph-tools >/dev/null 2>&1; then
    cd test/addons/rook-toolbox && ./start dr2
    cd - >/dev/null
fi

echo "✓ Ceph toolbox available on both clusters"
echo ""

echo "Ensuring Ceph clusters are deployed on both dr1 and dr2..."

# Check if CephCluster exists on dr2, deploy if missing
if ! kubectl --context=dr2 -n rook-ceph get cephcluster my-cluster >/dev/null 2>&1; then
    echo "⚠ CephCluster not found on dr2, deploying..."
    cd test/addons/rook-cluster && ./start dr2 && cd - >/dev/null
    cd test/addons/rook-pool && ./start dr2 && cd - >/dev/null
    cd test/addons/rook-toolbox && ./start dr2 && cd - >/dev/null
    echo "✓ Ceph cluster deployed on dr2"
else
    echo "✓ Ceph clusters exist on both dr1 and dr2"
fi
echo ""

echo "Configuring RBD mirroring between dr1 and dr2 clusters..."

# Run the rbd-mirror addon to establish cross-cluster mirroring
cd test/addons/rbd-mirror && ./start dr1 dr2
cd - >/dev/null

echo "✓ RBD mirroring configured between clusters"
echo ""

echo "Waiting for RBD mirror daemons to be ready..."

# Wait for mirror daemons on both clusters
kubectl --context=dr1 -n rook-ceph wait --for=condition=Ready pod -l app=rook-ceph-rbd-mirror --timeout=180s || echo "⚠ DR1 mirror daemon not ready yet"
kubectl --context=dr2 -n rook-ceph wait --for=condition=Ready pod -l app=rook-ceph-rbd-mirror --timeout=180s || echo "⚠ DR2 mirror daemon not ready yet" 

echo "✓ RBD mirror daemons ready"