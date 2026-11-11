# KEDA

KEDA is an event-driven autoscaler. It is a shared add-on for the whole cluster. KServe uses it to scale the vLLM pods on a Prometheus metric.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/management/keda.yaml` |
| Chart | `keda` 2.21.0 from https://kedacore.github.io/charts |
| Namespace | keda |
| Sync wave | 0 in the management stack, before the KServe group |
| Node | inference-lab-worker (pool=management) |

## How KServe uses KEDA

You do not write KEDA objects yourself. For each LLMInferenceService with `spec.scaling.keda`, the KServe controller creates and manages a KEDA ScaledObject. KEDA runs the trigger query against Prometheus and drives an HPA, which sets the number of vLLM pods.

When the KServe controller starts, it looks for the KEDA CRDs. If they exist, it watches ScaledObjects. That is why KEDA has an earlier wave than KServe. If KEDA is installed after KServe, restart the controller once: `kubectl -n kserve rollout restart deployment/llmisvc-controller-manager`.

## Certificates

KEDA generates its own certificates. It writes the CA bundle into its webhook and into the APIService `v1beta1.external.metrics.k8s.io`. The Application tells Argo CD to ignore these `caBundle` fields.

## Make sure that it works

```bash
kubectl -n keda get pods
kubectl get apiservice v1beta1.external.metrics.k8s.io
```
