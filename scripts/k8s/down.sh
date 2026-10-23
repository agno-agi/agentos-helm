#!/bin/bash

############################################################################
#
#    Agno Kubernetes Teardown
#
#    Usage:
#      ./scripts/k8s/down.sh          # asks before destroying
#      ./scripts/k8s/down.sh --yes    # no prompt (CI / automation)
#
#    Uninstalls the release AND deletes the database volume — all data in
#    the database is deleted. The namespace itself is left in place (it may
#    be shared); the script prints the optional delete command. Verify
#    afterwards with `helm list -n <namespace>`.
#
#    Overrides (env vars): AGENTOS_NAMESPACE (agentos), AGENTOS_RELEASE (agentos)
#
############################################################################

set -e

# Colors
ORANGE='\033[38;5;208m'
DIM='\033[2m'
BOLD='\033[1m'
RED='\033[31m'
NC='\033[0m'

# Preflight
if ! command -v kubectl &> /dev/null || ! command -v helm &> /dev/null; then
    echo "kubectl + helm are required. See the README prerequisites."
    exit 1
fi

NAMESPACE="${AGENTOS_NAMESPACE:-agentos}"
RELEASE="${AGENTOS_RELEASE:-agentos}"
CONTEXT="$(kubectl config current-context 2> /dev/null || true)"

if ! helm status "$RELEASE" -n "$NAMESPACE" &> /dev/null; then
    echo "Release '${RELEASE}' not found in namespace '${NAMESPACE}' (context '${CONTEXT}') — nothing to tear down."
    echo "Check: helm list -A"
    exit 1
fi

echo ""
echo -e "${ORANGE}▸${NC} ${BOLD}Kubernetes Teardown${NC}"
echo ""
echo -e "This deletes from context ${CONTEXT}, namespace ${NAMESPACE}:"
echo -e "  - release   ${RELEASE} (api + database)"
echo -e "  - volume    the Postgres PVC  ${RED}(all data deleted)${NC}"
echo ""

if [[ "$1" != "--yes" ]]; then
    printf "Type the release name (%s) to confirm: " "$RELEASE"
    IFS= read -r CONFIRM
    if [[ "$CONFIRM" != "$RELEASE" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

echo ""
echo -e "${DIM}> helm uninstall ${RELEASE} -n ${NAMESPACE} --wait${NC}"
helm uninstall "$RELEASE" -n "$NAMESPACE" --wait \
    || echo -e "${DIM}Uninstall returned non-zero — verifying below${NC}"

# volumeClaimTemplates PVCs survive uninstall by design; they carry the
# instance label (set in the chart) so they can be deleted here.
echo ""
echo -e "${DIM}> kubectl delete pvc -n ${NAMESPACE} -l app.kubernetes.io/instance=${RELEASE}${NC}"
kubectl delete pvc -n "$NAMESPACE" \
    -l "app.kubernetes.io/instance=${RELEASE}" \
    --ignore-not-found --timeout=120s

# The release only counts as gone when neither helm nor the cluster still
# knows it — an API blip mid-uninstall would otherwise read as success.
if helm status "$RELEASE" -n "$NAMESPACE" &> /dev/null; then
    echo ""
    echo -e "${RED}${BOLD}Teardown incomplete${NC} — helm still lists the release. Retry:"
    echo -e "${DIM}  helm uninstall ${RELEASE} -n ${NAMESPACE}${NC}"
    exit 1
fi
# helm's --wait covers the release's resources, not the pods they own —
# those are removed by cascading GC and linger in Terminating for their
# grace period. Give them that window before judging leftovers.
kubectl wait pods -n "$NAMESPACE" \
    -l "app.kubernetes.io/instance=${RELEASE}" \
    --for=delete --timeout=90s > /dev/null 2>&1 || true
LEFT="$(kubectl get pods,pvc -n "$NAMESPACE" -l "app.kubernetes.io/instance=${RELEASE}" -o name 2> /dev/null || true)"
if [[ -n "$LEFT" ]]; then
    echo ""
    echo -e "${RED}${BOLD}Teardown incomplete${NC} — still present:"
    echo "$LEFT"
    exit 1
fi

echo ""
echo -e "${BOLD}Done.${NC} Release and data volume confirmed gone."
echo -e "${DIM}Namespace kept (may be shared). Remove it too: kubectl delete namespace ${NAMESPACE}${NC}"
echo -e "${DIM}Verify anytime: helm list -n ${NAMESPACE}${NC}"
echo ""
