#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Script to apply container image and flag format fixes to CSI provisioner deployments
# Required for Ceph CSI compatibility

set -e

echo "Applying CSI provisioner fixes for Ceph CSI compatibility..."

# Run the existing hack script
exec hack/fix-csi-provisioners.sh