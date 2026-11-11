# Management stack

The management stack holds the shared services of the platform. It installs KEDA, KServe with its gateway, and LiteLLM with its database. All its pods run on the management node `inference-lab-worker`.

The stack Application is `argocd/stacks/management.yaml`. It has sync wave 1, so it starts after the storage and monitoring stacks are Healthy.

A group is a folder of Applications that belong together. A group Application next to the folder syncs it. The Argo CD UI then shows the apps of the group under one app.

The stack syncs its apps and groups in this order:

| Sync wave | App or group | What it does | README |
| --- | --- | --- | --- |
| 0 | keda | Shared autoscaler. KServe uses it to scale vLLM. | [helm/management/keda](../../../helm/management/keda/README.md) |
| 1 | kserve (group) | KServe for LLMInferenceService, the Envoy gateway and llm-d | [kserve](kserve/README.md) |
| 2 | litellm-group (group) | LiteLLM proxy with its PostgreSQL database | [litellm](litellm/README.md) |

KEDA comes first. When the KServe controller starts, it looks for the KEDA CRDs, and it watches KEDA objects only if they exist. LiteLLM comes last, because it sends requests to the KServe gateway.

To make sure that the stack works, run:

```bash
kubectl -n argocd get application management keda kserve litellm-group
```
