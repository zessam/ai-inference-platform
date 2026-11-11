#!/usr/bin/env bash
# Creates the Secret inference/s3-models that the vLLM model download uses.
# The ServiceAccount inference/kserve-s3 (helm/inference/vllm) lists this
# Secret. The KServe storage-initializer reads the keys and the annotations.
# It uses the SeaweedFS read keys from .lab-secrets.json. The Secret is not in Git.
# scripts/argocd-deployment.sh does the same step.
# Run from any directory. Works in Git Bash on Windows. Safe to run again.
set -euo pipefail

cd "$(dirname "$0")/.."   # repo root

SECRETS_FILE=".lab-secrets.json"
[[ -f "$SECRETS_FILE" ]] || { echo "Missing $SECRETS_FILE. Run scripts/argocd-deployment.sh first."; exit 1; }

# json_get <key>: read a string value from $SECRETS_FILE (no jq needed).
json_get() {
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$SECRETS_FILE"
}

READ_ACCESS_KEY=$(json_get readAccessKey)
READ_SECRET_KEY=$(json_get readSecretKey)
[[ -n "$READ_ACCESS_KEY" && -n "$READ_SECRET_KEY" ]] || { echo "$SECRETS_FILE has no readAccessKey or readSecretKey."; exit 1; }

echo "==> Creating namespace inference"
kubectl create namespace inference --dry-run=client -o yaml | kubectl apply -f -

echo "==> Applying Secret inference/s3-models"
kubectl apply -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: s3-models
  namespace: inference
  annotations:
    serving.kserve.io/s3-endpoint: seaweedfs-all-in-one.storage.svc:8333
    serving.kserve.io/s3-usehttps: "0"
    serving.kserve.io/s3-verifyssl: "0"
    serving.kserve.io/s3-region: us-east-1
type: Opaque
stringData:
  AWS_ACCESS_KEY_ID: "$READ_ACCESS_KEY"
  AWS_SECRET_ACCESS_KEY: "$READ_SECRET_KEY"
YAML

kubectl -n inference get secret s3-models
