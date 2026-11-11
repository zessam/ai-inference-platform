# vLLM model smollm2

This local chart deploys the vLLM model `smollm2-135m-instruct` as a KServe LLMInferenceService. KServe creates the vLLM pods, the model download, the llm-d scheduler, the route on the gateway and the autoscaling.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/inference/vllm.yaml` |
| Chart | local chart in this folder, version 0.1.0 |
| Namespace | inference |
| Sync wave | 0 in the inference stack |
| Nodes | inference-lab-worker2 and inference-lab-worker3 (pool=inference) |
| Model | `s3://models/smollm2-135m-instruct` in SeaweedFS |
| Image | `docker.io/vllm/vllm-openai-cpu:v0.23.0`, pinned by digest |
| URL | `http://localhost:8081/inference/smollm2/v1/chat/completions` |

## Resources

The chart renders three objects:

| Object | Name | What it does |
| --- | --- | --- |
| LLMInferenceService | `smollm2` | The model. KServe builds all other objects from it. |
| ServiceAccount | `kserve-s3` | Lists the Secret `s3-models`, which holds the S3 read keys for the model download. |
| PodMonitor | `smollm2-vllm` | Prometheus scrapes `/metrics` on port 8000 of each vLLM pod. |

The container `main` is merged with the KServe preset `kserve-config-llm-template`. The chart replaces only the image, the security context, the environment, the resources and the liveness probe.

The Secret `inference/s3-models` is not in Git. `scripts/create-s3-models-secret.sh` creates it from the read keys in `.lab-secrets.json`.

## Autoscaling

The values under `autoscaling` set the scaling. KServe turns them into a KEDA ScaledObject with this Prometheus trigger:

```
sum(vllm:num_requests_waiting{namespace="inference",model_name="smollm2-135m-instruct"})
```

The number of pods is the query result divided by the threshold 2, rounded up, from 1 to 2. After the queue is empty, the HPA keeps the second pod for 300 seconds.

These settings are for the lab:

- `maxNumSeqs: 4` limits vLLM to 4 requests at the same time, so that a few requests fill the queue. Remove it on GPU nodes.
- `antiAffinity: true` puts each pod on a different inference node. With 2 nodes and 2 pods, an update of the pod template waits until the model scales back to 1 pod.

In KServe v0.21.0, the field `scaling.keda.advanced.horizontalPodAutoscalerConfig` cannot be used, because of a bug in a CRD validation rule. The template explains it.

## Load test

Run `scripts/check-autoscaling.sh`, then `scripts/generate-load.sh` in Git Bash. The root README describes them.

## Make sure that it works

```bash
kubectl -n inference get llminferenceservice,pods -o wide
kubectl -n inference get scaledobject,hpa
```
