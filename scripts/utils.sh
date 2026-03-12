#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Shared utilities for CSI replication scripts

# Detect container runtime (prefer podman, fallback to docker).
# Override with CONTAINER_RUNTIME=podman|docker
#
# Usage: detect_container_runtime [--prefer-docker]
#   --prefer-docker: use docker when both are available (for PREFER_DOCKER compatibility)
#
# Sets CONTAINER_RUNTIME. Exits on failure.
detect_container_runtime() {
    local prefer_docker=false
    [[ "${1:-}" == "--prefer-docker" ]] && prefer_docker=true

    if [ -n "${CONTAINER_RUNTIME}" ]; then
        if command -v "$CONTAINER_RUNTIME" >/dev/null 2>&1 && $CONTAINER_RUNTIME info >/dev/null 2>&1; then
            return 0
        fi
        echo "CONTAINER_RUNTIME=$CONTAINER_RUNTIME is set but not available or not responsive" >&2
        exit 1
    fi

    if $prefer_docker && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        CONTAINER_RUNTIME="docker"
    elif command -v podman >/dev/null 2>&1 && podman info >/dev/null 2>&1; then
        CONTAINER_RUNTIME="podman"
    elif command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        CONTAINER_RUNTIME="docker"
    else
        echo "Neither podman nor docker is available and responsive. Install podman or docker." >&2
        exit 1
    fi
}
