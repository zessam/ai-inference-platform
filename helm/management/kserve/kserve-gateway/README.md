# KServe gateway

This local chart creates the Gateway that LLMInferenceService uses by default. KServe expects this Gateway but does not create it.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/management/kserve/kserve-gateway.yaml` |
| Chart | local chart in this folder, version 0.1.0 |
| Namespace | kserve (Gateway), envoy-gateway-system (EnvoyProxy) |
| Sync wave | 3 in the KServe group |
| Address | `http://localhost:8081` on the host, `http://kserve-ingress-gateway.envoy-gateway-system.svc` in the cluster |

## Resources

The chart creates three resources:

| Resource | Name | What it does |
| --- | --- | --- |
| EnvoyProxy | `envoy-gateway-system/kserve-ingress` | Runs the Envoy proxy pods on the management node. Names their Service `kserve-ingress-gateway` and opens it on NodePort 30081. |
| GatewayClass | `envoy` | Connects the Gateway API to Envoy Gateway. |
| Gateway | `kserve/kserve-ingress-gateway` | Listens on port 80 for routes from all namespaces. |

The fixed Service name lets LiteLLM reach the gateway at a stable address. kind maps host port 8081 to NodePort 30081.

## Model URLs

KServe serves each model at `/<namespace>/<name>/v1/...`. For the model `inference/smollm2`, the chat URL is `http://localhost:8081/inference/smollm2/v1/chat/completions`.

## Make sure that it works

```bash
kubectl -n kserve get gateway kserve-ingress-gateway
kubectl -n envoy-gateway-system get svc kserve-ingress-gateway
```
