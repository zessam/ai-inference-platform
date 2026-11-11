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
| monitoring | 0 | Created: kube-prometheus-stack, grafana-dashboards |
| management | 1 | Created: KEDA, KServe group (cert-manager, LeaderWorkerSet, Envoy Gateway, Envoy AI Gateway, KServe LLMInferenceService), LiteLLM group (CloudNativePG, PostgreSQL, LiteLLM) |
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

### Grafana dashboards

The app `grafana-dashboards` (`argocd/apps/monitoring/grafana-dashboards.yaml`, sync wave 1) adds dashboards to Grafana. Its local chart `helm/monitoring/grafana-dashboards` turns each JSON file in `dashboards/<folder>/` into a ConfigMap with the label `grafana_dashboard: "1"`. The Grafana sidecar loads these ConfigMaps from all namespaces. The annotation `grafana_folder` sets the Grafana folder. For this, `helm/monitoring/kube-prometheus-stack/values.yaml` sets `grafana.sidecar.dashboards.folderAnnotation` and `foldersFromFilesStructure`.

The folder "vLLM" holds the official vLLM dashboards from the vLLM repository, tag v0.23.0:

| File | Title | Source in the vLLM repository |
| --- | --- | --- |
| vllm.json | vLLM | examples/observability/prometheus_grafana/grafana.json |
| vllm-performance-statistics.json | Performance Statistics | examples/observability/dashboards/grafana/performance_statistics.json |
| vllm-query-statistics.json | Query Statistics_New4 | examples/observability/dashboards/grafana/query_statistics.json |

The only change to the files is that the saved variable selections (data source uid and model names) are cleared. Grafana then selects the default Prometheus and the first model.

To add a dashboard, put its JSON file in `helm/monitoring/grafana-dashboards/dashboards/<folder>/`. For a new folder, also add it under `folders` in the values.

Later: Langfuse on node port 30300.

## Management stack (created)

The management stack syncs its apps in this order:

| Sync wave | App or group | Content |
| --- | --- | --- |
| 0 | keda | KEDA 2.21.0, shared autoscaler |
| 1 | kserve (group) | KServe LLMInferenceService and its dependencies |
| 2 | litellm-group (group) | LiteLLM with its PostgreSQL database |

KEDA is a shared cluster add-on, so it is not in the `kserve` group. Only one KEDA can run in a cluster, and other apps can also use it. The Application is `argocd/apps/management/keda.yaml`, and the values are in `helm/management/keda/values.yaml`. KServe does not install KEDA, but it manages the KEDA objects for each model (see "Autoscaling").

### KServe group

The `kserve` group installs KServe for LLMInferenceService and everything that it needs. All these apps are in the group `kserve`: the Applications in `argocd/apps/management/kserve/` and the values in `helm/management/kserve/`. The group Application `argocd/apps/management/kserve.yaml` syncs them. The sync waves in the table apply inside that group. It does not install the KServe InferenceService controller (`kserve-crd` and `kserve-resources`). The versions come from `kserve-deps.env` in KServe v0.21.0, except Envoy Gateway, which uses the newest v1.8 patch release.

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

## LiteLLM (created)

LiteLLM Proxy is the API entry point for clients. It gives one OpenAI-compatible API for the vLLM model and for external providers. It adds API keys, budgets and rate limits per user or team, retries and fallbacks, and a web UI with usage and spend. It replaces Portkey, because the open-source Portkey gateway has no UI and no analytics.

All LiteLLM apps are in the group `litellm`. The group Application `argocd/apps/management/litellm.yaml` (name `litellm-group`) syncs the folder `argocd/apps/management/litellm/`. It has sync wave 2, so it starts after the `kserve` group (wave 1) is Healthy.

| App | Chart repository | Chart | Version | Namespace | Sync wave | Key values |
| --- | --- | --- | --- | --- | --- | --- |
| repositories | Not a chart | Secret | Not applicable | argocd | -1 | OCI repository Secret for ghcr.io/berriai |
| cloudnative-pg | https://cloudnative-pg.github.io/charts | cloudnative-pg | 0.29.1 (operator 1.30.1) | cnpg-system | 0 | CloudNativePG operator for PostgreSQL |
| litellm-db | This repository | helm/management/litellm/litellm-db | 0.1.0 | litellm | 1 | CNPG Cluster `litellm-db`, PostgreSQL 17.9, 1 instance, 2Gi |
| litellm | ghcr.io/berriai (OCI) | litellm-helm | 1.106.7 | litellm | 2 | Model `smollm2-135m-instruct`, NodePort 30080 |

All pods run on `pool: management`.

LiteLLM needs PostgreSQL for keys, budgets, spend logs and the UI. CloudNativePG runs the database. It generates the database password inside the cluster and stores it in the Secret `litellm/litellm-db-app` (keys `username`, `password`, `host`). LiteLLM reads that Secret (`db.useExisting`). So the database password is never in Git. The bundled PostgreSQL of the LiteLLM chart is not used: its password would be in Git, and its `bitnamilegacy` images get no updates.

The Secret `litellm/litellm-secrets` holds `LITELLM_MASTER_KEY` and `LITELLM_SALT_KEY`. The master key is the admin key for the API and the UI. The salt key encrypts credentials that LiteLLM stores in the database. Do not change the salt key after the first start, because LiteLLM can then not read those credentials. `scripts/argocd-deployment.sh` or `scripts/create-litellm-secret.sh` creates the Secret from `.lab-secrets.json` (keys `litellmMasterKey` and `litellmSaltKey`). The Secret is not in Git. Without `masterkeySecretName`, the chart generates the master key with Helm `lookup`, and the key would change on every Argo CD sync.

LiteLLM sends requests for the model `smollm2-135m-instruct` to the KServe gateway, not to the vLLM Service. The provider is `hosted_vllm`, and `api_base` is `http://kserve-ingress-gateway.envoy-gateway-system.svc.cluster.local/inference/smollm2/v1`. So the llm-d scheduler still chooses the vLLM pod for each request. The path is: client, LiteLLM, Envoy gateway, llm-d scheduler, vLLM.

On the Windows host, LiteLLM is at `http://localhost:8080`, and the UI is at `http://localhost:8080/ui`. kind maps host port 8080 to NodePort 30080 of the Service `litellm-nodeport`. The user name for the UI is `admin`, and the password is the master key. Inside the cluster, LiteLLM is at `http://litellm.litellm.svc:4000`.

To send a request, use the master key or an API key that you created in the UI:

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Authorization: Bearer <key>" -H "Content-Type: application/json" \
  -d '{"model":"smollm2-135m-instruct","messages":[{"role":"user","content":"Hi"}]}'
```

### Analytics with ClickHouse (not ready)

LiteLLM stores spend logs in PostgreSQL. For analytics in ClickHouse, Langfuse is the planned option. Recent Langfuse versions store traces in ClickHouse, and LiteLLM can send each request to Langfuse with its `success_callback` setting. Langfuse also has a UI for traces, prompts, latency and costs.

Later: Langfuse with ClickHouse on node port 30300, Guardrails AI on node port 30082.

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
- `nodeSelector: pool: inference` and a toleration for `workload=inference:NoSchedule`.
- Required pod anti-affinity on `kubernetes.io/hostname`, so that each replica runs on a different inference node.
- Autoscaling from 1 to 2 replicas with KEDA (see below).
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

### Autoscaling

KServe manages the scaling, and KEDA does the work. You do not write a ScaledObject or an HPA. KEDA 2.21.0 is a separate app in wave 0 of the management stack, before the `kserve` group. The KServe controller watches ScaledObjects only if the KEDA CRDs exist when the controller starts. If the controller started before KEDA existed, restart it once: `kubectl -n kserve rollout restart deployment/llmisvc-controller-manager`.

The scaling chain has these steps:

1. `spec.scaling.keda` in the LLMInferenceService describes the trigger. The CRD does not accept `spec.replicas` and `spec.scaling` together.
2. The KServe controller creates a KEDA ScaledObject for the vLLM Deployment.
3. KEDA runs the Prometheus query every 15 seconds and creates an HPA.
4. The HPA sets the number of replicas of the vLLM Deployment.
5. A new vLLM pod joins the InferencePool, and the llm-d scheduler sends traffic to it.

The scaling metric is `vllm:num_requests_waiting`. It counts the requests that wait in the queue of each vLLM pod, because vLLM cannot start them yet. The query is `sum(vllm:num_requests_waiting{namespace="inference",model_name="smollm2-135m-instruct"})`. The PodMonitor `smollm2-vllm` makes Prometheus scrape it.

KEDA sets the replicas to the query result divided by the threshold 2, rounded up, from 1 to 2. For example, 3 waiting requests give 2 replicas. After the queue is empty, the HPA keeps the second replica for 300 seconds before it scales down.

The values are in `helm/inference/vllm/values.yaml` under `autoscaling`. `autoscaling.enabled: false` turns the scaling off and uses `replicas` instead.

In the lab, `maxNumSeqs: 4` limits vLLM to 4 requests at the same time (`--max-num-seqs 4`, through `VLLM_ADDITIONAL_ARGS`). Without the limit, vLLM on CPU accepts many requests at once, and the queue does not fill in a test. Remove the limit on GPU nodes.

Before the first scale-up, pull the vLLM image on worker3, so that the second pod does not wait for the download: `docker exec inference-lab-worker3 crictl pull <image of helm/inference/vllm/values.yaml>`.

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
