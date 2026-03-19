#!/usr/bin/env bash
# SPDX-FileCopyrightText: The RamenDR authors
# SPDX-License-Identifier: Apache-2.0
#
# Check cluster CSI capabilities: NetworkFence, CSI replication addon, VolumeGroupReplication.
# Usage: ./check_cluster_csi_capabilities.sh [--mode networkfence|replication|volumegroupreplication|all]
#   --mode: which capabilities to check (default: networkfence)
#   CHECK_MODE env var overrides --mode if set

set -euo pipefail

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1" >&2; exit 1; }; }
need_cmd kubectl
need_cmd jq
need_cmd awk
need_cmd sort
need_cmd sed

# Optional: set to reduce pod output (regex-like string used by jq test(...;"i"))
POD_HINT="${POD_HINT:-}"

# Parse --mode argument
CHECK_MODE="${CHECK_MODE:-networkfence}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      CHECK_MODE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--mode networkfence|replication|volumegroupreplication|all]" >&2
      exit 2
      ;;
  esac
done

case "$CHECK_MODE" in
  networkfence|replication|volumegroupreplication|all) ;;
  *)
    echo "ERROR: invalid --mode '$CHECK_MODE'. Must be: networkfence, replication, volumegroupreplication, or all" >&2
    exit 2
    ;;
esac

EXIT_CODE=0

check_kubectl_connectivity() {
  echo
  echo "## 0) kubectl connectivity"
  ctx="$(kubectl config current-context 2>/dev/null || true)"
  if [[ -z "${ctx}" ]]; then
    echo "ERROR: kubectl has no current context."
    echo "Fix: kubectl config use-context <context>"
    exit 2
  fi
  echo "Context: ${ctx}"
  kubectl version --request-timeout=5s >/dev/null 2>&1 || {
    echo "ERROR: kubectl cannot reach the API server for context '${ctx}'."
    exit 2
  }
  echo "OK: API reachable."
}

check_networkfence() {
  echo
  echo "== NetworkFence / CSI-Addons detection =="
  echo
  echo "## 1) Installed CSI drivers (CSIDriver objects)"
  if kubectl get csidriver >/dev/null 2>&1; then
    kubectl get csidriver -o json \
      | jq -r '.items[] | [.metadata.name, (.spec.attachRequired|tostring), (.spec.podInfoOnMount|tostring)] | @tsv' \
      | awk -F'\t' '
BEGIN{printf "%-50s %-14s %-14s\n","DRIVER","attachRequired","podInfoOnMount"; print "-------------------------------------------------------------------------------------------"}
{printf "%-50s %-14s %-14s\n",$1,$2,$3}
'
  else
    echo "RESULT: No CSIDriver objects found."
  fi

  echo
  echo "## 2) CRD presence (NetworkFence, NetworkFenceClass, CSIAddonsNode)"
  crds_json="$(kubectl get crd -o json)"

  nf_crds="$(echo "$crds_json" | jq -r '.items[] | select(.metadata.name|test("(^|\\.)networkfences\\."; "i")) | .metadata.name')"
  nfc_crds="$(echo "$crds_json" | jq -r '.items[] | select(.metadata.name|test("(^|\\.)networkfenceclasses\\."; "i")) | .metadata.name')"
  csiaddonsnode_crd="$(echo "$crds_json" | jq -r '.items[] | select(.metadata.name|test("(^|\\.)csiaddonsnodes\\."; "i")) | .metadata.name' | head -n 1)"

  if [[ -z "${nf_crds}" && -z "${nfc_crds}" ]]; then
    echo "RESULT: NetworkFence CRDs not found."
    EXIT_CODE=1
  else
    echo "OK: NetworkFence CRD(s):"
    [[ -n "${nf_crds}" ]]  && echo "${nf_crds}"  | sed 's/^/  - /'
    [[ -n "${nfc_crds}" ]] && echo "${nfc_crds}" | sed 's/^/  - /'
  fi

  if [[ -z "${csiaddonsnode_crd}" || "${csiaddonsnode_crd}" == "null" ]]; then
    echo "RESULT: CSIAddonsNode CRD not found."
    EXIT_CODE=1
  else
    echo "OK: CSIAddonsNode CRD: ${csiaddonsnode_crd}"
  fi

  echo
  echo "## 3) Heuristic check: is csi-addons sidecar deployed in any pods?"
  pods_json="$(kubectl get pods -A -o json)"

  if [[ -n "${POD_HINT}" ]]; then
    pods_json="$(echo "$pods_json" | jq --arg hint "${POD_HINT}" '
      .items |= map(select((.metadata.name//"")|test($hint;"i") or (.metadata.namespace//"")|test($hint;"i")))
    ')"
    echo "Applied POD_HINT filter: ${POD_HINT}"
  fi

  sidecar_pods="$(echo "$pods_json" | jq -r '
    .items[]
    | . as $p
    | ($p.spec.containers // []) | map(.name) as $names
    | select($names | any(test("csi(-|)?addons"; "i")))
    | "\($p.metadata.namespace)/\($p.metadata.name) :: containers=" + ($names | join(","))
  ' | sort -u)"

  if [[ -z "${sidecar_pods}" ]]; then
    echo "RESULT: No pods found with container name matching /csi[-]?addons/i."
    EXIT_CODE=1
  else
    echo "OK: Found pods with csi-addons sidecar:"
    echo "${sidecar_pods}" | sed 's/^/  - /'
  fi

  echo
  echo "## 4) Per-driver NetworkFence summary via CSIAddonsNode"
  if [[ -z "${csiaddonsnode_crd}" || "${csiaddonsnode_crd}" == "null" ]]; then
    echo "SKIP: CSIAddonsNode CRD is not installed."
  else
    resource="${csiaddonsnode_crd}"
    nodes_json="$(kubectl get "${resource}" -A -o json)"
    count="$(echo "$nodes_json" | jq '.items | length')"

    if [[ "$count" -eq 0 ]]; then
      echo "RESULT: ${resource} exists but there are 0 CSIAddonsNode objects."
      EXIT_CODE=1
    else
      echo "OK: Found ${count} CSIAddonsNode object(s)."
      echo "$nodes_json" | jq -r '
        .items[]
        | {
            driver: (.spec.driver.name // "-"),
            caps: (.status.capabilities // [])
          }
        | .driver as $d
        | [
            $d,
            ((.caps | map(ascii_downcase) | any(test("network_fence\\.network_fence|network_fence.*network_fence"))) | tostring),
            ((.caps | map(ascii_downcase) | any(test("network_fence\\.get_clients_to_fence|get_clients_to_fence"))) | tostring)
          ]
        | @tsv
      ' | awk -F'\t' '
      {
        d=$1; nf=$2; gc=$3;
        if (!(d in seen)) { seen[d]=1; has_nf[d]=nf; has_gc[d]=gc; }
        else {
          if (nf=="true") has_nf[d]="true";
          if (gc=="true") has_gc[d]="true";
        }
      }
      END{
        printf "%-45s %-18s %-22s\n","DRIVER","NETWORK_FENCE_RPC","GET_CLIENTS_TO_FENCE"
        print "---------------------------------------------------------------------------------------------------------------"
        for (d in seen) printf "%-45s %-18s %-22s\n", d, has_nf[d], has_gc[d]
      }
      ' | sort
    fi
  fi

  echo
  echo "== NetworkFence notes =="
  echo "- NETWORK_FENCE_RPC=true means the driver advertises fence/unfence support via CSI-Addons."
  echo "- GET_CLIENTS_TO_FENCE=true means the driver advertises client discovery for NetworkFenceClass workflow."
}

check_csi_replication() {
  echo
  echo "== CSI Replication Addon detection =="

  echo
  echo "## Replication CRDs"
  if kubectl get crd volumereplications.replication.storage.openshift.io >/dev/null 2>&1; then
    echo "OK: volumereplications.replication.storage.openshift.io"
  else
    echo "RESULT: volumereplications.replication.storage.openshift.io not found."
    echo "        Install from kubernetes-csi-addons (e.g. deploy/controller/crds.yaml)"
    EXIT_CODE=1
  fi

  if kubectl get crd volumereplicationclasses.replication.storage.openshift.io >/dev/null 2>&1; then
    echo "OK: volumereplicationclasses.replication.storage.openshift.io"
  else
    echo "RESULT: volumereplicationclasses.replication.storage.openshift.io not found."
    EXIT_CODE=1
  fi

  echo
  echo "## CSIAddonsNode replication capability"
  csiaddonsnode_crd="$(kubectl get crd -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name|test("(^|\\.)csiaddonsnodes\\."; "i")) | .metadata.name' | head -n 1)"
  if [[ -z "${csiaddonsnode_crd}" || "${csiaddonsnode_crd}" == "null" ]]; then
    echo "SKIP: CSIAddonsNode CRD not installed."
    EXIT_CODE=1
  else
    nodes_json="$(kubectl get "${csiaddonsnode_crd}" -A -o json 2>/dev/null)"
    has_replication="$(echo "$nodes_json" | jq -r '
      .items[]
      | select((.status.capabilities // []) | map(if type == "string" then ascii_downcase else ((.name // . | tostring) | ascii_downcase) end) | any(test("replication")))
      | .spec.driver.name // empty
    ' 2>/dev/null | head -n 1)"

    if [[ -n "${has_replication}" ]]; then
      echo "OK: Driver(s) advertise replication capability (e.g. $has_replication)"
    else
      echo "RESULT: No CSIAddonsNode advertises replication capability."
      echo "        CSI driver may not support replication; or install CRDs from kubernetes-csi-addons."
      EXIT_CODE=1
    fi
  fi
}

check_volumegroupreplication() {
  echo
  echo "== VolumeGroupReplication detection =="

  echo
  echo "## VGR CRDs"
  for crd in volumegroupreplications.replication.storage.openshift.io \
             volumegroupreplicationclasses.replication.storage.openshift.io \
             volumegroupreplicationcontents.replication.storage.openshift.io; do
    if kubectl get crd "$crd" >/dev/null 2>&1; then
      echo "OK: $crd"
    else
      echo "RESULT: $crd not found."
      echo "        Install from kubernetes-csi-addons. Rook/Ceph may not ship these CRDs."
      EXIT_CODE=1
    fi
  done

  echo
  echo "## Replication capability (backend support)"
  csiaddonsnode_crd="$(kubectl get crd -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name|test("(^|\\.)csiaddonsnodes\\."; "i")) | .metadata.name' | head -n 1)"
  if [[ -z "${csiaddonsnode_crd}" || "${csiaddonsnode_crd}" == "null" ]]; then
    echo "SKIP: CSIAddonsNode CRD not installed."
    EXIT_CODE=1
  else
    nodes_json="$(kubectl get "${csiaddonsnode_crd}" -A -o json 2>/dev/null)"
    has_replication="$(echo "$nodes_json" | jq -r '
      .items[]
      | select((.status.capabilities // []) | map(if type == "string" then ascii_downcase else ((.name // . | tostring) | ascii_downcase) end) | any(test("replication")))
      | .spec.driver.name // empty
    ' 2>/dev/null | head -n 1)"

    if [[ -n "${has_replication}" ]]; then
      echo "OK: Driver advertises replication (VGR uses same gRPC APIs): $has_replication"
    else
      echo "RESULT: No driver advertises replication. VGR requires replication capability."
      echo "        If CRDs are installed but capability missing: CSI driver may need update."
      EXIT_CODE=1
    fi
  fi

  echo
  echo "== VolumeGroupReplication notes =="
  echo "- VGR CRDs come from kubernetes-csi-addons. Rook (v1.10+) no longer ships them."
  echo "- Ceph CSI driver supports replication; install CRDs if missing."
}

# Main
check_kubectl_connectivity

case "$CHECK_MODE" in
  networkfence)
    check_networkfence
    ;;
  replication)
    check_csi_replication
    ;;
  volumegroupreplication)
    check_volumegroupreplication
    ;;
  all)
    check_networkfence
    check_csi_replication
    check_volumegroupreplication
    ;;
esac

exit "${EXIT_CODE}"
