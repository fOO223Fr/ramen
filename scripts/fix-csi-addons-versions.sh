#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Script to update CSI Addons controller and sidecar to compatible official versions
# Required for gRPC connectivity

set -e

echo "Updating CSI Addons to official compatible versions..."

# Update CSI Addons versions on both clusters
hack/fix-csi-addons-versions.sh dr1
hack/fix-csi-addons-versions.sh dr2

echo "✓ CSI Addons versions updated on both clusters"