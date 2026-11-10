#!/usr/bin/env bash
# Installs Argo CD on the kind cluster, applies the insecure + NodePort patches,
# and prints the admin password.
# Run from the repo root (ai-inference-platform). Works in Git Bash on Windows.
set -euo pipefail

NAMESPACE="argocd"
CONTEXT="kind-inference-lab"
INSTALL_URL="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
PATCH_DIR="patches"

kubectl config use-context "$CONTEXT" >/dev/null

for f in "$PATCH_DIR/argocd-insecure.yaml" "$PATCH_DIR/argocd-nodeport.yaml"; do
  [[ -f "$f" ]] || { echo "Missing $f (run from the repo root)"; exit 1; }
done

echo "==> Creating namespace $NAMESPACE"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "==> Installing Argo CD"
kubectl apply -n "$NAMESPACE" --server-side -f "$INSTALL_URL"

echo "==> Waiting for argocd-server"
kubectl -n "$NAMESPACE" rollout status deployment argocd-server --timeout=300s

echo "==> Applying patches"
kubectl -n "$NAMESPACE" patch configmap argocd-cmd-params-cm --type merge \
  --patch-file "$PATCH_DIR/argocd-insecure.yaml"
kubectl -n "$NAMESPACE" patch svc argocd-server \
  --patch-file "$PATCH_DIR/argocd-nodeport.yaml"

echo "==> Restarting argocd-server"
kubectl -n "$NAMESPACE" rollout restart deployment argocd-server
kubectl -n "$NAMESPACE" rollout status deployment argocd-server --timeout=300s

echo "==> Waiting for the initial admin secret"
for _ in $(seq 1 30); do
  kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret >/dev/null 2>&1 && break
  sleep 2
done

PASSWORD=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \
  -o go-template='{{.data.password | base64decode}}')

echo
echo "Argo CD UI: http://localhost:8085"
echo "Username:   admin"
echo "Password:   $PASSWORD"