# cert-manager

cert-manager issues and renews TLS certificates in the cluster. KServe, LeaderWorkerSet and Envoy AI Gateway get the certificates for their webhooks from it. The Kubernetes API server calls webhooks only over HTTPS.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/management/kserve/cert-manager.yaml` |
| Chart | `cert-manager` v1.21.3 from https://charts.jetstack.io |
| Namespace | cert-manager |
| Sync wave | 0 in the KServe group |
| Node | inference-lab-worker (pool=management) |

## Configuration

The chart installs its CRDs (`crds.enabled: true`). `global.nodeSelector` puts all its pods on the management node.

## Make sure that it works

```bash
kubectl -n cert-manager get pods
kubectl get certificates -A
```
