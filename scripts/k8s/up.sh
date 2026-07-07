#!/bin/bash

############################################################################
#
#    Agno Kubernetes Setup (helm install / first-time provisioning)
#
#    Usage:     ./scripts/k8s/up.sh [--yes]
#    Redeploy:  ./scripts/k8s/redeploy.sh
#    Sync env:  ./scripts/k8s/env-sync.sh
#    Teardown:  ./scripts/k8s/down.sh
#
#    Prerequisites:
#      - kubectl pointed at the target cluster, helm 3+
#      - OPENAI_API_KEY set in environment (or .env / .env.production)
#      - An image the cluster can pull. Default: the official agnohq/agentos.
#        Customized the platform? Build your own:
#          docker build -t <registry>/agentos:<tag> . && docker push …
#          IMAGE_REPOSITORY=<registry>/agentos IMAGE_TAG=<tag> ./scripts/k8s/up.sh
#        or for kind: docker build -t agentos:kind . && kind load docker-image agentos:kind
#
#    Overrides (env vars): AGENTOS_NAMESPACE (agentos), AGENTOS_RELEASE
#    (agentos), IMAGE_REPOSITORY, IMAGE_TAG, IMAGE_PULL_POLICY,
#    INGRESS_HOST, INGRESS_CLASS.
#
#    Deploys into the CURRENT kubectl context (asks first on a TTY; --yes
#    or non-interactive runs proceed against the printed context). Pauses
#    for JWT_VERIFICATION_KEY when production auth would otherwise prevent
#    the deploy from serving. DB_PASS is generated once and written back to
#    your env file — keep it, the database volume remembers it.
#
############################################################################

set -e

# Colors
ORANGE='\033[38;5;208m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${ORANGE}"
cat << 'BANNER'
     █████╗  ██████╗ ███╗   ██╗ ██████╗
    ██╔══██╗██╔════╝ ████╗  ██║██╔═══██╗
    ███████║██║  ███╗██╔██╗ ██║██║   ██║
    ██╔══██║██║   ██║██║╚██╗██║██║   ██║
    ██║  ██║╚██████╔╝██║ ╚████║╚██████╔╝
    ╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝
BANNER
echo -e "${NC}"

# Persist a resolved single-line value back into the env file so it stays a
# faithful record of the deploy. Replaces an existing commented-or-uncommented
# `KEY=` line in place; appends if the key is absent. Rewrites via the
# original file (not `mv`) so the file keeps its inode + permissions.
persist_env_var() {
    local key="$1" value="$2" file="$3" tmp
    if [[ -z "$file" ]]; then
        return
    fi
    [[ -f "$file" ]] || touch "$file"
    if grep -qE "^[#[:space:]]*${key}=" "$file"; then
        tmp="$(mktemp)"
        if sed -E "s|^[#[:space:]]*${key}=.*|${key}=${value}|" "$file" > "$tmp"; then
            cat "$tmp" > "$file"
        fi
        rm -f "$tmp"
    else
        printf '\n%s=%s\n' "$key" "$value" >> "$file"
    fi
}

# Persist a multi-line env value. Existing active KEY= blocks are removed
# before appending; commented examples are left alone as documentation.
persist_multiline_env_var() {
    local key="$1" value="$2" file="$3" tmp line skipping=0 value_part
    if [[ -z "$file" ]]; then
        return
    fi
    if [[ ! -f "$file" ]]; then
        printf '%s="%s"\n' "$key" "$value" > "$file"
        return
    fi

    # Values are written quoted so compose's env_file parser (and every
    # script parser here, which strips quotes) reads the PEM as one variable.
    tmp="$(mktemp)"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$skipping" == 1 ]]; then
            [[ "$line" == *"-----END"* ]] && skipping=0
            continue
        fi

        if [[ "$line" =~ ^[[:space:]]*${key}= ]]; then
            value_part="${line#*=}"
            if [[ "$value_part" == *"-----BEGIN"* && "$value_part" != *"-----END"* ]]; then
                skipping=1
            fi
            continue
        fi

        printf '%s\n' "$line" >> "$tmp"
    done < "$file"

    [[ -s "$tmp" ]] && printf '\n' >> "$tmp"
    printf '%s="%s"\n' "$key" "$value" >> "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

# Load env file — .env.production preferred, .env as fallback. Parsed
# line-by-line (not `source`d) so an unquoted multi-line PEM isn't
# interpreted as shell. A function so the JWT pause below can re-read the
# file after the user edits it.
load_env_file() {
    local line current_key="" current_value=""
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$current_key" ]]; then
            [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        fi

        if [[ -z "$current_key" ]]; then
            current_key="${line%%=*}"
            current_value="${line#*=}"
        else
            current_value="${current_value}
${line}"
        fi

        # Still inside a PEM block — keep accumulating lines.
        if [[ "$current_value" == *"-----BEGIN"* && "$current_value" != *"-----END"* ]]; then
            continue
        fi

        # Strip surrounding quotes if present
        current_value="${current_value#\"}"
        current_value="${current_value%\"}"
        current_value="${current_value#\'}"
        current_value="${current_value%\'}"

        export "${current_key}=${current_value}"

        current_key=""
        current_value=""
    done < "$1"
}

capture_pasted_jwt_verification_key() {
    local line pasted="$1"

    pasted="${pasted#export JWT_VERIFICATION_KEY=}"
    pasted="${pasted#JWT_VERIFICATION_KEY=}"
    [[ "$pasted" != *"-----BEGIN"* ]] && return 1

    while [[ "$pasted" != *"-----END"* ]]; do
        if ! IFS= read -r line; then
            break
        fi
        pasted="${pasted}
${line}"
    done

    [[ "$pasted" != *"-----BEGIN"* || "$pasted" != *"-----END"* ]] && return 1

    pasted="${pasted#\"}"
    pasted="${pasted%\"}"
    pasted="${pasted#\'}"
    pasted="${pasted%\'}"

    JWT_VERIFICATION_KEY="$pasted"
    export JWT_VERIFICATION_KEY
}

# YAML single-quoted scalar (doubles embedded single quotes)
yaml_sq() {
    local v="${1//\'/\'\'}"
    printf "'%s'" "$v"
}

ENV_FILE=""
[[ -f .env.production ]] && ENV_FILE=".env.production"
[[ -z "$ENV_FILE" && -f .env ]] && ENV_FILE=".env"

if [[ -n "$ENV_FILE" ]]; then
    load_env_file "$ENV_FILE"
    echo -e "${DIM}Loaded ${ENV_FILE}${NC}"
fi

# Preflight
if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found. Install: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi
if ! command -v helm &> /dev/null; then
    echo "helm not found. Install: https://helm.sh/docs/intro/install/"
    exit 1
fi
if [[ -z "$OPENAI_API_KEY" ]]; then
    echo "OPENAI_API_KEY not set. Add to .env (or .env.production) or export it."
    exit 1
fi

CONTEXT="$(kubectl config current-context 2> /dev/null || true)"
if [[ -z "$CONTEXT" ]]; then
    echo "No current kubectl context. Point kubectl at a cluster first."
    exit 1
fi
if ! kubectl get namespace --request-timeout=15s -o name > /dev/null 2>&1; then
    echo "Cluster for context '${CONTEXT}' is not reachable."
    exit 1
fi

NAMESPACE="${AGENTOS_NAMESPACE:-agentos}"
RELEASE="${AGENTOS_RELEASE:-agentos}"

echo ""
echo -e "${BOLD}Deploying to kubectl context: ${CONTEXT}${NC}  ${DIM}(namespace ${NAMESPACE}, release ${RELEASE})${NC}"
if [[ "$1" != "--yes" && -t 0 ]]; then
    printf "Continue? [y/N] "
    IFS= read -r GO
    if [[ "$GO" != "y" && "$GO" != "Y" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# The database password is minted once and recorded in the env file: the
# Postgres volume only reads it on first initialization, so a regenerated
# password against an existing volume locks the app out.
if [[ -z "$DB_PASS" ]]; then
    DB_PASS="$(openssl rand -hex 16)"
    ENV_FILE="${ENV_FILE:-.env.production}"
    persist_env_var DB_PASS "$DB_PASS" "$ENV_FILE"
    echo -e "${DIM}Generated DB_PASS (saved to ${ENV_FILE})${NC}"
fi

AUTH_REQUIRES_JWT=1
[[ "${RUNTIME_ENV:-prd}" == "dev" ]] && AUTH_REQUIRES_JWT=""

# JWT auth is on in prd and the app refuses to serve without a verification
# key. Pause so the user can mint one at os.agno.com and have the first
# deploy come up serving.
if [[ -n "$AUTH_REQUIRES_JWT" && -z "$JWT_VERIFICATION_KEY" && -z "$JWT_JWKS_FILE" && -t 0 ]]; then
    echo ""
    echo -e "${BOLD}JWT_VERIFICATION_KEY not set${NC} — AgentOS won't serve production traffic without auth."
    echo -e "  1. Open ${BOLD}https://os.agno.com${NC} -> Connect OS -> Live -> enter ${INGRESS_HOST:+https://}${INGRESS_HOST:-your AgentOS URL}"
    echo -e "  2. Name it ${BOLD}Live AgentOS${NC}"
    echo -e "  3. Note: Live AgentOS Connections are a paid feature; use ${BOLD}PLATFORM30${NC} to get 1 month off"
    echo -e "  4. Go to Settings -> OS & Security -> turn ${BOLD}Token-Based Authorization (JWT)${NC} on"
    echo -e "  5. Copy the public key"
    echo -e "  6. Paste the full PEM block at the prompt below, or save it in ${ENV_FILE:-.env.production}"
    echo ""
    echo -e "  Paste JWT_VERIFICATION_KEY now, or press Enter after saving it:"
    JWT_INPUT=""
    IFS= read -r JWT_INPUT || true
    if [[ -n "$JWT_INPUT" ]]; then
        if capture_pasted_jwt_verification_key "$JWT_INPUT"; then
            ENV_FILE="${ENV_FILE:-.env.production}"
            persist_multiline_env_var JWT_VERIFICATION_KEY "$JWT_VERIFICATION_KEY" "$ENV_FILE"
            echo -e "${DIM}  Saved JWT_VERIFICATION_KEY to ${ENV_FILE}${NC}"
        else
            echo -e "${BOLD}Warning:${NC} couldn't parse the pasted JWT_VERIFICATION_KEY."
            echo -e "${DIM}  Save it to ${ENV_FILE:-.env.production} and run ./scripts/k8s/env-sync.sh if auth is still missing.${NC}"
        fi
    else
        [[ -f .env.production ]] && ENV_FILE=".env.production"
        [[ -z "$ENV_FILE" && -f .env ]] && ENV_FILE=".env"
    fi
    [[ -n "$ENV_FILE" ]] && load_env_file "$ENV_FILE"
fi

if [[ -n "$AUTH_REQUIRES_JWT" && -z "$JWT_VERIFICATION_KEY" && -z "$JWT_JWKS_FILE" ]]; then
    echo ""
    echo -e "${DIM}Deploying without JWT auth config — the app will refuse traffic until${NC}"
    echo -e "${DIM}you add JWT_VERIFICATION_KEY to ${ENV_FILE:-.env.production} and run ./scripts/k8s/env-sync.sh.${NC}"
fi

# Secrets ride a values file (0600, deleted on exit), not --set args.
mkdir -p tmp
VALUES_FILE="tmp/values-secrets.yaml"
: > "$VALUES_FILE"
chmod 600 "$VALUES_FILE"
trap 'rm -f "$VALUES_FILE"' EXIT

{
    printf 'runtimeEnv: %s\n' "$(yaml_sq "${RUNTIME_ENV:-prd}")"
    if [[ -n "$AGENTOS_URL" ]]; then
        printf 'agentosUrl: %s\n' "$(yaml_sq "$AGENTOS_URL")"
    fi
    if [[ -n "$IMAGE_REPOSITORY" || -n "$IMAGE_TAG" || -n "$IMAGE_PULL_POLICY" ]]; then
        printf 'image:\n'
        if [[ -n "$IMAGE_REPOSITORY" ]]; then printf '  repository: %s\n' "$(yaml_sq "$IMAGE_REPOSITORY")"; fi
        if [[ -n "$IMAGE_TAG" ]]; then printf '  tag: %s\n' "$(yaml_sq "$IMAGE_TAG")"; fi
        if [[ -n "$IMAGE_PULL_POLICY" ]]; then printf '  pullPolicy: %s\n' "$(yaml_sq "$IMAGE_PULL_POLICY")"; fi
    fi
    if [[ -n "$INGRESS_HOST" ]]; then
        printf 'ingress:\n  enabled: true\n  host: %s\n' "$(yaml_sq "$INGRESS_HOST")"
        if [[ -n "$INGRESS_CLASS" ]]; then printf '  className: %s\n' "$(yaml_sq "$INGRESS_CLASS")"; fi
    fi
    printf 'secrets:\n'
    printf '  openaiApiKey: %s\n' "$(yaml_sq "$OPENAI_API_KEY")"
    if [[ -n "$JWT_VERIFICATION_KEY" ]]; then
        printf '  jwtVerificationKey: |-\n'
        printf '%s\n' "$JWT_VERIFICATION_KEY" | sed 's/^/    /'
    fi
    if [[ -n "$PARALLEL_API_KEY" ]]; then printf '  parallelApiKey: %s\n' "$(yaml_sq "$PARALLEL_API_KEY")"; fi
    if [[ -n "$SLACK_BOT_TOKEN" ]]; then printf '  slackBotToken: %s\n' "$(yaml_sq "$SLACK_BOT_TOKEN")"; fi
    if [[ -n "$SLACK_SIGNING_SECRET" ]]; then printf '  slackSigningSecret: %s\n' "$(yaml_sq "$SLACK_SIGNING_SECRET")"; fi
    printf 'postgres:\n  auth:\n    password: %s\n' "$(yaml_sq "$DB_PASS")"
} >> "$VALUES_FILE"

echo ""
echo -e "${BOLD}Installing ${RELEASE} into ${NAMESPACE}...${NC}"
echo ""
helm upgrade --install "$RELEASE" charts/agentos \
    --namespace "$NAMESPACE" --create-namespace \
    -f "$VALUES_FILE" \
    --wait --timeout 15m

# helm's fullname: the release name when it already contains the chart name.
FULLNAME="$RELEASE"
[[ "$RELEASE" != *agentos* ]] && FULLNAME="${RELEASE}-agentos"

echo ""
echo -e "${BOLD}Done.${NC}"
if [[ -n "$INGRESS_HOST" ]]; then
    echo -e "${DIM}URL:            https://${INGRESS_HOST}  (docs at /docs, MCP at /mcp)${NC}"
else
    echo -e "${DIM}Reach it:       kubectl port-forward svc/${FULLNAME} 8000:8000 -n ${NAMESPACE}${NC}"
    echo -e "${DIM}                then http://localhost:8000/docs${NC}"
fi
echo -e "${DIM}Logs:           kubectl logs deploy/${FULLNAME} -n ${NAMESPACE} -f${NC}"
echo -e "${DIM}Sync env vars:  ./scripts/k8s/env-sync.sh  (defaults to .env.production)${NC}"
[[ -n "$INGRESS_HOST" ]] && echo -e "${DIM}Connect apps:   uvx agno connect --url https://${INGRESS_HOST}  (Claude Desktop + coding agents; mints a service-account token — see README)${NC}"
echo -e "${DIM}Teardown:       ./scripts/k8s/down.sh${NC}"
echo ""
