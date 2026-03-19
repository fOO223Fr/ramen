#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# CSI Replication Layer Monitoring Script
# Focuses purely on CSI replication infrastructure without RamenDR orchestration
# Monitors: CSI Addons, Storage Classes, VRCs, RBD Mirroring, Ceph clusters

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check contexts for CSI replication environment
check_contexts() {
    if [ -z "$KUBECONFIG" ]; then
        echo -e "${YELLOW}⚠️  KUBECONFIG not set, using default: ~/.kube/config${NC}"
        export KUBECONFIG=~/.kube/config
    fi
    
    local required_contexts=("dr1" "dr2")
    
    for ctx in "${required_contexts[@]}"; do
        if ! kubectl config get-contexts -o name | grep -q "^$ctx$"; then
            echo -e "${RED}❌ Required context '$ctx' not found${NC}"
            echo "Available contexts:"
            kubectl config get-contexts -o name
            echo ""
            echo -e "${YELLOW}💡 To create CSI replication environment:${NC}"
            echo "  make setup-csi-replication"
            echo "  # or manually:"
            echo "  minikube start --profile=$ctx"
            echo "  minikube update-context --profile=$ctx"
            exit 1
        fi
    done
    
    echo -e "${GREEN}✅ CSI replication contexts available: dr1, dr2${NC}"
}

# Comprehensive CSI replication monitoring
comprehensive_csi_monitoring() {
    clear
    echo "KUBECONFIG: $KUBECONFIG"
    echo "CURRENT_CONTEXT: $(kubectl config current-context 2>/dev/null || echo 'No context set')"

    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}              🔍 CSI REPLICATION INFRASTRUCTURE MONITORING                     ${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    # Timestamp
    echo -e "${CYAN}📅 $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""

    # CLUSTER INFRASTRUCTURE
    echo -e "${BLUE}=== CLUSTER INFRASTRUCTURE ===${NC}"
    echo "🏗️ Contexts:"
    kubectl config get-contexts | head -n 1  # Header
    kubectl config get-contexts | grep -E "(dr1|dr2)" || echo "  No CSI replication contexts found"
    echo ""
    
    echo "📊 Cluster Nodes:"
    echo "DR1 Cluster:"
    kubectl --context=dr1 get nodes -o wide 2>/dev/null || echo "  DR1 cluster not accessible"
    echo "DR2 Cluster:" 
    kubectl --context=dr2 get nodes -o wide 2>/dev/null || echo "  DR2 cluster not accessible"
    echo ""

    # CSI ADDONS CONTROLLERS
    echo -e "${YELLOW}=== CSI ADDONS CONTROLLERS ===${NC}"
    echo "🎛️ CSI Addons Controller (DR1):"
    kubectl --context=dr1 get pods,deployment -n csi-addons-system 2>/dev/null || echo "  CSI Addons not found on dr1"
    echo "🎛️ CSI Addons Controller (DR2):"
    kubectl --context=dr2 get pods,deployment -n csi-addons-system 2>/dev/null || echo "  CSI Addons not found on dr2"
    echo ""
    
    echo "🔌 CSI Addons Node Resources (DR1):"
    kubectl --context=dr1 get csiaddonsnode -A -o wide 2>/dev/null || echo "  No CSIAddonsNode resources found on dr1"
    echo "🔌 CSI Addons Node Resources (DR2):"
    kubectl --context=dr2 get csiaddonsnode -A -o wide 2>/dev/null || echo "  No CSIAddonsNode resources found on dr2"
    echo ""

    # STORAGE CLASSES AND VRCs
    echo -e "${PURPLE}=== STORAGE CLASSES & VOLUME REPLICATION ===${NC}"
    echo "💾 Storage Classes (DR1):"
    kubectl --context=dr1 get storageclass -o wide 2>/dev/null | grep -E "(NAME|rook-ceph)" || echo "  No Ceph storage classes found"
    echo "💾 Storage Classes (DR2):"
    kubectl --context=dr2 get storageclass -o wide 2>/dev/null | grep -E "(NAME|rook-ceph)" || echo "  No Ceph storage classes found"
    echo ""
    
    echo "🔄 Volume Replication Classes (DR1):"
    kubectl --context=dr1 get volumereplicationclass -o custom-columns=NAME:.metadata.name,DRIVER:.spec.provisioner 2>/dev/null || echo "  No VolumeReplicationClasses found"
    echo "🔄 Volume Replication Classes (DR2):"
    kubectl --context=dr2 get volumereplicationclass -o custom-columns=NAME:.metadata.name,DRIVER:.spec.provisioner 2>/dev/null || echo "  No VolumeReplicationClasses found"
    echo ""
    
    echo "📸 Volume Snapshot Classes (DR1):"
    kubectl --context=dr1 get volumesnapshotclass -o wide 2>/dev/null || echo "  No VolumeSnapshotClasses found"
    echo "📸 Volume Snapshot Classes (DR2):"
    kubectl --context=dr2 get volumesnapshotclass -o wide 2>/dev/null || echo "  No VolumeSnapshotClasses found"
    echo ""

    # CEPH STORAGE INFRASTRUCTURE
    echo -e "${GREEN}=== CEPH STORAGE INFRASTRUCTURE ===${NC}"
    echo "🏗️ Ceph Cluster Health (DR1):"
    kubectl --context=dr1 -n rook-ceph get cephcluster -o wide 2>/dev/null || echo "  No CephCluster found on dr1"
    echo "🏗️ Ceph Cluster Health (DR2):"
    kubectl --context=dr2 -n rook-ceph get cephcluster -o wide 2>/dev/null || echo "  No CephCluster found on dr2"
    echo ""
    
    echo "💾 Ceph Block Pools (DR1):"
    kubectl --context=dr1 -n rook-ceph get cephblockpool -o wide 2>/dev/null || echo "  No CephBlockPool found on dr1"
    echo "💾 Ceph Block Pools (DR2):"
    kubectl --context=dr2 -n rook-ceph get cephblockpool -o wide 2>/dev/null || echo "  No CephBlockPool found on dr2"
    echo ""

    # RBD MIRRORING STATUS
    echo -e "${YELLOW}=== RBD MIRRORING STATUS ===${NC}"
    echo "🪞 RBD Mirror Daemons (DR1):"
    kubectl --context=dr1 -n rook-ceph get pods -l app=rook-ceph-rbd-mirror 2>/dev/null || echo "  No RBD mirror pods found on dr1"
    echo "🪞 RBD Mirror Daemons (DR2):"
    kubectl --context=dr2 -n rook-ceph get pods -l app=rook-ceph-rbd-mirror 2>/dev/null || echo "  No RBD mirror pods found on dr2"
    echo ""
    
    echo "🔄 RBD Mirroring Health (DR1):"
    local rbd_dr1=""
    rbd_dr1=$(kubectl --context=dr1 -n rook-ceph exec deploy/rook-ceph-tools -- rbd mirror pool status replicapool 2>/dev/null) || true
    if [[ -n "$rbd_dr1" ]]; then echo "$rbd_dr1" | head -10; else echo "  Cannot check RBD mirror status on dr1"; fi
    echo "🔄 RBD Mirroring Health (DR2):"
    local rbd_dr2=""
    rbd_dr2=$(kubectl --context=dr2 -n rook-ceph exec deploy/rook-ceph-tools -- rbd mirror pool status replicapool 2>/dev/null) || true
    if [[ -n "$rbd_dr2" ]]; then echo "$rbd_dr2" | head -10; else echo "  Cannot check RBD mirror status on dr2"; fi
    # Alert when RBD shows 0 images but VRs exist (indicates orphaned/stale state)
    local vr_count=0
    vr_count=$(kubectl --context=dr1 get volumereplication -A --no-headers 2>/dev/null | wc -l)
    vr_count=$((vr_count + $(kubectl --context=dr2 get volumereplication -A --no-headers 2>/dev/null | wc -l)))
    if [[ "$vr_count" -gt 0 ]] && echo "$rbd_dr1$rbd_dr2" | grep -q "images: 0 total"; then
        echo -e "${YELLOW}⚠️  RBD has 0 mirrored images but $vr_count VR(s) exist.${NC}"
        echo -e "${YELLOW}   If VR CURRENTSTATE is <none>: CSI-Addons may not be reconciling. Try: make fix-csi-addons-tls && make restart-csi-service${NC}"
        echo -e "${YELLOW}   Otherwise: make reset-csi-replication-state${NC}"
        echo ""
    fi
    echo ""

    # CSI PODS AND DRIVERS
    echo -e "${BLUE}=== CSI PODS & DRIVERS ===${NC}"
    echo "🚗 CSI RBD Pods (DR1):"
    kubectl --context=dr1 -n rook-ceph get pods -l app=csi-rbdplugin 2>/dev/null | head -5 || echo "  No CSI RBD pods found on dr1"
    echo "🚗 CSI RBD Pods (DR2):"
    kubectl --context=dr2 -n rook-ceph get pods -l app=csi-rbdplugin 2>/dev/null | head -5 || echo "  No CSI RBD pods found on dr2"
    echo ""
    
    echo "⚡ External Snapshotter (DR1):"
    kubectl --context=dr1 -n kube-system get pods -l app=snapshot-controller 2>/dev/null || echo "  Snapshot controller not found on dr1"
    echo "⚡ External Snapshotter (DR2):"
    kubectl --context=dr2 -n kube-system get pods -l app=snapshot-controller 2>/dev/null || echo "  Snapshot controller not found on dr2"
    echo ""

    # RESOURCE METRICS
    echo -e "${GREEN}=== RESOURCE METRICS ===${NC}"
    echo "📊 Node Resources (DR1):"
    kubectl --context=dr1 top nodes 2>/dev/null || echo "  Metrics not available on dr1"
    echo "📊 Node Resources (DR2):"
    kubectl --context=dr2 top nodes 2>/dev/null || echo "  Metrics not available on dr2"
    echo ""
    
    echo "🔋 CSI Pod Resources (DR1):"
    kubectl --context=dr1 top pods -n csi-addons-system 2>/dev/null || echo "  Pod metrics not available"
    echo "🔋 Ceph Pod Resources (DR1):"
    kubectl --context=dr1 top pods -n rook-ceph 2>/dev/null | head -5 || echo "  Ceph pod metrics not available"
    echo ""

    # HELPFUL CSI REPLICATION COMMANDS
    echo -e "${CYAN}=== CSI REPLICATION COMMANDS ===${NC}"
    echo "🔍 Test CSI replication: make test-csi-replication"
    echo "🔄 Test failover: make test-csi-failover"
    echo "📦 Test VolumeGroupReplication (VGR): make test-csi-volumegroupreplication"
    echo "📦 Test VolumeGroupEnableReplication (blocked): make test-csi-volumegroup-enablereplication"
    echo "💾 Check Ceph health: kubectl --context=dr1 -n rook-ceph exec deployment/rook-ceph-tools -- ceph status"
    echo "🪞 Check RBD images: kubectl --context=dr1 -n rook-ceph exec deployment/rook-ceph-tools -- rbd ls replicapool"
    echo "🔗 Check CSI Addons logs: kubectl --context=dr1 logs -n csi-addons-system deployment/csi-addons-controller-manager -f"
    echo "⚡ Check snapshot controller: kubectl --context=dr1 logs -n kube-system deployment/snapshot-controller -f"
    echo ""

    # STORAGE USAGE & PVCS (moved to bottom for easy detection)
    echo -e "${PURPLE}=== STORAGE USAGE & PVCS ===${NC}"
    echo "📦 PVCs using Ceph storage (DR1):"
    kubectl --context=dr1 get pvc -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,SIZE:.spec.resources.requests.storage,SC:.spec.storageClassName 2>/dev/null | grep -E "(NAMESPACE|rook-ceph)" | head -8 || echo "  No PVCs using Ceph storage on dr1"
    echo "📦 PVCs using Ceph storage (DR2):"
    kubectl --context=dr2 get pvc -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,SIZE:.spec.resources.requests.storage,SC:.spec.storageClassName 2>/dev/null | grep -E "(NAMESPACE|rook-ceph)" | head -8 || echo "  No PVCs using Ceph storage on dr2"
    echo ""

    # ACTIVE VOLUME REPLICATIONS (moved to bottom for easy detection)
    # SOURCEKIND: PersistentVolumeClaim = single PVC, VolumeGroupReplication = group (VGR)
    echo -e "${CYAN}=== ACTIVE VOLUME REPLICATIONS ===${NC}"
    echo "🔄 Volume Replications (DR1):"
    kubectl --context=dr1 get volumereplication -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,AGE:.metadata.creationTimestamp,VOLUMEREPLICATIONCLASS:.spec.volumeReplicationClass,SOURCEKIND:.spec.dataSource.kind,SOURCENAME:.spec.dataSource.name,DESIREDSTATE:.spec.replicationState,CURRENTSTATE:.status.state 2>/dev/null | head -15 || echo "  No active volume replications on dr1"
    echo "  Detailed Status:"
    kubectl --context=dr1 get volumereplication -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.status.state}{"|"}{range .status.conditions[*]}{.type}={.status}{" "}{end}{"|"}{.status.message}{"\n"}{end}' 2>/dev/null | sed 's/|/  /g' || true
    echo ""
    echo "🔄 Volume Replications (DR2):"
    kubectl --context=dr2 get volumereplication -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,AGE:.metadata.creationTimestamp,VOLUMEREPLICATIONCLASS:.spec.volumeReplicationClass,SOURCEKIND:.spec.dataSource.kind,SOURCENAME:.spec.dataSource.name,DESIREDSTATE:.spec.replicationState,CURRENTSTATE:.status.state 2>/dev/null | head -15 || echo "  No active volume replications on dr2"
    echo "  Detailed Status:"
    kubectl --context=dr2 get volumereplication -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.status.state}{"|"}{range .status.conditions[*]}{.type}={.status}{" "}{end}{"|"}{.status.message}{"\n"}{end}' 2>/dev/null | sed 's/|/  /g' || true
    echo ""

    # VR ISSUES ALERT - highlight when VRs have problems
    local vr_issues=""
    vr_issues=$(kubectl --context=dr1 get volumereplication -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.status.state} {.status.message}{"\n"}{end}' 2>/dev/null)
    vr_issues="$vr_issues$(kubectl --context=dr2 get volumereplication -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.status.state} {.status.message}{"\n"}{end}' 2>/dev/null)"
    # Detect: (1) explicit errors, (2) empty state (CURRENTSTATE <none> = controller not reconciling)
    local vr_has_issues=false
    if echo "$vr_issues" | grep -qE "(Unknown|Degraded|not found|error|Error|failed|Failed)"; then
        vr_has_issues=true
    fi
    # VRs with desired state but empty status.state (controller not updating)
    local vr_empty_state=""
    vr_empty_state=$(kubectl --context=dr1 get volumereplication -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.status.state}{"\n"}{end}' 2>/dev/null | awk '$2=="" || $2=="<none>" {print $1 " (state empty)"}')
    vr_empty_state="$vr_empty_state$(kubectl --context=dr2 get volumereplication -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name} {.status.state}{"\n"}{end}' 2>/dev/null | awk '$2=="" || $2=="<none>" {print $1 " (state empty)"}')"
    if [[ -n "$vr_empty_state" ]]; then
        vr_has_issues=true
    fi
    if $vr_has_issues; then
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${RED}⚠️  VR ISSUES DETECTED - VolumeReplications have problems${NC}"
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        if [[ -n "$vr_empty_state" ]]; then
            echo -e "${YELLOW}VRs with empty state (CURRENTSTATE <none> - controller not reconciling):${NC}"
            echo "$vr_empty_state" | sed 's/^/  • /'
            echo -e "${YELLOW}  → CSI-Addons may not be processing VRs. Try: make fix-csi-addons-tls && make restart-csi-service${NC}"
            echo ""
        fi
        if echo "$vr_issues" | grep -qE "(Unknown|Degraded|not found|error|Error|failed|Failed)"; then
            echo -e "${YELLOW}Problematic VRs:${NC}"
            echo "$vr_issues" | grep -E "(Unknown|Degraded|not found|error|Error|failed|Failed)" | sed 's/^/  • /'
            echo ""
        fi
        echo -e "${YELLOW}Common causes & fixes:${NC}"
        echo "  • Empty state: make fix-csi-addons-tls && make restart-csi-service"
        echo "  • Orphaned VRs from failed tests: make reset-csi-replication-state"
        echo "  • VRC not found: ensure rbd-volumereplicationclass exists (make start-csi-replication)"
        echo "  • Image not found: RBD images may have been cleaned; run make reset-csi-replication-state"
        echo ""
    fi

    # VOLUME GROUP REPLICATIONS (VGR) - one VGR CR creates VGRC and per-volume VRs via controller
    echo -e "${CYAN}=== VOLUME GROUP REPLICATIONS (VGR) ===${NC}"
    echo -e "${YELLOW}Note: VGR uses VolumeGroupReplication CR with source.selector. Controller creates VolumeGroupReplicationContent + per-volume VolumeReplication.${NC}"
    echo ""
    echo "📦 VolumeGroupReplications (DR1):"
    kubectl --context=dr1 get volumegroupreplication -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,VGRCLASS:.spec.volumeGroupReplicationClassName,VRC:.spec.volumeReplicationClassName,STATE:.status.state 2>/dev/null | head -15 || echo "  No VolumeGroupReplications found on dr1"
    echo "📦 VolumeGroupReplications (DR2):"
    kubectl --context=dr2 get volumegroupreplication -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,VGRCLASS:.spec.volumeGroupReplicationClassName,VRC:.spec.volumeReplicationClassName,STATE:.status.state 2>/dev/null | head -15 || echo "  No VolumeGroupReplications found on dr2"
    echo ""
    echo "📋 VolumeGroupReplicationContents (cluster-scoped):"
    kubectl --context=dr1 get volumegroupreplicationcontent -o custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp,VGRCLASS:.spec.volumeGroupReplicationClassName 2>/dev/null | head -10 || echo "  No VGRCs found"
    echo ""
    # VGR empty-state detection: state <none> = controller not reconciling or no leader
    local vgr_empty=""
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        state=$(echo "$line" | awk '{print $NF}')
        if [[ -z "$state" ]] || [[ "$state" == "<none>" ]]; then
            ns_name=$(echo "$line" | awk '{$NF=""; print $0}' | xargs | tr ' ' '/')
            [[ -n "$ns_name" ]] && vgr_empty="${vgr_empty}${ns_name}"$'\n'
        fi
    done < <(kubectl --context=dr1 get volumegroupreplication -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATE:.status.state --no-headers 2>/dev/null || true)
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        state=$(echo "$line" | awk '{print $NF}')
        if [[ -z "$state" ]] || [[ "$state" == "<none>" ]]; then
            ns_name=$(echo "$line" | awk '{$NF=""; print $0}' | xargs | tr ' ' '/')
            [[ -n "$ns_name" ]] && vgr_empty="${vgr_empty}${ns_name}"$'\n'
        fi
    done < <(kubectl --context=dr2 get volumegroupreplication -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATE:.status.state --no-headers 2>/dev/null || true)
    if [[ -n "$vgr_empty" ]]; then
        vgr_empty=$(echo "$vgr_empty" | sort -u | grep -v '^$')
        if [[ -n "$vgr_empty" ]]; then
            echo -e "${YELLOW}⚠️  VGR with empty state (STATE <none>):${NC}"
            echo "$vgr_empty" | sed 's/^/  • /'
            local vgrc_count
            vgrc_count=$(kubectl --context=dr1 get volumegroupreplicationcontent -o name 2>/dev/null | wc -l)
            vgrc_count=$((vgrc_count + $(kubectl --context=dr2 get volumegroupreplicationcontent -o name 2>/dev/null | wc -l)))
            if [[ "${vgrc_count:-0}" -gt 0 ]]; then
                echo -e "  ${YELLOW}VGRC exists but VGR state empty → controller may lack leader. Run: make restart-csi-service${NC}"
            else
                echo -e "  ${YELLOW}No VGRC yet → controller may not be reconciling. Check CSI Addons logs for 'no leader'.${NC}"
            fi
            echo ""
        fi
    fi
    echo ""
    echo -e "${CYAN}=== VOLUME GROUPS (VolumeGroupEnableReplication - blocked) ===${NC}"
    echo -e "${YELLOW}Note: test-csi-volumegroup-enablereplication uses VolumeGroup + VolumeReplication (blocked, no controller).${NC}"
    echo ""
    echo "📦 VolumeGroups (DR1):"
    kubectl --context=dr1 get volumegroup -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.ready,VGCLASS:.spec.volumeGroupClassName,VGCONTENT:.status.boundVolumeGroupContentName,AGE:.metadata.creationTimestamp 2>/dev/null | head -15 || echo "  No VolumeGroups found on dr1"
    echo ""
    echo "📦 VolumeGroups (DR2):"
    kubectl --context=dr2 get volumegroup -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,READY:.status.ready,VGCLASS:.spec.volumeGroupClassName,VGCONTENT:.status.boundVolumeGroupContentName,AGE:.metadata.creationTimestamp 2>/dev/null | head -15 || echo "  No VolumeGroups found on dr2"
    echo ""

    # NETWORK FENCE RESOURCES (moved to bottom for easy detection)
    echo -e "${PURPLE}=== NETWORK FENCE RESOURCES ===${NC}"
    echo "🔐 Network Fence Classes (DR1):"
    kubectl --context=dr1 get networkfenceclass -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PROVISIONER:.spec.provisioner,PARAMETERS:.spec.parameters 2>/dev/null || echo "  No NetworkFenceClass resources found on dr1"
    echo "🔐 Network Fence Classes (DR2):"
    kubectl --context=dr2 get networkfenceclass -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PROVISIONER:.spec.provisioner,PARAMETERS:.spec.parameters 2>/dev/null || echo "  No NetworkFenceClass resources found on dr2"
    echo ""
    echo "🚫 Network Fences (DR1):"
    kubectl --context=dr1 get networkfence -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.networkFenceClassName,FENCESTATE:.spec.fenceState,CIDRS:.spec.cidrs 2>/dev/null || echo "  No NetworkFence resources found on dr1"
    echo "🚫 Network Fences (DR2):"
    kubectl --context=dr2 get networkfence -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.networkFenceClassName,FENCESTATE:.spec.fenceState,CIDRS:.spec.cidrs 2>/dev/null || echo "  No NetworkFence resources found on dr2"
    echo ""
    
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Wait for refresh interval or key press (space/enter) to refresh immediately
# Usage: wait_for_refresh [interval_seconds]
wait_for_refresh() {
    local interval="${1:-20}"
    echo -e "\n${YELLOW}Press Space or Enter to refresh now, or wait ${interval}s...${NC}"
    read -t "$interval" -n 1 -s key || true
}

# Storage Classes monitoring
storageclass_monitoring() {
    echo -e "${GREEN}💾 Starting Storage Classes & VRCs Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • Storage Classes (Ceph RBD)"
    echo "  • Volume Replication Classes"
    echo "  • Volume Snapshot Classes"
    echo "  • CSI driver status"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop. Space or Enter = refresh now.${NC}"
    echo ""
    sleep 2
    
    while true; do
        clear
        echo "=== STORAGE CLASSES ==="
        kubectl --context=dr1 get storageclass -o wide 2>/dev/null | grep -E "(NAME|rook-ceph)"
        kubectl --context=dr2 get storageclass -o wide 2>/dev/null | grep -v NAME | grep rook-ceph
        echo ""
        echo "=== VOLUME REPLICATION CLASSES ==="
        kubectl --context=dr1 get volumereplicationclass 2>/dev/null
        echo ""
        echo "=== VOLUME SNAPSHOT CLASSES ==="
        kubectl --context=dr1 get volumesnapshotclass 2>/dev/null
        echo ""
        echo "=== ACTIVE VOLUME REPLICATIONS (SOURCEKIND: PersistentVolumeClaim=single, VolumeGroupReplication=group) ==="
        kubectl --context=dr1 get volumereplication -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,SOURCEKIND:.spec.dataSource.kind,SOURCENAME:.spec.dataSource.name,STATE:.status.state 2>/dev/null | head -8
        echo "  Detailed Status:"
        kubectl --context=dr1 get volumereplication -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.status.state}{"|"}{range .status.conditions[*]}{.type}={.status}{" "}{end}{"|"}{.status.message}{"\n"}{end}' 2>/dev/null | sed 's/|/  /g' || echo "  No active replications"
        wait_for_refresh 3
    done
}

# CSI Addons monitoring
csi_addons_monitoring() {
    echo -e "${GREEN}🎛️ Starting CSI Addons Controllers Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • CSI Addons controller pods"
    echo "  • CSI Addons Node resources"
    echo "  • CSI driver sidecar containers"
    echo "  • Controller connectivity status"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop. Space or Enter = refresh now.${NC}"
    echo ""
    sleep 2
    
    while true; do
        clear
        echo "=== CSI ADDONS CONTROLLERS ==="
        kubectl --context=dr1 get pods -n csi-addons-system -o wide 2>/dev/null
        kubectl --context=dr2 get pods -n csi-addons-system -o wide 2>/dev/null
        echo ""
        echo "=== CSI ADDONS NODES ==="
        kubectl --context=dr1 get csiaddonsnode -A 2>/dev/null || echo "No CSIAddonsNode resources"
        echo ""
        echo "=== CSI RBD PLUGIN PODS ==="
        kubectl --context=dr1 -n rook-ceph get pods -l app=csi-rbdplugin 2>/dev/null | head -5
        wait_for_refresh 3
    done
}

# RBD Mirroring monitoring
rbd_mirroring_monitoring() {
    echo -e "${GREEN}🪞 Starting RBD Mirroring Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • RBD mirror daemon pods"
    echo "  • RBD pool mirroring status"
    echo "  • Cross-cluster replication health"
    echo "  • Image sync status"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop. Space or Enter = refresh now.${NC}"
    echo ""
    sleep 2
    
    while true; do
        clear
        echo "=== RBD MIRROR DAEMONS ==="
        kubectl --context=dr1 -n rook-ceph get pods -l app=rook-ceph-rbd-mirror 2>/dev/null
        kubectl --context=dr2 -n rook-ceph get pods -l app=rook-ceph-rbd-mirror 2>/dev/null
        echo ""
        echo "=== RBD POOL STATUS (DR1) ==="
        kubectl --context=dr1 -n rook-ceph exec deploy/rook-ceph-tools -- rbd mirror pool status replicapool 2>/dev/null | head -10 || echo "RBD status unavailable"
        echo ""
        echo "=== RBD IMAGES ==="
        kubectl --context=dr1 -n rook-ceph exec deploy/rook-ceph-tools -- rbd ls replicapool 2>/dev/null | head -5 || echo "No RBD images"
        wait_for_refresh 5
    done
}

# Ceph cluster monitoring
ceph_cluster_monitoring() {
    echo -e "${GREEN}🏗️ Starting Ceph Clusters Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • Ceph cluster health"
    echo "  • Ceph block pools"
    echo "  • OSD status"
    echo "  • Ceph operator pods"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop. Space or Enter = refresh now.${NC}"
    echo ""
    sleep 2
    
    while true; do
        clear
        echo "=== CEPH CLUSTERS ==="
        kubectl --context=dr1 -n rook-ceph get cephcluster,cephblockpool 2>/dev/null
        kubectl --context=dr2 -n rook-ceph get cephcluster,cephblockpool 2>/dev/null
        echo ""
        echo "=== CEPH OPERATORS ==="
        kubectl --context=dr1 -n rook-ceph get pods -l app=rook-ceph-operator 2>/dev/null
        kubectl --context=dr2 -n rook-ceph get pods -l app=rook-ceph-operator 2>/dev/null
        echo ""
        echo "=== CEPH HEALTH (DR1) ==="
        kubectl --context=dr1 -n rook-ceph exec deploy/rook-ceph-tools -- ceph status 2>/dev/null | head -8 || echo "Ceph status unavailable"
        wait_for_refresh 5
    done
}

# PVC and storage usage monitoring
storage_usage_monitoring() {
    echo -e "${GREEN}📦 Starting Storage Usage Monitoring...${NC}"
    echo ""
    echo "This will monitor:"
    echo "  • PVCs using Ceph storage"
    echo "  • Volume usage and capacity"
    echo "  • Storage resource consumption"
    echo "  • Active applications with storage"
    echo ""
    echo -e "${YELLOW}⚠️  Press Ctrl+C to stop. Space or Enter = refresh now.${NC}"
    echo ""
    sleep 2
    
    while true; do
        clear
        echo "=== PVCS WITH CEPH STORAGE ==="
        kubectl --context=dr1 get pvc -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,SIZE:.spec.resources.requests.storage,SC:.spec.storageClassName 2>/dev/null | grep -E "(NAMESPACE|rook-ceph)" | head -8
        kubectl --context=dr2 get pvc -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,STATUS:.status.phase,SIZE:.spec.resources.requests.storage,SC:.spec.storageClassName 2>/dev/null | grep -v NAME | grep rook-ceph | head -5
        echo ""
        echo "=== PODS USING CEPH VOLUMES ==="
        kubectl --context=dr1 get pods -A --field-selector=status.phase=Running 2>/dev/null | head -8
        echo ""
        echo "=== VOLUME SNAPSHOTS ==="
        kubectl --context=dr1 get volumesnapshot -A 2>/dev/null | head -5 || echo "No volume snapshots found"
        echo ""
        echo "=== ACTIVE VOLUME REPLICATIONS (SOURCEKIND: PersistentVolumeClaim=single, VolumeGroupReplication=group) ==="
        kubectl --context=dr1 get volumereplication -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,SOURCEKIND:.spec.dataSource.kind,SOURCENAME:.spec.dataSource.name,STATE:.status.state 2>/dev/null | head -8
        echo "  Detailed Status:"
        kubectl --context=dr1 get volumereplication -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"|"}{.metadata.name}{"|"}{.status.state}{"|"}{range .status.conditions[*]}{.type}={.status}{" "}{end}{"|"}{.status.message}{"\n"}{end}' 2>/dev/null | sed 's/|/  /g' || echo "  No active replications"
        echo ""
        echo "=== VOLUME GROUP REPLICATIONS ==="
        kubectl --context=dr1 get volumegroupreplication -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,VGRCLASS:.spec.volumeGroupReplicationClassName,STATE:.status.state 2>/dev/null | head -15 || echo "  No VolumeGroupReplications found"
        kubectl --context=dr2 get volumegroupreplication -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,VGRCLASS:.spec.volumeGroupReplicationClassName,STATE:.status.state 2>/dev/null | head -15 || echo "  No VolumeGroupReplications found on dr2"
        echo ""
        echo "=== NETWORK FENCE CLASSES ==="
        kubectl --context=dr1 get networkfenceclass -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PROVISIONER:.spec.provisioner 2>/dev/null | head -5 || echo "No NetworkFenceClass resources found on dr1"
        kubectl --context=dr2 get networkfenceclass -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,PROVISIONER:.spec.provisioner 2>/dev/null | head -5 || echo "No NetworkFenceClass resources found on dr2"
        echo ""
        echo "=== NETWORK FENCES ==="
        kubectl --context=dr1 get networkfence -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.networkFenceClassName,FENCESTATE:.spec.fenceState,CIDRS:.spec.cidrs 2>/dev/null | head -5 || echo "No NetworkFence resources found on dr1"
        kubectl --context=dr2 get networkfence -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.networkFenceClassName,FENCESTATE:.spec.fenceState,CIDRS:.spec.cidrs 2>/dev/null | head -5 || echo "No NetworkFence resources found on dr2"
        wait_for_refresh 3
    done
}

# Show monitoring options
show_monitoring_options() {
    echo -e "${BLUE}🔍 CSI Replication Infrastructure Monitoring Options:${NC}"
    echo ""
    echo "1. 💾 Storage Classes & Volume Replication Classes Monitoring"
    echo "2. 🎛️  CSI Addons Controllers & Nodes Monitoring"  
    echo "3. 🪞 RBD Mirroring & Cross-Cluster Replication Monitoring"
    echo "4. 🏗️  Ceph Clusters & Storage Infrastructure Monitoring"
    echo "5. 📦 PVCs & Storage Usage Monitoring"
    echo "6. 🔄 Comprehensive CSI Replication Monitoring (All-in-One)"
    echo "7. 📋 Show All Commands (for copy-paste)"
    echo "8. ❓ Help & Examples"
    echo ""
}

# Show all commands for copy-paste
show_commands() {
    echo -e "${BLUE}📋 CSI Replication Monitoring Commands (Copy-Paste Ready):${NC}"
    echo ""
    
    echo -e "${PURPLE}# Terminal 1: Storage Classes & VRCs${NC}"
    echo 'watch -n 3 "
        kubectl --context=dr1 get storageclass,volumereplicationclass 2>/dev/null && 
        kubectl --context=dr1 get volumereplication -A 2>/dev/null | head -5
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 2: CSI Addons Controllers${NC}"
    echo 'watch -n 3 "
        kubectl --context=dr1 get pods -n csi-addons-system -o wide 2>/dev/null && 
        kubectl --context=dr2 get pods -n csi-addons-system -o wide 2>/dev/null && 
        kubectl --context=dr1 get csiaddonsnode -A 2>/dev/null
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 3: RBD Mirroring${NC}"
    echo 'watch -n 5 "
        kubectl --context=dr1 -n rook-ceph get pods -l app=rook-ceph-rbd-mirror && 
        kubectl --context=dr1 -n rook-ceph exec deployment/rook-ceph-tools -- rbd mirror pool status replicapool 2>/dev/null | head -8
    "'
    echo ""
    
    echo -e "${PURPLE}# Terminal 4: Ceph Clusters${NC}"
    echo 'watch -n 5 "
        kubectl --context=dr1 -n rook-ceph get cephcluster,cephblockpool && 
        kubectl --context=dr2 -n rook-ceph get cephcluster,cephblockpool
    "'
    echo ""
    
    echo -e "${PURPLE}# Manual Commands${NC}"
    echo "# Test CSI replication:"
    echo "make test-csi-replication"
    echo ""
    echo "# Check RBD images:"
    echo "kubectl --context=dr1 -n rook-ceph exec deployment/rook-ceph-tools -- rbd ls replicapool"
    echo ""
    echo "# Check CSI Addons logs:"
    echo "kubectl --context=dr1 logs -n csi-addons-system deployment/csi-addons-controller-manager -f"
}

# Help and examples
show_help() {
    echo -e "${BLUE}❓ CSI Replication Infrastructure Monitoring Help${NC}"
    echo ""
    echo -e "${PURPLE}🎯 Environment Setup:${NC}"
    echo "  1. Create CSI replication environment: make setup-csi-replication"
    echo "  2. Test the setup: make test-csi-replication"
    echo "  3. Run this monitoring script: ./csi-replication-monitoring.sh"
    echo ""
    echo -e "${PURPLE}📊 Resource Explanations:${NC}"
    echo "  • storageclass: Kubernetes storage provisioning (rook-ceph-block)"
    echo "  • volumereplicationclass: CSI volume replication configuration"
    echo "  • volumereplication: Active CSI volume replication instances"
    echo "  • csiaddonsnode: CSI addons service discovery"
    echo "  • cephcluster/cephblockpool: Ceph storage backend"
    echo "  • rbd-mirror: Cross-cluster RBD image replication"
    echo ""
    echo -e "${PURPLE}⚡ CSI Replication Environment:${NC}"
    echo "  • Focus: Pure CSI replication without RamenDR orchestration"
    echo "  • Clusters: dr1 (primary) and dr2 (secondary)"
    echo "  • Storage: Ceph RBD with cross-cluster mirroring"
    echo "  • Replication: CSI VolumeReplication API"
    echo "  • No hub cluster or RamenDR operators needed"
    echo ""
    echo -e "${PURPLE}🔧 Troubleshooting:${NC}"
    echo "  • If contexts not found: run 'make setup-csi-replication'"
    echo "  • If CSI Addons errors: run 'make fix-csi-addons-tls'"  
    echo "  • If storage issues: check ceph status in rook-ceph-tools pod"
    echo "  • If mirroring issues: check rook-ceph-rbd-mirror pods"
    echo ""
    echo -e "${PURPLE}🧪 Testing Commands:${NC}"
    echo "  • make test-csi-replication           # Test single-volume replication"
    echo "  • make test-csi-failover             # Test demote/promote flow"
    echo "  • make test-csi-volumegroupreplication # Test VGR (VolumeGroupReplication)"
    echo "  • make status-csi-replication        # Check environment status"
}

# Main menu
main() {
    # Check contexts first
    check_contexts
    
    if [ $# -eq 1 ] && [ "$1" == "comprehensive" ]; then
        # Direct comprehensive monitoring without menu
        while true; do
            comprehensive_csi_monitoring
            wait_for_refresh 20
        done
    fi
    
    while true; do
        show_monitoring_options
        read -p "Choose an option (1-8) or 'q' to quit: " choice
        echo ""
        
        case $choice in
            1) storageclass_monitoring ;;
            2) csi_addons_monitoring ;;
            3) rbd_mirroring_monitoring ;;
            4) ceph_cluster_monitoring ;;
            5) storage_usage_monitoring ;;
            6) 
                echo -e "${GREEN}🔄 Starting Comprehensive CSI Replication Monitoring...${NC}"
                echo -e "${YELLOW}⚠️  Press Ctrl+C to stop. Space or Enter = refresh now.${NC}"
                sleep 2
                while true; do
                    comprehensive_csi_monitoring
                    wait_for_refresh 20
                done
                ;;
            7) show_commands ;;
            8) show_help ;;
            q|Q) echo "Exiting..."; exit 0 ;;
            *) echo -e "${RED}❌ Invalid option. Please choose 1-8 or 'q'${NC}"; echo ;;
        esac
        
        if [ "$choice" != "7" ] && [ "$choice" != "8" ]; then
            echo ""
            echo -e "${YELLOW}Press any key to return to menu...${NC}"
            read -n 1 -s
            echo ""
        fi
    done
}

# Run main function
main "$@"