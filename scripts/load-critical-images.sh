#!/bin/bash
# Load critical images directly to both clusters to avoid network issues

CRITICAL_IMAGES=(
    "registry.k8s.io/sig-storage/snapshot-controller:v7.0.1"
    "quay.io/csiaddons/k8s-controller:latest"
    "quay.io/cephcsi/cephcsi:v3.15.0" 
    "quay.io/rook/ceph:v1.18.9"
    "alpine:3.19"
)

echo "Loading critical images to both dr1 and dr2 clusters..."

for image in "${CRITICAL_IMAGES[@]}"; do
    echo "Loading $image to dr1..."
    minikube image load "$image" --profile=dr1 || echo "Failed to load $image to dr1"
    
    echo "Loading $image to dr2..." 
    minikube image load "$image" --profile=dr2 || echo "Failed to load $image to dr2"
done

echo "Restarting failed pods to pick up loaded images..."
kubectl --context=dr1 delete pods -n kube-system -l app.kubernetes.io/name=snapshot-controller || true
kubectl --context=dr2 delete pods -n kube-system -l app.kubernetes.io/name=snapshot-controller || true
kubectl --context=dr2 delete pods -n csi-addons-system -l control-plane=controller-manager || true

echo "Done!"