# KServe group

The KServe group installs KServe for the resource LLMInferenceService and everything that it needs. An LLMInferenceService describes one model. KServe turns it into vLLM pods, an llm-d scheduler and a route on the gateway.

The group Application is `argocd/apps/management/kserve.yaml`. It has sync wave 1 in the management stack. Inside the group, the apps sync in this order:

| Sync wave | App | What it does | Namespace | README |
| --- | --- | --- | --- | --- |
| -1 | repositories | Argo CD repository Secrets for the OCI chart registries | argocd | this file |
| 0 | cert-manager | Certificates for the webhooks | cert-manager | [cert-manager](../../../../helm/management/kserve/cert-manager/README.md) |
| 1 | lws | LeaderWorkerSet, for models on several nodes | lws-system | [lws](../../../../helm/management/kserve/lws/README.md) |
| 1 | envoy-gateway | Gateway API implementation, entry point for traffic | envoy-gateway-system | [envoy-gateway](../../../../helm/management/kserve/envoy-gateway/README.md) |
| 1 | envoy-ai-gateway-crds | CRDs of Envoy AI Gateway | envoy-ai-gateway-system | this file |
| 1 | kserve-llmisvc-crd | CRDs of LLMInferenceService | kserve | this file |
| 2 | envoy-ai-gateway | Lets Envoy send traffic to an InferencePool | envoy-ai-gateway-system | [envoy-ai-gateway](../../../../helm/management/kserve/envoy-ai-gateway/README.md) |
| 2 | kserve-llmisvc-resources | KServe controller for LLMInferenceService | kserve | [kserve-llmisvc-resources](../../../../helm/management/kserve/kserve-llmisvc-resources/README.md) |
| 3 | kserve-runtime-configs | Templates (presets) for vLLM, router and scheduler | kserve | [kserve-runtime-configs](../../../../helm/management/kserve/kserve-runtime-configs/README.md) |
| 3 | kserve-gateway | The Gateway `kserve/kserve-ingress-gateway` | kserve | [kserve-gateway](../../../../helm/management/kserve/kserve-gateway/README.md) |

All pods of the group run on the management node.

## Apps without a values folder

Three apps have no folder in `helm/`, because they need no values:

- `repositories.yaml` holds three Secrets. They tell Argo CD that docker.io/envoyproxy, ghcr.io/kserve/charts and registry.k8s.io/lws/charts hold Helm charts in OCI format. The Secrets have no passwords, because the registries are public.
- `envoy-ai-gateway-crds.yaml` installs the CRDs of Envoy AI Gateway, chart `ai-gateway-crds-helm` v1.1.0.
- `kserve-llmisvc-crd.yaml` installs the CRDs LLMInferenceService and LLMInferenceServiceConfig, chart `kserve-llmisvc-crd` v0.21.0.

## Webhook certificates

cert-manager writes the CA bundle into the webhook configurations after each sync. So the Applications tell Argo CD to ignore the field `caBundle` (`ignoreDifferences` and `RespectIgnoreDifferences=true`). Without this, Argo CD reports drift, and self-heal removes the CA bundle.

[docs/KSERVE.md](../../../../docs/KSERVE.md) explains each component and the steps of a model deployment.

To make sure that the group works, run:

```bash
kubectl -n argocd get applications | grep -E "kserve|envoy|lws|cert-manager"
kubectl -n kserve get pods,gateway
```
