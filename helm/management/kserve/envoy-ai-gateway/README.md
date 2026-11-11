# Envoy AI Gateway

Envoy AI Gateway extends Envoy Gateway for AI traffic. In this platform, it adds one feature: an HTTPRoute can send traffic to an InferencePool. Envoy then asks the llm-d scheduler which vLLM pod to use.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/management/kserve/envoy-ai-gateway.yaml` |
| Chart | `ai-gateway-helm` v1.1.0 from docker.io/envoyproxy (OCI) |
| CRDs | `envoy-ai-gateway-crds`, chart `ai-gateway-crds-helm` v1.1.0 |
| Namespace | envoy-ai-gateway-system |
| Sync wave | 2 in the KServe group |
| Node | inference-lab-worker (pool=management) |

## Configuration

`controller.mutatingWebhook.certManager.enable: true` lets cert-manager issue the webhook certificate. Without it, the chart generates the certificate with Helm `lookup`, and the certificate changes on every Argo CD sync.

Envoy AI Gateway can also route to external providers and limit tokens. This platform does not use these features. LiteLLM does that work.

## Make sure that it works

```bash
kubectl -n envoy-ai-gateway-system get pods
```
