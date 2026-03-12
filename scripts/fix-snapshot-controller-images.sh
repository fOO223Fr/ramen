#!/bin/bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0

# Fix snapshot-controller to use working image version and compatible args.

set -e

echo "Fixing snapshot-controller image and arguments..."

# Check and update dr1 snapshot-controller
if kubectl --context=dr1 -n kube-system get deployment snapshot-controller >/dev/null 2>&1; then
    kubectl --context=dr1 -n kube-system patch deployment snapshot-controller --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "registry.k8s.io/sig-storage/snapshot-controller:v7.0.1"}]'
    kubectl --context=dr1 -n kube-system patch deployment snapshot-controller --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["--v=5", "--leader-election=true"]}]'
    echo "✓ Fixed dr1 snapshot-controller image and arguments"
else
    echo "⚠ snapshot-controller not found in dr1 cluster"
fi

# Check and update dr2 snapshot-controller
if kubectl --context=dr2 -n kube-system get deployment snapshot-controller >/dev/null 2>&1; then
    kubectl --context=dr2 -n kube-system patch deployment snapshot-controller --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/image", "value": "registry.k8s.io/sig-storage/snapshot-controller:v7.0.1"}]'
    kubectl --context=dr2 -n kube-system patch deployment snapshot-controller --type='json' \
        -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/args", "value": ["--v=5", "--leader-election=true"]}]'
    echo "✓ Fixed dr2 snapshot-controller image and arguments"
else
    echo "⚠ snapshot-controller not found in dr2 cluster"
fi
