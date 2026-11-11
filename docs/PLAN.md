# Argo CD platform plan

This file lists the Argo CD Applications for each stack. A stack is a group of apps that Argo CD syncs together. All four stack Applications exist. All four stacks have apps now.

## Layout

The root Application syncs one Application for each stack. Each stack Application syncs the Application files in its own folder, not in subfolders. A group folder, such as `management/kserve`, holds apps that belong together. A group Application next to the folder, for example `argocd/apps/management/kserve.yaml`, syncs the folder. The Argo CD UI then shows the apps of the group under one app. The Helm values for each app are in `helm/`. `helm/README.md` tells you how to add an app.

```
argocd/root.yaml                    root app, path argocd/stacks
argocd/stacks/<stack>.yaml          stack app, path argocd/apps/<stack>
argocd/apps/<stack>/<group>.yaml              group app, path argocd/apps/<stack>/<group>
argocd/apps/<stack>/[<group>/]<app>.yaml      one Helm chart per file
helm/<stack>/[<group>/]<app>/values.yaml      Helm values, read through the $values ref
helm/<stack>/[<group>/]<app>/Chart.yaml       only for charts kept in this repository
```

## Sync waves

A sync wave is a number on an Application. Argo CD syncs lower numbers first. The health check in `patches/argocd-app-health.yaml` makes Argo CD wait until a wave is Healthy before it starts the next wave.

| Stack | Stack sync wave | Status |
| --- | --- | --- |
| storage | 0 | Created: seaweedfs |
| monitoring | 0 | Created: kube-prometheus-stack |
| management | 1 | Created: KServe group (cert-manager, LeaderWorkerSet, Envoy Gateway, Envoy AI Gateway, KServe LLMInferenceService), Portkey |
| inference | 2 | Created: vllm |

The sync wave of an app applies only inside its stack. For example, kserve-llmisvc-resources has wave 2 in the management stack. It starts after the other management apps, not at the same time as the inference stack.

## Rules for every app

- Pin the chart version. Do not use `latest` or a version range.
- Put the Helm values in `helm/<stack>/<app>/values.yaml`. If the Application is in a group folder, use the same group folder: `helm/<stack>/<group>/<app>/values.yaml`.
- For a chart from a chart repository with a values file, use two sources: the chart, and this repository with `ref: values`. A chart without a values file, for example a CRD chart, uses one source. For a chart in this repository, use one source with `path`.
- For a Helm chart in an OCI registry, set `repoURL` without the `oci://` prefix. The registry needs a repository Secret with `enableOCI: "true"` in `argocd/apps/management/kserve/repositories.yaml`.
- Set `syncPolicy.automated` with `prune: true` and `selfHeal: true`.
- Set `retry` with limit 10, backoff 30s, factor 2, max 5m.
- Set `syncOptions` to `CreateNamespace=true` and `ServerSideApply=true`.
- If the chart has admission webhooks or CRD conversion webhooks, add `ignoreDifferences` for their `caBundle` and the sync option `RespectIgnoreDifferences=true`. cert-manager writes the `caBundle` after the sync. Without this, Argo CD reports drift and self-heal removes the value.

Node placement:

- Most apps run on the management node with `nodeSelector: pool: management`.
- Storage apps run on `pool: storage` with a toleration for `workload=storage:NoSchedule`.
- Inference apps run on `pool: inference` with a toleration for `workload=inference:NoSchedule`.

## Storage stack (created)

| App | Chart repository | Chart | Version | Namespace | Sync wave | Key values |
| --- | --- | --- | --- | --- | --- | --- |
| seaweedfs | https://seaweedfs.github.io/seaweedfs/helm | seaweedfs | 4.53.0 | storage | 0 | allInOne only, S3 with auth, bucket `models`, NodePort 30333, hostPath `/data` on pool=storage, credentials from Secret `seaweedfs-s3-creds` |

The Application is `argocd/apps/storage/seaweedfs.yaml`. The values are in `helm/storage/seaweedfs/values.yaml`. `scripts/argocd-deployment.sh` creates the Secret `storage/seaweedfs-s3-creds` from `.lab-secrets.json`. The Secret is not in Git.

## Monitoring stack (created)

| App | Chart repository | Chart | Version | Namespace | Sync wave | Key values |
| --- | --- | --- | --- | --- | --- | --- |
| kube-prometheus-stack | https://prometheus-community.github.io/helm-charts | kube-prometheus-stack | 93.1.2 | monitoring | 0 | See the list below |

Values for kube-prometheus-stack:

- `alertmanager.enabled: false`
- `kubeEtcd`, `kubeControllerManager`, `kubeScheduler`, `kubeProxy`: `enabled: false`
- Prometheus: service type NodePort, node port 30090, `retention: 2d`
- Prometheus: `ruleSelectorNilUsesHelmValues`, `serviceMonitorSelectorNilUsesHelmValues`, `podMonitorSelectorNilUsesHelmValues`, `probeSelectorNilUsesHelmValues`, `scrapeConfigSelectorNilUsesHelmValues` all `false`
- Grafana: service type NodePort, node port 30030
- Prometheus, Grafana, the operator and kube-state-metrics: `nodeSelector: pool: management`
- node-exporter: `nodeSelector: pool: management` and `tolerations: []`

With the selector values set to `false`, Prometheus reads ServiceMonitors and PodMonitors from all Helm releases, not only from its own release. The vLLM metrics need this.

The node-exporter chart default tolerates all taints. The empty list keeps node-exporter off the tainted nodes. Then Prometheus gets node metrics only from the management node.

The Application is `argocd/apps/monitoring/kube-prometheus-stack.yaml`. The values are in `helm/monitoring/kube-prometheus-stack/values.yaml`.

The Grafana chart generates a random admin password with Helm `lookup`. Argo CD cannot run `lookup`, so the password changes on every sync. To prevent this, Grafana reads its password from the Secret `monitoring/grafana-admin`. `scripts/argocd-deployment.sh` creates that Secret from the value `grafanaAdminPassword` in `.lab-secrets.json`. The Secret is not in Git.

Later: Langfuse on node port 30300.

## Management stack (created)

The management stack installs KServe for LLMInferenceService and everything that it needs. All these apps are in the group `kserve`: the Applications in `argocd/apps/management/kserve/` and the values in `helm/management/kserve/`. The group Application `argocd/apps/management/kserve.yaml` syncs them. The sync waves in the table apply inside that group. It does not install the KServe InferenceService controller (`kserve-crd` and `kserve-resources`). The versions come from `kserve-deps.env` in KServe v0.21.0, except Envoy Gateway, which uses the newest v1.8 patch release.

| App | Chart repository | Chart | Version | Namespace | Sync wave | Key values |
| --- | --- | --- | --- | --- | --- | --- |
| repositories | Not a chart | Secrets | Not applicable | argocd | -1 | OCI repository Secrets for docker.io/envoyproxy, ghcr.io/kserve/charts, registry.k8s.io/lws/charts |
| cert-manager | https://charts.jetstack.io | cert-manager | v1.21.3 | cert-manager | 0 | `crds.enabled: true` |
| lws | registry.k8s.io/lws/charts | lws | v0.8.0 | lws-system | 1 | `enableCertManager: true` |
| envoy-gateway | docker.io/envoyproxy | gateway-helm | v1.8.6 | envoy-gateway-system | 1 | Extension manager for Envoy AI Gateway, InferencePool backends |
| envoy-ai-gateway-crds | docker.io/envoyproxy | ai-gateway-crds-helm | v1.1.0 | envoy-ai-gateway-system | 1 | No values |
| kserve-llmisvc-crd | ghcr.io/kserve/charts | kserve-llmisvc-crd | v0.21.0 | kserve | 1 | No values |
| envoy-ai-gateway | docker.io/envoyproxy | ai-gateway-helm | v1.1.0 | envoy-ai-gateway-system | 2 | Webhook certificate from cert-manager |
| kserve-llmisvc-resources | ghcr.io/kserve/charts | kserve-llmisvc-resources | v0.21.0 | kserve | 2 | S3 endpoint `seaweedfs-all-in-one.storage.svc:8333`, HTTP |
| kserve-runtime-configs | ghcr.io/kserve/charts | kserve-runtime-configs | v0.21.0 | kserve | 3 | `llmisvcConfigs.enabled: true`, `servingruntime.enabled: false` |
| kserve-gateway | This repository | helm/management/kserve/kserve-gateway | 0.1.0 | kserve | 3 | GatewayClass `envoy`, Gateway `kserve/kserve-ingress-gateway`, NodePort 30081 |

All pods of these apps run on `pool: management`.

The waves follow the dependencies:

- cert-manager comes first, because LeaderWorkerSet, Envoy AI Gateway and KServe get their webhook certificates from it.
- The CRD charts and Envoy Gateway come in wave 1. The Envoy Gateway chart also installs the Gateway API v1.5.1 CRDs, so Gateway API has no Application of its own.
- The controllers come in wave 2. `kserve-llmisvc-resources` also installs the InferencePool and llm-d CRDs (`inferencepools.inference.networking.k8s.io`, `inferenceobjectives.llm-d.ai` and two others).
- The LLMInferenceServiceConfig presets and the Gateway come in wave 3. The presets need the KServe webhook to be ready.

Envoy AI Gateway runs as an extension server of Envoy Gateway. It lets an HTTPRoute send traffic to an InferencePool, which is how llm-d routes each request to the best vLLM replica.

The local chart `helm/management/kserve/kserve-gateway` creates three resources:

- An EnvoyProxy in `envoy-gateway-system`. It runs the Envoy proxy pods on the management node and exposes the gateway on NodePort 30081. kind maps host port 8081 to that port.
- The GatewayClass `envoy`, which uses that EnvoyProxy.
- The Gateway `kserve/kserve-ingress-gateway`. LLMInferenceService uses this Gateway by default.

The presets in `kserve-runtime-configs` use the image `ghcr.io/llm-d/llm-d-cuda`, which needs a GPU. For the CPU lab, the LLMInferenceService must set a CPU image. The presets already refer to `docker.io/vllm/vllm-openai-cpu:v0.23.0`.

## Portkey (created)

| App | Chart repository | Chart | Version | Namespace | Sync wave | Key values |
| --- | --- | --- | --- | --- | --- | --- |
| portkey | This repository | helm/management/portkey | 0.1.0, image `portkeyai/gateway:1.15.2` | portkey | 1 in the management stack | NodePort 30080, pool=management |

Portkey is an AI gateway. It gives clients one OpenAI-compatible API and adds retries, fallbacks and routing between providers. This setup uses the open-source gateway, because the open-source image is public. The Application is `argocd/apps/management/portkey.yaml`. It has sync wave 1, so it starts after the `kserve` group (wave 0) is Healthy.

On the Windows host, Portkey is at `http://localhost:8080`. kind maps that port to NodePort 30080. Inside the cluster, Portkey is at `http://portkey-gateway.portkey.svc:8787`.

Portkey sends a request to the upstream that the client names in two headers. For a model behind KServe, the client sends these headers:

```
x-portkey-provider: openai
x-portkey-custom-host: http://kserve-ingress-gateway.envoy-gateway-system.svc.cluster.local/inference/smollm2/v1
```

`kserve-ingress-gateway.envoy-gateway-system.svc` is the Envoy proxy Service of the KServe gateway. The EnvoyProxy in `helm/management/kserve/kserve-gateway` gives it this fixed name. `/inference/smollm2` is the route path of the vLLM model (`/<namespace>/<name>`).

### Analytics with ClickHouse (not ready)

The open-source gateway has no analytics store. Request logs and analytics in ClickHouse need the Portkey enterprise gateway. These facts come from the official chart `gateway` 1.7.8 in https://github.com/Portkey-AI/helm (`charts/portkey-gateway`):

- The images `docker.io/portkeyai/gateway_enterprise` and `docker.io/portkeyai/data-service` are private. You need Docker credentials from Portkey.
- The gateway needs `PORTKEY_CLIENT_AUTH`, a key from Portkey.
- ClickHouse is set with the environment values `ANALYTICS_STORE: clickhouse`, `ANALYTICS_STORE_ENDPOINT`, `ANALYTICS_STORE_USER`, `ANALYTICS_STORE_PASSWORD`, `ANALYTICS_LOG_TABLE` and `ANALYTICS_FEEDBACK_TABLE`.

The repository https://github.com/Portkey-AI/helm-chart is deprecated. Its README points to `Portkey-AI/helm`.

To move to ClickHouse analytics later, do these steps:

1. Get the enterprise license, the Docker credentials and `PORTKEY_CLIENT_AUTH` from Portkey.
2. Deploy ClickHouse as an Argo CD app, for example in a new `analytics` group.
3. Create a Secret outside Git with the Docker credentials, `PORTKEY_CLIENT_AUTH` and the ClickHouse password, in the same way as `storage/seaweedfs-s3-creds`.
4. Replace the local chart in `argocd/apps/management/portkey.yaml` with the official chart from https://portkey-ai.github.io/helm, chart `gateway`, with a pinned version.
5. Put the ClickHouse values in `helm/management/portkey/values.yaml`.

Later: KEDA 2.21.0 for autoscaling, Guardrails AI on node port 30082.

## Inference stack (created)

| App | Chart repository | Chart | Version | Namespace | Sync wave | Key values |
| --- | --- | --- | --- | --- | --- | --- |
| vllm | This repository | helm/inference/vllm | 0.1.0 | inference | 0 in the inference stack | LLMInferenceService `smollm2`, 1 replica, vLLM CPU image |

The Application is `argocd/apps/inference/vllm.yaml`. The chart `helm/inference/vllm` renders three objects:

- The LLMInferenceService `inference/smollm2` (`serving.kserve.io/v1alpha2`).
- The ServiceAccount `inference/kserve-s3`, which lists the Secret `s3-models`.
- The PodMonitor `inference/smollm2-vllm`. Prometheus scrapes `/metrics` on port 8000 of each vLLM pod every 15 seconds. KEDA reads these metrics from Prometheus.

The LLMInferenceService has these settings:

- Model URI `s3://models/smollm2-135m-instruct`. The KServe storage-initializer downloads it before vLLM starts.
- Served model name `smollm2-135m-instruct`. Clients send this name in the `model` field.
- One replica on one inference node, with `nodeSelector: pool: inference` and a toleration for `workload=inference:NoSchedule`.
- Image `docker.io/vllm/vllm-openai-cpu:v0.23.0`, pinned by digest. This is the CPU image that the KServe v0.21.0 presets use.
- `VLLM_CPU_KVCACHE_SPACE` 1 GiB. Resources: request 1 CPU and 4Gi, limit 2 CPU and 8Gi.
- Router: the default llm-d scheduler, and an HTTPRoute on the Gateway `kserve/kserve-ingress-gateway`.

The container `main` is merged with the preset `kserve-config-llm-template`. The preset supplies the `vllm serve /mnt/models` command, port 8000 and the probes. The chart replaces only the image, the security context, the environment, the resources and the liveness probe. The CPU image runs as root, so the chart sets `runAsNonRoot: false`.

The Secret `inference/s3-models` holds the read keys from `.lab-secrets.json` and these KServe annotations. `scripts/argocd-deployment.sh` creates it. To create only this Secret, run `scripts/create-s3-models-secret.sh` in Git Bash. The Secret is not in Git.

```yaml
metadata:
  annotations:
    serving.kserve.io/s3-endpoint: seaweedfs-all-in-one.storage.svc:8333
    serving.kserve.io/s3-usehttps: "0"
    serving.kserve.io/s3-verifyssl: "0"
    serving.kserve.io/s3-region: us-east-1
stringData:
  AWS_ACCESS_KEY_ID: <readAccessKey>
  AWS_SECRET_ACCESS_KEY: <readSecretKey>
```

`patches/argocd-app-health.yaml` adds a health check for LLMInferenceService. The vllm app is Healthy only when the `Ready` condition is `True`.

The gateway serves the model at `/<namespace>/<name>/v1/...`. For this model, the paths are:

- `http://localhost:8081/inference/smollm2/v1/chat/completions` from the Windows host.
- `http://kserve-ingress-gateway.envoy-gateway-system.svc.cluster.local/inference/smollm2/v1/chat/completions` inside the cluster.

The storage-initializer downloads every object under the model prefix. The bucket also holds `.cache/` and `onnx/` under that prefix, about 1.7 GB that vLLM does not use. Delete them to make the download faster (see "Upload the model").

Later: KEDA autoscaling on `sum(vllm:num_requests_waiting)` with 1 to 2 replicas, and pod anti-affinity on `kubernetes.io/hostname` so that the replicas run on worker2 and worker3.

## Make sure that each stack works

Run these commands in Git Bash after `scripts/argocd-deployment.sh` finishes.

Root and stacks:

```bash
kubectl -n argocd get applications
```

All Applications must show `Synced` and `Healthy`. If a stack stays `Progressing`, open http://localhost:8085 and read the status of its child apps.

Storage:

```bash
kubectl -n storage get pods -o wide        # pod on inference-lab-worker4
kubectl -n storage get svc                 # 8333:30333/TCP
```

Monitoring:

```bash
kubectl -n monitoring get pods -o wide     # all pods on inference-lab-worker
```

Open http://localhost:9090 for Prometheus and http://localhost:3000 for Grafana.

Management:

```bash
kubectl -n cert-manager get pods
kubectl -n keda get pods
kubectl -n kserve get pods
kubectl get crd inferenceservices.serving.kserve.io
```

Inference:

```bash
kubectl -n inference get inferenceservice
kubectl -n inference get pods -o wide      # replicas on worker2 and worker3
kubectl -n inference get scaledobject
```

## Upload the model

You need the AWS CLI on the Windows host. The storage stack must be Healthy. The model files must be in `models/smollm2-135m-instruct`.

Run these commands in Git Bash from the repository root:

```bash
json_get() { sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" .lab-secrets.json; }
export AWS_ACCESS_KEY_ID=$(json_get adminAccessKey)
export AWS_SECRET_ACCESS_KEY=$(json_get adminSecretKey)
export AWS_DEFAULT_REGION=us-east-1
aws --endpoint-url http://localhost:8333 s3 ls
aws --endpoint-url http://localhost:8333 s3 sync models/smollm2-135m-instruct s3://models/smollm2-135m-instruct
aws --endpoint-url http://localhost:8333 s3 ls s3://models/smollm2-135m-instruct/
```

The first `aws` command must list the bucket `models`. The commands use the admin keys because the read identity can list and read, but it cannot upload.
