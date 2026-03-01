#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Script to clean up local Docker registry used for CSI replication

set -e

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

log_info "🧹 Cleaning up local Docker registry..."

# Check if registry is running
if docker ps | grep -q "local-registry"; then
    log_info "Stopping local registry container..."
    docker stop local-registry
    log_success "Local registry stopped"
else
    log_info "Local registry is not running"
fi

# Remove registry container
if docker ps -a | grep -q "local-registry"; then
    log_info "Removing local registry container..."
    docker rm local-registry
    log_success "Local registry container removed"
else
    log_info "Local registry container does not exist"
fi

# Clean up registry images (optional - saves disk space)
log_info "Cleaning up registry-related images..."
docker image prune -f --filter "label=org.opencontainers.image.title=registry" || log_warning "Failed to prune registry images"

# Clean up localhost:5000 tagged images
log_info "Cleaning up localhost:5000 tagged images..."
LOCALHOST_IMAGES=$(docker images --format "table {{.Repository}}:{{.Tag}}" | grep "localhost:5000" | awk '{print $1}' || true)
if [ -n "$LOCALHOST_IMAGES" ]; then
    echo "$LOCALHOST_IMAGES" | xargs docker rmi -f || log_warning "Some localhost:5000 images could not be removed"
    log_success "Cleaned up localhost:5000 tagged images"
else
    log_info "No localhost:5000 tagged images found"
fi

log_success "🎉 Local registry cleanup complete!"