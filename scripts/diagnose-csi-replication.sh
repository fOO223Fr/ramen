#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Comprehensive CSI Replication Diagnostics
# Identifies and reports on issues preventing VolumeReplication from working

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

diagnose_cluster() {
    local context="$1"
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Diagnostics for $context${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # 1. Check cluster connectivity
    echo -e "${PURPLE}1. Cluster Connectivity${NC}"
    if kubectl --context=$context cluster-info &>/dev/null; then
        echo -e "${GREEN}✓ Cluster accessible${NC}"
    else
        echo -e "${RED}✗ Cluster not accessible${NC}"
        return 1
    fi
    echo ""
    
    # 2. Check CSI services exist (Rook may use different service names; provisioner pods are the key)
    echo -e "${PURPLE}2. CSI Services (rook-ceph namespace)${NC}"
    local svc_rbd="missing"
    kubectl --context=$context -n rook-ceph get svc 2>/dev/null | grep -q csi-rbdplugin-provisioner && svc_rbd="found"
    local svc_cephfs="missing"
    kubectl --context=$context -n rook-ceph get svc 2>/dev/null | grep -q csi-cephfsplugin-provisioner && svc_cephfs="found"
    
    if [ "$svc_rbd" = "found" ]; then
        echo -e "${GREEN}✓ csi-rbdplugin-provisioner service${NC}"
    else
        echo -e "${YELLOW}⚠ csi-rbdplugin-provisioner service not found (Rook may use different naming; run: make restart-csi-service to create)${NC}"
    fi
    
    if [ "$svc_cephfs" = "found" ]; then
        echo -e "${GREEN}✓ csi-cephfsplugin-provisioner service${NC}"
    else
        echo -e "${YELLOW}⚠ csi-cephfsplugin-provisioner service not found (optional for RBD replication)${NC}"
    fi
    echo ""
    
    # 3. Check provisioner pods
    echo -e "${PURPLE}3. CSI Provisioner Pods (rook-ceph namespace)${NC}"
    local rbd_pods=$(kubectl --context=$context -n rook-ceph get pods -l app=csi-rbdplugin-provisioner -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    if [ -n "$rbd_pods" ]; then
        echo -e "${GREEN}✓ RBD provisioner pod(s):${NC} $rbd_pods"
        
        # Check if running
        for pod in $rbd_pods; do
            local status=$(kubectl --context=$context -n rook-ceph get pod $pod -o jsonpath='{.status.phase}' 2>/dev/null)
            if [ "$status" = "Running" ]; then
                echo -e "  ${GREEN}✓${NC} $pod is Running"
            else
                echo -e "  ${RED}✗${NC} $pod is $status"
            fi
        done
    else
        echo -e "${RED}✗ No RBD provisioner pods found${NC}"
    fi
    echo ""
    
    # 4. Check sidecar-leader status
    echo -e "${PURPLE}4. CSI-Addons Sidecar-Leader Status${NC}"
    if [ -n "$rbd_pods" ]; then
        local pod=$(echo $rbd_pods | cut -d' ' -f1)
        local leader_status=$(kubectl --context=$context -n rook-ceph logs $pod -c csi-addons 2>/dev/null | grep -i "obtained leader" | tail -1 || echo "")
        
        if [ -n "$leader_status" ]; then
            echo -e "${GREEN}✓ Leader elected${NC}"
            echo "  $leader_status"
        else
            echo -e "${YELLOW}⚠ Leader status unclear${NC}"
            echo "  Checking recent logs..."
            kubectl --context=$context -n rook-ceph logs $pod -c csi-addons --tail=5 2>/dev/null | grep -i "leader\|error" || echo "  (No leader-related messages found)"
        fi
    else
        echo -e "${RED}✗ Cannot check sidecar - no pods running${NC}"
    fi
    echo ""
    
    # 5. Check CSI-Addons controller
    echo -e "${PURPLE}5. CSI-Addons Controller${NC}"
    local ctrl_pod=$(kubectl --context=$context -n csi-addons-system get pods -l control-plane=controller-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "$ctrl_pod" ]; then
        local ctrl_status=$(kubectl --context=$context -n csi-addons-system get pod $ctrl_pod -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$ctrl_status" = "Running" ]; then
            echo -e "${GREEN}✓ Controller pod running: $ctrl_pod${NC}"
        else
            echo -e "${RED}✗ Controller pod not running: $ctrl_status${NC}"
        fi
        
        # Check for errors
        local errors=$(kubectl --context=$context -n csi-addons-system logs $ctrl_pod --tail=50 2>/dev/null | grep -i "error\|failed" | head -5 || echo "")
        if [ -n "$errors" ]; then
            echo -e "${RED}Recent errors in controller:${NC}"
            echo "$errors" | sed 's/^/  /'
        else
            echo -e "${GREEN}✓ No recent errors in controller logs${NC}"
        fi
    else
        echo -e "${RED}✗ CSI-Addons controller pod not found${NC}"
    fi
    echo ""
    
    # 6. Check VolumeReplicationClasses
    echo -e "${PURPLE}6. VolumeReplicationClasses${NC}"
    local vrcs=$(kubectl --context=$context get volumereplicationclass -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$vrcs" ]; then
        echo -e "${GREEN}✓ VolumeReplicationClasses found:${NC}"
        for vrc in $vrcs; do
            echo "  - $vrc"
        done
    else
        echo -e "${RED}✗ No VolumeReplicationClasses found${NC}"
    fi
    echo ""
    
    # 7. Check VolumeReplication objects
    echo -e "${PURPLE}7. VolumeReplication Objects${NC}"
    local vrs=$(kubectl --context=$context get volumereplication -A -o json 2>/dev/null)
    local vr_count=$(echo "$vrs" | jq '.items | length')
    
    if [ "$vr_count" -gt 0 ]; then
        echo -e "${YELLOW}Found $vr_count VolumeReplication object(s):${NC}"
        echo "$vrs" | jq -r '.items[] | "\(.metadata.namespace)/\(.metadata.name): state=\(.status.state // "EMPTY")"' | sed 's/^/  /'
        
        # Check for any with empty state
        local empty_count=$(echo "$vrs" | jq '[.items[] | select(.status.state == null or .status.state == "")] | length')
        if [ "$empty_count" -gt 0 ]; then
            echo -e "${RED}⚠ $empty_count object(s) with EMPTY state${NC}"
            echo -e "${RED}  This indicates the controller hasn't reconciled them yet${NC}"
        fi
    else
        echo -e "${YELLOW}No VolumeReplication objects (expected if test not running)${NC}"
    fi
    echo ""
    
    # 8. Check RBD images (use replicapool for CSI replication tests)
    echo -e "${PURPLE}8. RBD Images${NC}"
    local rbd_pool="replicapool"
    local images=""
    images=$(kubectl --context=$context -n rook-ceph exec deploy/rook-ceph-tools -- rbd ls $rbd_pool --format=json 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
    if [ -n "$images" ]; then
        echo -e "${GREEN}✓ RBD images in $rbd_pool pool:${NC}"
        echo "$images" | head -5 | sed 's/^/  - /'
    else
        echo -e "${YELLOW}No RBD images in $rbd_pool (or error accessing Ceph)${NC}"
    fi
    echo ""

    # 9. CSIAddonsNode and "no leader" detection (critical for VGR/VR)
    echo -e "${PURPLE}9. CSIAddonsNode (controller→sidecar connection)${NC}"
    local node_count
    node_count=$(kubectl --context=$context get csiaddonsnode -A -o name 2>/dev/null | wc -l)
    if [ "${node_count:-0}" -gt 0 ]; then
        echo -e "${GREEN}✓ $node_count CSIAddonsNode resource(s)${NC}"
        kubectl --context=$context get csiaddonsnode -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,DRIVER:.spec.driver.name 2>/dev/null | head -8
    else
        echo -e "${RED}✗ No CSIAddonsNode - controller cannot reach sidecars. Run: make restart-csi-service${NC}"
    fi
    echo ""
    local no_leader
    no_leader=$(kubectl --context=$context -n csi-addons-system logs deployment/csi-addons-controller-manager --tail=100 2>/dev/null | grep -c "no leader for the ControllerService" || echo "0")
    if [ "${no_leader:-0}" -gt 0 ]; then
        echo -e "${RED}⚠ 'no leader' errors in controller logs ($no_leader recent) - VGR/VR will fail. Run: make restart-csi-service${NC}"
        echo ""
    fi
}

main() {
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}          CSI Replication Diagnostics Report${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Diagnose both clusters
    diagnose_cluster "dr1"
    diagnose_cluster "dr2"
    
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Recommendations:${NC}"
    echo ""
    echo "If you see ✗ (errors):"
    echo "  1. Missing services? Run: make restart-csi-service"
    echo "  2. No leader elected? Run: make restart-csi-service"
    echo "  3. No CSIAddonsNode or 'no leader' errors? Run: make restart-csi-service"
    echo "  4. Controller errors? Check: kubectl --context=dr1 -n csi-addons-system logs -f deployment/csi-addons-controller-manager"
    echo "  5. VR/VGR with EMPTY state? Run: make restart-csi-service  # forces controller to reconnect to sidecars"
    echo ""
    echo "For VGR test (make test-csi-volumegroupreplication):"
    echo "  • If VGR state stays <none> with 'no leader' in controller logs → make restart-csi-service"
    echo "  • Recommended flow: make reset-csi-replication-state && make restart-csi-service && make test-csi-volumegroupreplication"
    echo ""
}

main
