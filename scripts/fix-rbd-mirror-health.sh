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

# Check if CephBlockPool has mirroringInfo populated (required for setup-rbd-mirroring)
check_pool_ready() {
    local context=$1
    local site_name
    site_name=$(kubectl --context="$context" -n rook-ceph get cephblockpool replicapool \
        -o jsonpath='{.status.mirroringInfo.site_name}' 2>/dev/null || true)
    [[ -n "$site_name" ]]
}

log_info "Fixing RBD mirror daemon health..."
log_info "Step 1: Cleaning up error-state replicated images..."
./scripts/cleanup-replicated-images.sh

log_info "Step 2: Checking if CephBlockPool has mirroring info (required for full setup)..."
DR1_READY=$(check_pool_ready dr1 && echo yes || echo no)
DR2_READY=$(check_pool_ready dr2 && echo yes || echo no)

if [[ "$DR1_READY" == "yes" && "$DR2_READY" == "yes" ]]; then
    log_info "CephBlockPool ready on both clusters. Re-applying RBD mirror peer configuration..."
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
    log_warn "CephBlockPool mirroringInfo not ready (dr1=$DR1_READY, dr2=$DR2_READY)."
    log_warn "Full setup would hang. Restarting rbd-mirror daemon instead."
    for ctx in $CONTEXTS; do
        log_info "  Restarting rbd-mirror on $ctx..."
        kubectl --context="$ctx" -n rook-ceph delete pod -l app=rook-ceph-rbd-mirror \
            --ignore-not-found=true --wait=false 2>/dev/null || true
    done
    log_info "Waiting for pods to become Ready (60s)..."
    sleep 5
    for ctx in $CONTEXTS; do
        kubectl --context="$ctx" -n rook-ceph wait --for=condition=Ready pod -l app=rook-ceph-rbd-mirror \
            --timeout=60s 2>/dev/null || log_warn "$ctx rbd-mirror may still be starting"
    done
    log_info "✓ Daemon restarted. If WARNING persists, check:"
    log_info "  kubectl --context=dr1 -n rook-ceph get cephblockpool replicapool -o yaml"
    log_info "  kubectl --context=dr1 -n rook-ceph logs deploy/rook-ceph-rbd-mirror-a"
fi
