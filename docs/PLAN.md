# Argo CD platform plan

This file lists the Argo CD Applications for each stack. A stack is a group of apps that Argo CD syncs together. All four stack Applications exist. Only the storage stack has an app now. The folders of the other stacks contain only a `.gitkeep` file.

## Layout

The root Application syncs one Application for each stack. Each stack Application syncs the Application files in its own folder. The Helm values for each app are in `helm/`. `helm/README.md` tells you how to add an app.

```
argocd/root.yaml                    root app, path argocd/stacks
argocd/stacks/<stack>.yaml          stack app, path argocd/apps/<stack>
argocd/apps/<stack>/<app>.yaml      one Helm chart per file
helm/<stack>/<app>/values.yaml      Helm values, read through the $values ref
helm/<stack>/<app>/Chart.yaml       only for charts kept in this repository (vllm)
```

## Sync waves

A sync wave is a number on an Application. Argo CD syncs lower numbers first. The health check in `patches/argocd-app-health.yaml` makes Argo CD wait until a wave is Healthy before it starts the next wave.

| Stack | Stack sync wave | Status |
| --- | --- | --- |
| storage | 0 | Created: seaweedfs |
| monitoring | 0 | Planned |
| management | 1 | Planned |
| inference | 2 | Planned |

The sync wave of an app applies only inside its stack. For example, kserve-resources has wave 2 in the management stack. It starts after the other management apps, not at the same time as the inference stack.

## Rules for every app

- Pin the chart version. Do not use `latest` or a version range.
- Put the Helm values in `helm/<stack>/<app>/values.yaml`.
- For a chart from a chart repository, use two sources: the chart, and this repository with `ref: values`. For a chart in this repository, use one source with `path`.
- Set `syncPolicy.automated` with `prune: true` and `selfHeal: true`.
- Set `retry` with limit 10, backoff 30s, factor 2, max 5m.
- Set `syncOptions` to `CreateNamespace=true` and `ServerSideApply=true`.

Node placement:

- Most apps run on the management node with `nodeSelector: pool: management`.
- Storage apps run on `pool: storage` with a toleration for `workload=storage:NoSchedule`.
- Inference apps run on `pool: inference` with a toleration for `workload=inference:NoSchedule`.

## Storage stack (created)

| App | Chart repository | Chart | Version | Namespace | Sync wave | Key values |
| --- | --- | --- | --- | --- | --- | --- |
| seaweedfs | https://seaweedfs.github.io/seaweedfs/helm | seaweedfs | 4.53.0 | storage | 0 | allInOne only, S3 with auth, bucket `models`, NodePort 30333, hostPath `/data` on pool=storage, credentials from Secret `seaweedfs-s3-creds` |

The Application is `argocd/apps/storage/seaweedfs.yaml`. The values are in `helm/storage/seaweedfs/values.yaml`. `scripts/argocd-deployment.sh` creates the Secret `storage/seaweedfs-s3-creds` from `.lab-secrets.json`. The Secret is not in Git.

## Monitoring stack (planned)

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

Later: Langfuse on node port 30300.

## Management stack (planned)

| App | Chart repository | Chart | Version | Namespace | Sync wave | Key values |
| --- | --- | --- | --- | --- | --- | --- |
| cert-manager | https://charts.jetstack.io | cert-manager | v1.21.3 | cert-manager | 0 | `crds.enabled: true` |
| keda | https://kedacore.github.io/charts | keda | 2.21.0 | keda | 1 | Defaults, nodeSelector pool=management |
| kserve-crd | oci://ghcr.io/kserve/charts | kserve-crd | v0.21.0 | kserve | 1 | Defaults |
| kserve-resources | oci://ghcr.io/kserve/charts | kserve-resources | v0.21.0 | kserve | 2 | See the list below |

cert-manager has wave 0 because KServe uses it for the certificates of its webhook. kserve-crd has wave 1 so that the CRDs exist before kserve-resources syncs in wave 2.

Values for kserve-resources:

- `kserve.controller.deploymentMode: Standard`
- `kserve.controller.gateway.disableIngressCreation: true`
- `kserve.storage.s3.endpoint: seaweedfs-all-in-one.storage.svc:8333`
- `kserve.storage.s3.useHttps: "0"`

The KServe charts come from an OCI registry. Argo CD needs a repository Secret for that registry before it can sync them:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: repo-kserve-oci
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: helm
  name: kserve
  url: ghcr.io/kserve/charts
  enableOCI: "true"
```

In the Application, the OCI source uses `repoURL: ghcr.io/kserve/charts` without the `oci://` prefix.

Later: Envoy Gateway, llm-d, Guardrails AI on node port 30082, Portkey on node port 30080.

## Inference stack (planned)

| App | Chart repository | Chart | Version | Namespace | Sync wave | Key values |
| --- | --- | --- | --- | --- | --- | --- |
| vllm | This repository | helm/inference/vllm | Pinned in Chart.yaml | inference | Stack wave 2 | KServe InferenceService, see the list below |

The chart `helm/inference/vllm` does not exist yet. It will render a KServe InferenceService with these settings:

- Deployment mode Standard, with the annotation `serving.kserve.io/deploymentMode: Standard`.
- Autoscaler class `keda` on the metric `sum(vllm:num_requests_waiting)` from Prometheus. Minimum 1 replica, maximum 2 replicas.
- Pod anti-affinity on `kubernetes.io/hostname`, so that the two replicas run on worker2 and worker3.
- `nodeSelector: pool: inference` and a toleration for `workload=inference:NoSchedule`.
- `storageUri: s3://models/smollm2-135m-instruct`.
- `serviceAccountName: kserve-s3`.

The ServiceAccount `inference/kserve-s3` refers to the Secret `inference/s3-models`. That Secret holds the read keys from `.lab-secrets.json` and these KServe annotations:

```yaml
metadata:
  annotations:
    serving.kserve.io/s3-endpoint: seaweedfs-all-in-one.storage.svc:8333
    serving.kserve.io/s3-usehttps: "0"
    serving.kserve.io/s3-region: us-east-1
stringData:
  AWS_ACCESS_KEY_ID: <readAccessKey>
  AWS_SECRET_ACCESS_KEY: <readSecretKey>
```

Create this Secret in `scripts/argocd-deployment.sh`, not in Git. Use the same method as for `storage/seaweedfs-s3-creds`.

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
