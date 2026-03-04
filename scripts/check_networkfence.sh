#!/usr/bin/env bash
set -euo pipefail

need_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing required command: $1" >&2; exit 1; }; }
need_cmd kubectl
need_cmd jq
need_cmd awk
need_cmd sort
need_cmd sed

# Optional: set to reduce pod output (regex-like string used by jq test(...;"i"))
POD_HINT="${POD_HINT:-}"

echo "== NetworkFence / CSI-Addons detection (single script) =="

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
else
  echo "OK: NetworkFence CRD(s):"
  [[ -n "${nf_crds}" ]]  && echo "${nf_crds}"  | sed 's/^/  - /'
  [[ -n "${nfc_crds}" ]] && echo "${nfc_crds}" | sed 's/^/  - /'
fi

if [[ -z "${csiaddonsnode_crd}" || "${csiaddonsnode_crd}" == "null" ]]; then
  echo "RESULT: CSIAddonsNode CRD not found."
else
  echo "OK: CSIAddonsNode CRD: ${csiaddonsnode_crd}"
fi

echo
echo "## 3) Heuristic check: is csi-addons sidecar deployed in any pods?"
pods_json="$(kubectl get pods -A -o json)"

# Optional narrowing
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
else
  echo "OK: Found pods with csi-addons sidecar:"
  echo "${sidecar_pods}" | sed 's/^/  - /'
fi

echo
echo "## 4) Definitive per-driver detection via CSIAddonsNode.status.capabilities"
if [[ -z "${csiaddonsnode_crd}" || "${csiaddonsnode_crd}" == "null" ]]; then
  echo "SKIP: CSIAddonsNode CRD is not installed, cannot read advertised capabilities."
  echo "      (Heuristic checks above are the only signal.)"
  exit 0
fi

resource="${csiaddonsnode_crd}" # already plural.group
nodes_json="$(kubectl get "${resource}" -A -o json)"
count="$(echo "$nodes_json" | jq '.items | length')"

if [[ "$count" -eq 0 ]]; then
  echo "RESULT: ${resource} exists but there are 0 CSIAddonsNode objects."
  echo "        Sidecars may not be registering or controller isn’t populating status."
  exit 0
fi

echo "OK: Found ${count} CSIAddonsNode object(s)."

echo
echo "### 4.1 Raw CSIAddonsNode capabilities"
echo "$nodes_json" | jq -r '
  .items[]
  | {
      ns: (.metadata.namespace // "-"),
      name: (.metadata.name // "-"),
      driver: (.spec.driver.name // "-"),
      nodeID: (.spec.driver.nodeID // "-"),
      state: (.status.state // "-"),
      caps: (.status.capabilities // [])
    }
  | [.ns, .name, .driver, .nodeID, .state, (.caps|join(","))] | @tsv
' | awk -F'\t' '
BEGIN{
  printf "%-18s %-45s %-45s %-18s %-12s %s\n","NAMESPACE","CSIADDONSNODE","DRIVER","NODEID","STATE","CAPABILITIES"
  print "----------------------------------------------------------------------------------------------------------------------------------------------------------------"
}
{
  printf "%-18s %-45s %-45s %-18s %-12s %s\n",$1,$2,$3,$4,$5,$6
}
'

echo
echo "### 4.2 Per-driver NetworkFence summary"
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

echo
echo "== Final notes =="
echo "- NETWORK_FENCE_RPC=true means the driver advertises fence/unfence support via CSI-Addons."
echo "- GET_CLIENTS_TO_FENCE=true means the driver advertises client discovery for NetworkFenceClass workflow."