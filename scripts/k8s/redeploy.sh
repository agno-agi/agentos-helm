#!/bin/bash

############################################################################
#
#    Agno Kubernetes Redeploy
#
#    Usage:
#      ./scripts/k8s/redeploy.sh                  # restart pods (re-pull same tag)
#      IMAGE_TAG=v2 ./scripts/k8s/redeploy.sh     # roll to a new image tag
#
#    Run after building + pushing a new image (or `kind load docker-image`
#    on a local cluster). With IMAGE_TAG set, the release is upgraded to
#    the new tag; otherwise the deployment restarts in place — which picks
#    up a re-pushed/re-loaded image only when it actually reached the
#    cluster (pullPolicy IfNotPresent uses the node's copy).
#
#    Overrides (env vars): AGENTOS_NAMESPACE (agentos), AGENTOS_RELEASE (agentos)
#
############################################################################

set -e

# Colors
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

if ! command -v kubectl &> /dev/null || ! command -v helm &> /dev/null; then
    echo "kubectl + helm are required. See the README prerequisites."
    exit 1
fi

NAMESPACE="${AGENTOS_NAMESPACE:-agentos}"
RELEASE="${AGENTOS_RELEASE:-agentos}"

if ! helm status "$RELEASE" -n "$NAMESPACE" &> /dev/null; then
    echo "Release '${RELEASE}' not found in namespace '${NAMESPACE}'. Run ./scripts/k8s/up.sh first."
    exit 1
fi

# helm's fullname: the release name when it already contains the chart name.
FULLNAME="$RELEASE"
[[ "$RELEASE" != *agentos* ]] && FULLNAME="${RELEASE}-agentos"

echo ""
if [[ -n "$IMAGE_TAG" ]]; then
    echo -e "${BOLD}Rolling ${RELEASE} to image tag ${IMAGE_TAG}...${NC}"
    helm upgrade "$RELEASE" charts/agentos \
        --namespace "$NAMESPACE" \
        --reuse-values --set-string "image.tag=${IMAGE_TAG}" \
        --wait --timeout 10m
else
    echo -e "${BOLD}Restarting ${FULLNAME}...${NC}"
    kubectl rollout restart "deployment/${FULLNAME}" -n "$NAMESPACE"
    kubectl rollout status "deployment/${FULLNAME}" -n "$NAMESPACE" --timeout 10m
fi

echo ""
echo -e "${BOLD}Done.${NC}"
echo -e "${DIM}Logs: kubectl logs deploy/${FULLNAME} -n ${NAMESPACE} -f${NC}"
echo ""
