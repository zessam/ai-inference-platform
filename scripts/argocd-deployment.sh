#!/usr/bin/env bash
# Installs Argo CD on the kind cluster, applies the patches, labels the nodes,
# creates the SeaweedFS S3 and Grafana credentials, applies the root app-of-apps, and
# prints the admin password.
# Run from any directory. Works in Git Bash on Windows.
# Safe to run again on the same cluster.
set -euo pipefail

cd "$(dirname "$0")/.."   # repo root

NAMESPACE="argocd"
CONTEXT="kind-inference-lab"
INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
PATCH_DIR="patches"
SECRETS_FILE=".lab-secrets.json"
ROOT_APP="argocd/root.yaml"

# node name -> role label (node-role.kubernetes.io/<role>="")
NODE_ROLES=(
  "inference-lab-worker:management"
  "inference-lab-worker2:inference"
  "inference-lab-worker3:inference"
  "inference-lab-worker4:storage"
)

# gen <charset> <length>: random string from /dev/urandom.
gen() {
  local out
  out=$(LC_ALL=C tr -dc "$1" </dev/urandom 2>/dev/null | head -c "$2" || true)
  [[ ${#out} -eq $2 ]] || { echo "Key generation failed"; exit 1; }
  printf '%s' "$out"
}

# json_get <key>: read a string value from $SECRETS_FILE (no jq needed).
json_get() {
  [[ -f "$SECRETS_FILE" ]] || return 0
  sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$SECRETS_FILE"
}

# --- Preconditions -----------------------------------------------------------
for f in "$PATCH_DIR/argocd-insecure.yaml" "$PATCH_DIR/argocd-nodeport.yaml" \
         "$PATCH_DIR/argocd-nodeselector.yaml" "$PATCH_DIR/argocd-app-health.yaml" \
         "$ROOT_APP"; do
  [[ -f "$f" ]] || { echo "Missing $f"; exit 1; }
done
if grep -qF '<user>' "$ROOT_APP"; then
  echo "$ROOT_APP still contains <user>. Set the GitHub user in repoURL first."
  exit 1
fi

kubectl config use-context "$CONTEXT" >/dev/null

# --- Node role labels --------------------------------------------------------
echo "==> Labeling node roles"
for entry in "${NODE_ROLES[@]}"; do
  node="${entry%%:*}"; role="${entry##*:}"
  kubectl label node "$node" "node-role.kubernetes.io/$role=" --overwrite
done

# --- Argo CD install ---------------------------------------------------------
echo "==> Creating namespace $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Argo CD"
kubectl apply -n "$NAMESPACE" --server-side -f "$INSTALL_URL"

echo "==> Waiting for argocd-server"
kubectl -n "$NAMESPACE" rollout status deployment argocd-server --timeout=300s

# --- Patches -----------------------------------------------------------------
echo "==> Applying patches"
kubectl -n "$NAMESPACE" patch configmap argocd-cmd-params-cm --type merge \
  --patch-file "$PATCH_DIR/argocd-insecure.yaml"
kubectl -n "$NAMESPACE" patch svc argocd-server \
  --patch-file "$PATCH_DIR/argocd-nodeport.yaml"
kubectl -n "$NAMESPACE" patch configmap argocd-cm --type merge \
  --patch-file "$PATCH_DIR/argocd-app-health.yaml"

echo "==> Pinning Argo CD workloads to pool=management"
WORKLOADS=$(kubectl -n "$NAMESPACE" get deployment,statefulset -o name)
for w in $WORKLOADS; do
  kubectl -n "$NAMESPACE" patch "$w" --patch-file "$PATCH_DIR/argocd-nodeselector.yaml"
done

echo "==> Restarting argocd-server"
kubectl -n "$NAMESPACE" rollout restart deployment argocd-server

echo "==> Waiting for Argo CD workloads"
for w in $WORKLOADS; do
  kubectl -n "$NAMESPACE" rollout status "$w" --timeout=300s
done

echo "==> Waiting for the initial admin secret"
for _ in $(seq 1 30); do
  kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret >/dev/null 2>&1 && break
  sleep 2
done

PASSWORD=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \
  -o go-template='{{.data.password | base64decode}}' 2>/dev/null \
  || echo "(secret not found; the admin password was probably changed)")

# --- Lab credentials ---------------------------------------------------------
# Generated once and kept in .lab-secrets.json (git-ignored), so they stay the
# same across cluster rebuilds and Argo CD syncs. A value missing from an
# existing file is generated and added. Existing values are kept.
[[ -f "$SECRETS_FILE" ]] && echo "==> Reusing credentials from $SECRETS_FILE"
ADMIN_ACCESS_KEY=$(json_get adminAccessKey)
ADMIN_SECRET_KEY=$(json_get adminSecretKey)
READ_ACCESS_KEY=$(json_get readAccessKey)
READ_SECRET_KEY=$(json_get readSecretKey)
GRAFANA_ADMIN_PASSWORD=$(json_get grafanaAdminPassword)
[[ -n "$ADMIN_ACCESS_KEY" ]] || ADMIN_ACCESS_KEY=$(gen 'A-Z0-9' 20)
[[ -n "$ADMIN_SECRET_KEY" ]] || ADMIN_SECRET_KEY=$(gen 'A-Za-z0-9' 40)
[[ -n "$READ_ACCESS_KEY" ]] || READ_ACCESS_KEY=$(gen 'A-Z0-9' 20)
[[ -n "$READ_SECRET_KEY" ]] || READ_SECRET_KEY=$(gen 'A-Za-z0-9' 40)
[[ -n "$GRAFANA_ADMIN_PASSWORD" ]] || GRAFANA_ADMIN_PASSWORD=$(gen 'A-Za-z0-9' 24)
( umask 077
  cat > "$SECRETS_FILE" <<EOF
{
  "adminAccessKey": "$ADMIN_ACCESS_KEY",
  "adminSecretKey": "$ADMIN_SECRET_KEY",
  "readAccessKey": "$READ_ACCESS_KEY",
  "readSecretKey": "$READ_SECRET_KEY",
  "grafanaAdminPassword": "$GRAFANA_ADMIN_PASSWORD"
}
EOF
)

echo "==> Creating namespace storage and Secret storage/seaweedfs-s3-creds"
kubectl create namespace storage --dry-run=client -o yaml | kubectl apply -f -
kubectl -n storage create secret generic seaweedfs-s3-creds \
  --from-literal=admin_access_key_id="$ADMIN_ACCESS_KEY" \
  --from-literal=admin_secret_access_key="$ADMIN_SECRET_KEY" \
  --from-literal=read_access_key_id="$READ_ACCESS_KEY" \
  --from-literal=read_secret_access_key="$READ_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating namespace monitoring and Secret monitoring/grafana-admin"
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl -n monitoring create secret generic grafana-admin \
  --from-literal=admin-user=admin \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "==> Creating namespace inference and Secret inference/s3-models"
# Read keys for the vLLM model download. ServiceAccount inference/kserve-s3
# (helm/inference/vllm) lists this Secret. The KServe storage-initializer reads
# the keys and the annotations.
kubectl create namespace inference --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f - <<EOF
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
EOF

# --- App of apps -------------------------------------------------------------
echo "==> Applying $ROOT_APP"
kubectl apply -f "$ROOT_APP"

echo
echo "Argo CD UI:  http://localhost:8085"
echo "Username:    admin"
echo "Password:    $PASSWORD"
echo
echo "S3 endpoint: http://localhost:8333"
echo "S3 keys:     $SECRETS_FILE (admin and read identities)"
echo
echo "Grafana:     http://localhost:3000 (admin, password in $SECRETS_FILE)"
echo "Prometheus:  http://localhost:9090"
