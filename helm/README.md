# Helm values

This folder holds the Helm values for every app that Argo CD deploys. Each app has its own folder. Argo CD reads these files from the `main` branch on GitHub, not from your disk. A change has no effect until you push it.

## Layout

```
helm/<stack>/[<group>/]<app>/values.yaml     values for a chart from a public chart repository
helm/<stack>/[<group>/]<app>/Chart.yaml      only for a chart that this repository holds
helm/<stack>/[<group>/]<app>/templates/      only for a chart that this repository holds
```

The stack names are the same as the folder names in `argocd/apps/`: storage, monitoring, management and inference. The app folder has the same name as the Application file. For example, `argocd/apps/storage/seaweedfs.yaml` uses `helm/storage/seaweedfs/values.yaml`.

A group folder holds apps that belong together. It has the same name in `argocd/apps/` and in `helm/`. For example, `argocd/apps/management/kserve/lws.yaml` uses `helm/management/kserve/lws/values.yaml`. A group also needs a group Application, for example `argocd/apps/management/kserve.yaml`, that syncs the folder. The stack Applications do not read subfolders.

## Current apps

| Stack/group | App | Chart repository | Chart | Version | Node pool |
| --- | --- | --- | --- | --- | --- |
| storage | seaweedfs | https://seaweedfs.github.io/seaweedfs/helm | seaweedfs | 4.53.0 | storage |
| monitoring | kube-prometheus-stack | https://prometheus-community.github.io/helm-charts | kube-prometheus-stack | 93.1.2 | management |
| management/kserve | cert-manager | https://charts.jetstack.io | cert-manager | v1.21.3 | management |
| management/kserve | lws | registry.k8s.io/lws/charts (OCI) | lws | v0.8.0 | management |
| management/kserve | envoy-gateway | docker.io/envoyproxy (OCI) | gateway-helm | v1.8.6 | management |
| management/kserve | envoy-ai-gateway | docker.io/envoyproxy (OCI) | ai-gateway-helm | v1.1.0 | management |
| management/kserve | kserve-llmisvc-resources | ghcr.io/kserve/charts (OCI) | kserve-llmisvc-resources | v0.21.0 | management |
| management/kserve | kserve-runtime-configs | ghcr.io/kserve/charts (OCI) | kserve-runtime-configs | v0.21.0 | No pods |
| management/kserve | kserve-gateway | This repository | helm/management/kserve/kserve-gateway | 0.1.0 | management |
| management | portkey | This repository | helm/management/portkey | 0.1.0 | management |
| inference | vllm | This repository | helm/inference/vllm | 0.1.0 | inference |

The CRD charts `envoy-ai-gateway-crds` and `kserve-llmisvc-crd` have no values file, so they have no folder here.

`docs/PLAN.md` lists the apps that come next.

## How Argo CD reads a values file

Each Application in `argocd/apps/` has two sources. A source is a location from which Argo CD reads files. The first source is the chart. The second source is this repository, with `ref: values`. The `ref` gives this repository a name, so the first source can use its files as `$values/<path>`.

```yaml
  sources:
    - repoURL: https://seaweedfs.github.io/seaweedfs/helm
      chart: seaweedfs
      targetRevision: 4.53.0
      helm:
        releaseName: seaweedfs
        valueFiles:
          - $values/helm/storage/seaweedfs/values.yaml
    - repoURL: https://github.com/zessam/ai-inference-platform.git
      targetRevision: main
      ref: values
```

If you move or rename a values file, change the `valueFiles` path in the Application in the same commit. If the path is wrong, the sync of that Application fails.

## Rules for a values file

- Put only the values that you change. The chart supplies the defaults for all other values.
- Set the node placement in the values file. Most apps use the node selector `pool: management`.
- For a storage app, use `pool: storage` and a toleration for the taint `workload=storage:NoSchedule`.
- For an inference app, use `pool: inference` and a toleration for the taint `workload=inference:NoSchedule`.
- Do not put passwords or keys in a values file. Git keeps them in its history. Create a Kubernetes Secret outside Git, for example in `scripts/argocd-deployment.sh`. Then give the name of the Secret to the chart, usually with a value such as `existingSecret`.
- Make sure that each key exists in the chart version that the Application pins. Keys change between chart versions.
- Some charts take a field as a multi-line string, not as a map. The SeaweedFS chart does this for `nodeSelector` and `tolerations`. Write those fields with `|`.

## Add an app

You need Helm on your computer for steps 2 and 4. These steps do not change the cluster.

1. Create the folder `helm/<stack>/<app>/`, or `helm/<stack>/<group>/<app>/` for an app in a group.
2. Read the default values of the chart version that you will pin: `helm show values <chart> --repo <chart-repo-url> --version <version>`.
3. Create `values.yaml` in the new folder with the values that you change.
4. Render the chart on your computer to make sure that Helm accepts the values: `helm template <app> <chart> --repo <chart-repo-url> --version <version> --namespace <namespace> -f helm/<stack>/<app>/values.yaml`.
5. Create `argocd/apps/<stack>/<app>.yaml`, or `argocd/apps/<stack>/<group>/<app>.yaml` for an app in a group. Copy `argocd/apps/storage/seaweedfs.yaml`, then change the chart, version, release name, namespace and values path.
6. Commit and push the two new files.
7. Make sure that Argo CD created the app and that it is Synced and Healthy: `kubectl -n argocd get application <app>`.

The stack Application syncs from `main`, so it creates the new Application after the push in step 6.

## Charts in this repository

If the chart is in this repository, the Application needs only one source. Set `path` to the chart folder. Helm then reads `values.yaml` in that folder without a `valueFiles` entry.

```yaml
  source:
    repoURL: https://github.com/zessam/ai-inference-platform.git
    targetRevision: main
    path: helm/inference/vllm
```

`helm/management/kserve/kserve-gateway` and `helm/inference/vllm` are examples.
