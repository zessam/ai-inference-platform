# Inference stack

The inference stack runs the models. It has one app, the vLLM model `smollm2`, which KServe deploys as an LLMInferenceService.

The stack Application is `argocd/stacks/inference.yaml`. It has sync wave 2, so it starts after the management stack, where KServe runs.

| App | What it does | Namespace | Sync wave | README |
| --- | --- | --- | --- | --- |
| vllm | vLLM model `smollm2-135m-instruct`, autoscaled from 1 to 2 pods | inference | 0 | [helm/inference/vllm](../../../helm/inference/vllm/README.md) |

The vLLM pods run only on the inference nodes `inference-lab-worker2` and `inference-lab-worker3`. A new model is a new app in this folder with its own chart or values in `helm/inference/`.

To make sure that the stack works, run:

```bash
kubectl -n argocd get application inference vllm
kubectl -n inference get llminferenceservice,pods -o wide
```
