# LeaderWorkerSet

LeaderWorkerSet runs a group of pods as one unit, with one leader and several workers. If one model is too large for the GPUs of one node, vLLM runs on several nodes. KServe then uses LeaderWorkerSet. The lab model does not use it.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/management/kserve/lws.yaml` |
| Chart | `lws` v0.8.0 from registry.k8s.io/lws/charts (OCI) |
| Namespace | lws-system |
| Sync wave | 1 in the KServe group |
| Node | inference-lab-worker (pool=management) |

## Configuration

`enableCertManager: true` lets cert-manager issue the webhook certificate.

## Make sure that it works

```bash
kubectl -n lws-system get pods
```
