#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Script to clean up local registry used for CSI replication

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

log_info "🧹 Cleaning up local registry (using $CONTAINER_RUNTIME)..."

# Stop and remove local-registry from BOTH podman and docker
# (registry may have been started with a different runtime than current)
for runtime in podman docker; do
    if command -v "$runtime" >/dev/null 2>&1; then
        if $runtime ps -a 2>/dev/null | grep -q "local-registry"; then
            log_info "Stopping/removing local-registry from $runtime..."
            $runtime stop local-registry 2>/dev/null || true
            $runtime rm local-registry 2>/dev/null || true
            log_success "Removed local-registry from $runtime"
        fi
    fi
done

# If port 5000 is still in use, try to free it (e.g. leftover process)
if command -v ss >/dev/null 2>&1 && ss -tlnp 2>/dev/null | grep -q ":5000 "; then
    log_warning "Port 5000 still in use, attempting to identify process..."
    PID=$(ss -tlnp 2>/dev/null | awk '/:5000 / {gsub(/.*pid=/, ""); gsub(/,.*/, ""); print; exit}')
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        log_info "Stopping process $PID using port 5000..."
        kill "$PID" 2>/dev/null || true
        sleep 2
        kill -9 "$PID" 2>/dev/null || true
        log_success "Freed port 5000"
    fi
elif command -v lsof >/dev/null 2>&1; then
    PID=$(lsof -ti :5000 2>/dev/null | head -1)
    if [ -n "$PID" ]; then
        log_info "Stopping process $PID using port 5000..."
        kill "$PID" 2>/dev/null || true
        sleep 2
        kill -9 "$PID" 2>/dev/null || true
        log_success "Freed port 5000"
    fi
fi

# Clean up registry images (optional - saves disk space)
log_info "Cleaning up registry-related images..."
$CONTAINER_RUNTIME image prune -f --filter "label=org.opencontainers.image.title=registry" 2>/dev/null || log_warning "Failed to prune registry images"

# Clean up localhost:5000 tagged images
log_info "Cleaning up localhost:5000 tagged images..."
LOCALHOST_IMAGES=$($CONTAINER_RUNTIME images --format "table {{.Repository}}:{{.Tag}}" 2>/dev/null | grep "localhost:5000" | awk '{print $1}' || true)
if [ -n "$LOCALHOST_IMAGES" ]; then
    echo "$LOCALHOST_IMAGES" | xargs $CONTAINER_RUNTIME rmi -f 2>/dev/null || log_warning "Some localhost:5000 images could not be removed"
    log_success "Cleaned up localhost:5000 tagged images"
else
    log_info "No localhost:5000 tagged images found"
fi

log_success "🎉 Local registry cleanup complete!"