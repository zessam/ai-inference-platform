# KServe runtime configs

This app installs the LLMInferenceServiceConfig presets. A preset is a template for part of an LLMInferenceService: the vLLM container, the router or the scheduler. A model spec then names only what differs.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/management/kserve/kserve-runtime-configs.yaml` |
| Chart | `kserve-runtime-configs` v0.21.0 from ghcr.io/kserve/charts (OCI) |
| Namespace | kserve |
| Sync wave | 3 in the KServe group, after the controller |

## Configuration

`kserve.llmisvcConfigs.enabled: true` installs the presets. `kserve.servingruntime.enabled: false` skips the ClusterServingRuntimes, which only InferenceService uses.

The KServe webhook checks each preset. That is why this app comes after the controller.

The default vLLM template uses the GPU image `ghcr.io/llm-d/llm-d-cuda`. The vLLM chart in `helm/inference/vllm` replaces it with a CPU image.

## Make sure that it works

```bash
kubectl -n kserve get llminferenceserviceconfig
```
