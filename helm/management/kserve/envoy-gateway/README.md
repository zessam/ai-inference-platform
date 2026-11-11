# Envoy Gateway

Envoy Gateway implements the Kubernetes Gateway API. It runs the Envoy proxy that receives the requests for the models. KServe creates HTTPRoutes, and Envoy Gateway serves them.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/management/kserve/envoy-gateway.yaml` |
| Chart | `gateway-helm` v1.8.6 from docker.io/envoyproxy (OCI) |
| Namespace | envoy-gateway-system |
| Sync wave | 1 in the KServe group |
| Node | inference-lab-worker (pool=management) |

## Configuration

The chart also installs the Gateway API v1.5.1 CRDs, the version that KServe v0.21.0 needs.

The `config.envoyGateway` block combines the two values files that Envoy AI Gateway v1.1.0 requires. The extension manager calls the AI Gateway controller each time that Envoy Gateway builds a routing configuration. `backendResources` lets an HTTPRoute send traffic to an InferencePool.

The proxy pods, the Gateway and the GatewayClass come from the local chart `kserve-gateway`.

## Make sure that it works

```bash
kubectl -n envoy-gateway-system get pods,svc
```
