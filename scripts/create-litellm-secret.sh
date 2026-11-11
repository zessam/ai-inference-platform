#!/usr/bin/env bash
# Creates the Secret litellm/litellm-secrets for the LiteLLM proxy
# (helm/management/litellm/litellm):
#   LITELLM_MASTER_KEY  admin key for the API and the UI (password for "admin")
#   LITELLM_SALT_KEY    encrypts credentials stored in the database
# The keys are generated once and kept in .lab-secrets.json (git-ignored).
# Existing keys are reused. Do not change the salt key after the first start.
# scripts/argocd-deployment.sh does the same step.
# Run from any directory. Works in Git Bash on Windows. Safe to run again.
set -euo pipefail

cd "$(dirname "$0")/.."   # repo root

SECRETS_FILE=".lab-secrets.json"
[[ -f "$SECRETS_FILE" ]] || { echo "Missing $SECRETS_FILE. Run scripts/argocd-deployment.sh first."; exit 1; }

json_get() {
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$SECRETS_FILE"
}
gen() {
  local out
  out=$(LC_ALL=C tr -dc "$1" </dev/urandom 2>/dev/null | head -c "$2" || true)
  [[ ${#out} -eq $2 ]] || { echo "Key generation failed"; exit 1; }
  printf '%s' "$out"
}

# json_add <key> <value>: add a key to the end of the JSON object.
json_add() {
  local tmp
  tmp=$(mktemp)
  sed '$d' "$SECRETS_FILE" | sed '$s/"$/",/' > "$tmp"
  printf '  "%s": "%s"\n}\n' "$1" "$2" >> "$tmp"
  ( umask 077; cat "$tmp" > "$SECRETS_FILE" )
  rm -f "$tmp"
}

MASTER_KEY=$(json_get litellmMasterKey)
SALT_KEY=$(json_get litellmSaltKey)
if [[ -z "$MASTER_KEY" ]]; then
  MASTER_KEY="sk-$(gen 'A-Za-z0-9' 32)"; json_add litellmMasterKey "$MASTER_KEY"
  echo "==> Generated litellmMasterKey in $SECRETS_FILE"
fi
if [[ -z "$SALT_KEY" ]]; then
  SALT_KEY="sk-$(gen 'A-Za-z0-9' 32)"; json_add litellmSaltKey "$SALT_KEY"
  echo "==> Generated litellmSaltKey in $SECRETS_FILE"
fi

echo "==> Creating namespace litellm"
kubectl create namespace litellm --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying Secret litellm/litellm-secrets"
kubectl -n litellm create secret generic litellm-secrets \
  --from-literal=LITELLM_MASTER_KEY="$MASTER_KEY" \
  --from-literal=LITELLM_SALT_KEY="$SALT_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n litellm get secret litellm-secrets
