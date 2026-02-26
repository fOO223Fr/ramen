#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Fix CSI provisioner deployments after upstream merge
# Upstream Rook manifests incorrectly configured csi-rbdplugin-provisioner with CephCSI driver
# This script patches it to use the correct external-provisioner image
#
# All patches target containers by NAME (not index) for robustness.

set -e

# Patch container by name using strategic merge
patch_container() {
    local context=$1
    local resource_type=$2
    local resource_name=$3
    local namespace=$4
    local patch_json=$5
    kubectl --context="$context" patch "$resource_type" "$resource_name" -n "$namespace" \
        --type='strategic' -p="$patch_json" 2>/dev/null || true
}

echo "🔧 Applying CSI provisioner fixes for Rook/Ceph compatibility (post-merge)..."
echo ""

for context in dr1 dr2; do
    echo "📌 Fixing CSI provisioners on $context cluster..."
    
    # ========== FIX csi-rbdplugin-provisioner ==========
    if kubectl --context=$context get deployment -n rook-ceph csi-rbdplugin-provisioner &>/dev/null; then
        echo "  ✓ Patching csi-rbdplugin-provisioner..."
        
        # Fix csi-provisioner image (by name)
        patch_container "$context" deployment csi-rbdplugin-provisioner rook-ceph \
            '{"spec":{"template":{"spec":{"containers":[{"name":"csi-provisioner","image":"registry.k8s.io/sig-storage/csi-provisioner:v5.2.0"}]}}}}'
        
        # Ensure log-collector has correct initialization (by name)
        patch_container "$context" deployment csi-rbdplugin-provisioner rook-ceph \
            '{"spec":{"template":{"spec":{"containers":[{"name":"log-collector","command":["/bin/sh"],"args":["-c","while true; do sleep 3600; done"]}]}}}}'
    fi
    
    # ========== csi-cephfsplugin-provisioner ==========
    if kubectl --context=$context get deployment -n rook-ceph csi-cephfsplugin-provisioner &>/dev/null; then
        echo "  ✓ Patching csi-cephfsplugin-provisioner (multiple image fixes)..."
        
        # Fix csi-attacher image (by name)
        patch_container "$context" deployment csi-cephfsplugin-provisioner rook-ceph \
            '{"spec":{"template":{"spec":{"containers":[{"name":"csi-attacher","image":"registry.k8s.io/sig-storage/csi-attacher:v4.8.1"}]}}}}'
        
        # Fix csi-snapshotter - remove broken "sh" command (by name: get index then json patch)
        idx=$(kubectl --context=$context get deployment csi-cephfsplugin-provisioner -n rook-ceph -o json 2>/dev/null | \
            jq -r '[.spec.template.spec.containers[] | .name] | index("csi-snapshotter")' 2>/dev/null || echo "")
        if [ -n "$idx" ] && [ "$idx" != "null" ]; then
            kubectl --context=$context patch deployment csi-cephfsplugin-provisioner -n rook-ceph --type='json' \
                -p="[{\"op\": \"remove\", \"path\": \"/spec/template/spec/containers/$idx/command\"}]" 2>/dev/null || true
        fi
        
        # Ensure log-collector has correct initialization (by name)
        patch_container "$context" deployment csi-cephfsplugin-provisioner rook-ceph \
            '{"spec":{"template":{"spec":{"containers":[{"name":"log-collector","command":["/bin/sh"],"args":["-c","while true; do sleep 3600; done"]}]}}}}'
    fi
    
    # ========== RESTART PROVISIONER PODS ==========
    echo "  ↻ Restarting provisioner pods to apply changes..."
    
    # Delete rbdplugin provisioner pods to force restart with new specs
    if kubectl --context=$context get deployment -n rook-ceph csi-rbdplugin-provisioner &>/dev/null; then
        kubectl --context=$context delete pods -n rook-ceph -l app=csi-rbdplugin-provisioner --ignore-not-found=true
    fi
    
    # Delete cephfsplugin provisioner pods to force restart with new specs
    if kubectl --context=$context get deployment -n rook-ceph csi-cephfsplugin-provisioner &>/dev/null; then
        kubectl --context=$context delete pods -n rook-ceph -l app=csi-cephfsplugin-provisioner --ignore-not-found=true
    fi
done

echo ""
echo "✅ CSI provisioner fixes applied"
echo "📊 Waiting for provisioner pods to stabilize (30 seconds)..."
sleep 30

echo ""
echo "📋 Final status:"
for context in dr1 dr2; do
    echo ""
    echo "=== $context cluster ==="
    kubectl --context=$context get pods -n rook-ceph -l 'app in (csi-rbdplugin-provisioner,csi-cephfsplugin-provisioner)' --no-headers 2>/dev/null || echo "No provisioner pods found"
done
