#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Script to specifically verify and fix snapshot-controller image issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/utils.sh
source "$SCRIPT_DIR/utils.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

detect_container_runtime

SNAPSHOT_IMAGE="registry.k8s.io/sig-storage/snapshot-controller:v7.0.1"

verify_and_fix_snapshot_controller() {
    local cluster=$1
    
    log_info "Verifying snapshot-controller image for cluster: $cluster"
    
    # Check if cluster exists
    if ! minikube profile list --output=json 2>/dev/null | grep -q "\"Name\":\"$cluster\""; then
        log_error "Cluster $cluster does not exist"
        return 1
    fi
    
    # Check if image exists locally
    if ! $CONTAINER_RUNTIME image inspect "$SNAPSHOT_IMAGE" >/dev/null 2>&1; then
        log_warning "Snapshot controller image not available locally, pulling..."
        
        # Try pulling with different methods
        log_info "Attempting to pull $SNAPSHOT_IMAGE..."
        if [[ "$CONTAINER_RUNTIME" == "podman" ]]; then
            # Try with podman-specific options
            if ! $CONTAINER_RUNTIME pull --tls-verify=false "$SNAPSHOT_IMAGE"; then
                log_error "Failed to pull snapshot controller image with podman"
                return 1
            fi
        else
            # Try with docker
            if ! $CONTAINER_RUNTIME pull "$SNAPSHOT_IMAGE"; then
                log_error "Failed to pull snapshot controller image with docker"  
                return 1
            fi
        fi
        log_success "Successfully pulled snapshot controller image"
    else
        log_success "Snapshot controller image available locally"
    fi
    
    # Check if image exists in minikube cluster
    if minikube image ls --profile="$cluster" 2>/dev/null | grep -q "$SNAPSHOT_IMAGE"; then
        log_success "Snapshot controller image already in $cluster cluster"
    else
        log_warning "Loading snapshot controller image into $cluster cluster..."
        
        # Try direct load
        if minikube image load "$SNAPSHOT_IMAGE" --profile="$cluster"; then
            log_success "Successfully loaded snapshot controller image into $cluster"
        else
            log_warning "Direct load failed, trying tar method..."
            
            # Try tar save/load method
            local tar_file="/tmp/snapshot-controller-$cluster.tar"
            if $CONTAINER_RUNTIME save "$SNAPSHOT_IMAGE" -o "$tar_file" && \
               minikube image load "$tar_file" --profile="$cluster"; then
                rm -f "$tar_file"
                log_success "Successfully loaded snapshot controller image via tar method"
            else
                log_error "All methods failed to load snapshot controller image"
                rm -f "$tar_file"
                return 1
            fi
        fi
    fi
    
    # Verify the image is now available in cluster
    if minikube image ls --profile="$cluster" 2>/dev/null | grep -q "$SNAPSHOT_IMAGE"; then
        log_success "✅ Snapshot controller image verified in $cluster cluster"
        
        # Try to restart any failing pods
        log_info "Checking for failing snapshot-controller pods..."
        if kubectl --context="$cluster" get pods -n kube-system -l app.kubernetes.io/name=snapshot-controller --field-selector=status.phase!=Running 2>/dev/null | grep -q snapshot-controller; then
            log_info "Restarting failing snapshot-controller pods..."
            kubectl --context="$cluster" delete pods -n kube-system -l app.kubernetes.io/name=snapshot-controller --ignore-not-found=true
            log_success "Snapshot-controller pods restarted"
        fi
        
        return 0
    else
        log_error "❌ Failed to verify snapshot controller image in $cluster cluster"
        return 1
    fi
}

main() {
    local clusters=("$@")
    
    if [ ${#clusters[@]} -eq 0 ]; then
        clusters=("dr1" "dr2")
        log_info "No clusters specified, using default: ${clusters[*]}"
    fi
    
    echo -e "${BLUE}🔍 Snapshot Controller Image Verification${NC}"
    echo "==========================================="
    echo ""
    
    log_info "Using container runtime: $CONTAINER_RUNTIME"
    log_info "Target image: $SNAPSHOT_IMAGE"
    echo ""
    
    local success_count=0
    local total_count=${#clusters[@]}
    
    for cluster in "${clusters[@]}"; do
        if verify_and_fix_snapshot_controller "$cluster"; then
            ((success_count++))
        fi
        echo ""
    done
    
    if [ $success_count -eq $total_count ]; then
        log_success "🎉 All $total_count clusters have working snapshot-controller images!"
    else
        log_warning "⚠️  Only $success_count/$total_count clusters have working snapshot-controller images"
        exit 1
    fi
}

main "$@"