#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Fix RBD mirror daemon health WARNING (e.g. after failed NetworkFence tests).
# Re-applies peer config when possible; falls back to daemon restart if setup would hang.

set -e

CONTEXTS="dr1 dr2"
SETUP_TIMEOUT=240

log_info() { echo "$*"; }
log_warn() { echo "⚠ $*" >&2; }

# Check if CephBlockPool has mirroringInfo and peer secret (required for setup-rbd-mirroring)
check_pool_ready() {
    local context=$1
    local site_name peer_secret
    site_name=$(kubectl --context="$context" -n rook-ceph get cephblockpool replicapool \
        -o jsonpath='{.status.mirroringInfo.site_name}' 2>/dev/null || true)
    peer_secret=$(kubectl --context="$context" -n rook-ceph get cephblockpool replicapool \
        -o jsonpath='{.status.info.rbdMirrorBootstrapPeerSecretName}' 2>/dev/null || true)
    [[ -n "$site_name" && -n "$peer_secret" ]]
}

clear_blocklist() {
    for ctx in $CONTEXTS; do
        if kubectl --context="$ctx" -n rook-ceph get deploy/rook-ceph-tools &>/dev/null; then
            kubectl --context="$ctx" -n rook-ceph exec deploy/rook-ceph-tools -- \
                ceph osd blocklist clear 2>/dev/null || true
            log_info "Cleared OSD blocklist in $ctx"
        fi
    done
}

log_info "Fixing RBD mirror daemon health..."
log_info "Step 1: Clearing OSD blocklist (stale NetworkFence entries - do this first to restore connectivity)..."
clear_blocklist

log_info "Step 2: Removing rbd-mirror daemon temporarily (releases watchers on error-state images so they can be deleted)..."
log_info "  CephRBDMirror count must be >=1, so we delete the CR; setup-rbd-mirroring will recreate it."
for ctx in $CONTEXTS; do
    if kubectl --context="$ctx" -n rook-ceph get cephrbdmirror my-rbd-mirror &>/dev/null; then
        kubectl --context="$ctx" -n rook-ceph delete cephrbdmirror my-rbd-mirror --wait=false 2>/dev/null || \
            log_warn "Could not delete CephRBDMirror on $ctx"
    fi
done
log_info "Waiting for rbd-mirror pods to terminate (45s)..."
sleep 45

log_info "Step 3: Cleaning up error-state replicated images..."
./scripts/cleanup-replicated-images.sh
log_info "Step 3b: Second cleanup pass (catches any remaining error images)..."
./scripts/cleanup-replicated-images.sh

log_info "Step 4: Checking if CephBlockPool has mirroring info and peer secret (required for full setup)..."
DR1_READY=$(check_pool_ready dr1 && echo yes || echo no)
DR2_READY=$(check_pool_ready dr2 && echo yes || echo no)

if [[ "$DR1_READY" == "yes" && "$DR2_READY" == "yes" ]]; then
    log_info "CephBlockPool ready on both clusters. Re-applying RBD mirror peer configuration (scales rbd-mirror back up)..."
    if timeout "$SETUP_TIMEOUT" ./scripts/setup-rbd-mirroring.sh; then
        log_info "✓ RBD mirror health fix complete."
    else
        exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_warn "Setup timed out after ${SETUP_TIMEOUT}s. Restarting rbd-mirror daemon as fallback..."
        else
            log_warn "Setup failed (exit $exit_code). Restarting rbd-mirror daemon as fallback..."
        fi
        for ctx in $CONTEXTS; do
            kubectl --context="$ctx" -n rook-ceph delete pod -l app=rook-ceph-rbd-mirror \
                --ignore-not-found=true --wait=false 2>/dev/null || true
        done
        log_info "Daemon restarted. Verify: kubectl -n rook-ceph exec deploy/rook-ceph-tools -- rbd mirror pool status replicapool"
        exit 0
    fi
else
    log_warn "CephBlockPool not ready for full setup (dr1=$DR1_READY, dr2=$DR2_READY)."
    log_warn "Recreating rbd-mirror daemon (was removed for cleanup)..."
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
    for ctx in $CONTEXTS; do
        kubectl --context="$ctx" apply -f "${REPO_ROOT}/test/addons/rbd-mirror/start-data/rbd-mirror.yaml" 2>/dev/null || true
    done
    log_info "Waiting for pods to become Ready (60s)..."
    sleep 5
    for ctx in $CONTEXTS; do
        kubectl --context="$ctx" -n rook-ceph wait --for=condition=Ready pod -l app=rook-ceph-rbd-mirror \
            --timeout=60s 2>/dev/null || log_warn "$ctx rbd-mirror may still be starting"
    done
    log_info "✓ Daemon restored. If WARNING persists, check:"
    log_info "  kubectl --context=dr1 -n rook-ceph get cephblockpool replicapool -o yaml"
    log_info "  kubectl --context=dr1 -n rook-ceph logs deploy/rook-ceph-rbd-mirror-a"
fi
