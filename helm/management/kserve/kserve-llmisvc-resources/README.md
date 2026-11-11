# KServe LLMInferenceService controller

This app runs the KServe controller for LLMInferenceService. The controller turns each LLMInferenceService into vLLM pods, a model download, an InferencePool, an llm-d scheduler, an HTTPRoute and, with autoscaling, a KEDA ScaledObject.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/management/kserve/kserve-llmisvc-resources.yaml` |
| Chart | `kserve-llmisvc-resources` v0.21.0 from ghcr.io/kserve/charts (OCI) |
| CRDs | `kserve-llmisvc-crd`, chart `kserve-llmisvc-crd` v0.21.0 |
| Namespace | kserve |
| Sync wave | 2 in the KServe group |
| Node | inference-lab-worker (pool=management) |

## Configuration

The chart also installs the InferencePool and llm-d CRDs (`kserve.llmisvc.createGIECRDs`).

`kserve.storage.s3` sets the default S3 endpoint for model downloads: `seaweedfs-all-in-one.storage.svc:8333` over plain HTTP. The S3 keys come from a Secret in the namespace of the model.

The KServe InferenceService controller (`kserve-crd`, `kserve-resources`) is not installed. This platform uses only LLMInferenceService.

## Make sure that it works

```bash
kubectl -n kserve get pods
kubectl get crd | grep -E "llminferenceservice|inferencepool"
```
