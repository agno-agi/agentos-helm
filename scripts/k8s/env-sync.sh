#!/bin/bash

############################################################################
#
#    Agno Kubernetes Environment Sync
#
#    Usage:
#      ./scripts/k8s/env-sync.sh             # syncs .env.production
#      ./scripts/k8s/env-sync.sh .env        # syncs .env instead
#
#    Re-renders the release's secret values from the env file and helm-
#    upgrades with --reuse-values, so only what you changed moves. The
#    deployment's secret-checksum annotation rolls the pod automatically
#    when secret contents change. Multi-line values (PEM-formatted
#    JWT_VERIFICATION_KEY) are handled correctly; a set JWT_JWKS_FILE
#    ships the local file's content as secrets.jwtJwks and repoints the
#    pod at the mount.
#
#    Overrides (env vars): AGENTOS_NAMESPACE (agentos), AGENTOS_RELEASE (agentos)
#
############################################################################

set -e

# Colors
ORANGE='\033[38;5;208m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

ENV_FILE="${1:-.env.production}"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "File not found: $ENV_FILE"
    echo "Usage: $0 [path/to/env] (default: .env.production)"
    exit 1
fi

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

# `helm upgrade` (no --install) needs a deployed revision to upgrade from —
# against a release stuck in failed/pending-* (e.g. an interrupted install)
# it errors "has no deployed releases". Catch that early and point at the
# fix. Blocks only on a positively-detected non-deployed status.
RELEASE_STATUS="$(helm status "$RELEASE" -n "$NAMESPACE" -o json 2> /dev/null | grep -o '"status":"[^"]*"' | head -n 1 | cut -d '"' -f 4)"
if [[ -n "$RELEASE_STATUS" && "$RELEASE_STATUS" != "deployed" ]]; then
    echo "Release '${RELEASE}' is in status '${RELEASE_STATUS}' — helm can only upgrade a deployed release."
    echo "Re-run ./scripts/k8s/up.sh to repair it (a stuck pending-* release needs 'helm rollback' or './scripts/k8s/down.sh' first)."
    exit 1
fi

# Parse the env file, treating PEM blocks (and other multiline values) as a
# single variable — same parser as up.sh.
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

        if [[ "$current_value" == *"-----BEGIN"* && "$current_value" != *"-----END"* ]]; then
            continue
        fi

        current_value="${current_value#\"}"
        current_value="${current_value%\"}"
        current_value="${current_value#\'}"
        current_value="${current_value%\'}"

        export "${current_key}=${current_value}"

        current_key=""
        current_value=""
    done < "$1"
}

yaml_sq() {
    local v="${1//\'/\'\'}"
    printf "'%s'" "$v"
}

# Resolve the local file behind JWT_JWKS_FILE (a container path in the env
# file) — same resolver as up.sh.
resolve_jwks_local_file() {
    local path="$1"
    if [[ -f "$path" ]]; then
        printf '%s' "$path"
    elif [[ "$path" == /app/* && -f "${path#/app/}" ]]; then
        printf '%s' "${path#/app/}"
    else
        return 1
    fi
}

load_env_file "$ENV_FILE"

if [[ -z "$OPENAI_API_KEY" ]]; then
    echo "OPENAI_API_KEY not set in ${ENV_FILE} — refusing to sync an empty key."
    exit 1
fi

# The chart ships JWKS content and mounts it in-cluster — a dangling
# JWT_JWKS_FILE must fail here, not sync a release agno refuses to start.
JWKS_LOCAL=""
if [[ -n "$JWT_JWKS_FILE" ]]; then
    JWKS_LOCAL="$(resolve_jwks_local_file "$JWT_JWKS_FILE")" || true
    if [[ -z "$JWKS_LOCAL" || ! -r "$JWKS_LOCAL" || ! -s "$JWKS_LOCAL" ]]; then
        echo "JWT_JWKS_FILE=${JWT_JWKS_FILE} doesn't resolve to a readable, non-empty local file"
        echo "(tried the path as-is, then /app/… against the repo root). Fix the path or unset it."
        exit 1
    fi
fi

echo ""
echo -e "${ORANGE}▸${NC} ${BOLD}Syncing env vars${NC}"
echo ""
echo -e "${DIM}> ${ENV_FILE} -> release ${RELEASE} (namespace ${NAMESPACE})${NC}"
echo ""

mkdir -p tmp
VALUES_FILE="tmp/values-secrets.yaml"
: > "$VALUES_FILE"
chmod 600 "$VALUES_FILE"
trap 'rm -f "$VALUES_FILE"' EXIT

{
    if [[ -n "$RUNTIME_ENV" ]]; then printf 'runtimeEnv: %s\n' "$(yaml_sq "$RUNTIME_ENV")"; fi
    if [[ -n "$AGENTOS_URL" ]]; then printf 'agentosUrl: %s\n' "$(yaml_sq "$AGENTOS_URL")"; fi
    if [[ -n "$JWKS_LOCAL" ]]; then printf 'jwtJwksFile: /etc/agentos/jwks.json\n'; fi
    printf 'secrets:\n'
    printf '  openaiApiKey: %s\n' "$(yaml_sq "$OPENAI_API_KEY")"
    if [[ -n "$JWT_VERIFICATION_KEY" ]]; then
        printf '  jwtVerificationKey: |-\n'
        printf '%s\n' "$JWT_VERIFICATION_KEY" | sed 's/^/    /'
    fi
    if [[ -n "$JWKS_LOCAL" ]]; then
        printf '  jwtJwks: |-\n'
        printf '%s\n' "$(cat "$JWKS_LOCAL")" | sed 's/^/    /'
    fi
    if [[ -n "$MCP_CONNECT_SECRET" ]]; then printf '  mcpConnectSecret: %s\n' "$(yaml_sq "$MCP_CONNECT_SECRET")"; fi
    if [[ -n "$AGENTOS_MCP_SIGNING_KEY" ]]; then printf '  agentosMcpSigningKey: %s\n' "$(yaml_sq "$AGENTOS_MCP_SIGNING_KEY")"; fi
    if [[ -n "$PARALLEL_API_KEY" ]]; then printf '  parallelApiKey: %s\n' "$(yaml_sq "$PARALLEL_API_KEY")"; fi
    if [[ -n "$SLACK_BOT_TOKEN" ]]; then printf '  slackBotToken: %s\n' "$(yaml_sq "$SLACK_BOT_TOKEN")"; fi
    if [[ -n "$SLACK_SIGNING_SECRET" ]]; then printf '  slackSigningSecret: %s\n' "$(yaml_sq "$SLACK_SIGNING_SECRET")"; fi
    # DB_PASS only when the env file carries one — otherwise the release
    # keeps its current password (never regenerate against a live volume).
    if [[ -n "$DB_PASS" ]]; then
        printf 'postgres:\n  auth:\n    password: %s\n' "$(yaml_sq "$DB_PASS")"
    fi
} >> "$VALUES_FILE"

helm upgrade "$RELEASE" charts/agentos \
    --namespace "$NAMESPACE" \
    --reuse-values -f "$VALUES_FILE" \
    --wait --timeout 10m

echo ""
echo -e "${BOLD}Done.${NC} ${DIM}Changed secrets roll the pod automatically (checksum annotation).${NC}"
echo ""
