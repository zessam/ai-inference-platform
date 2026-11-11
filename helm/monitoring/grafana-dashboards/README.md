# Grafana dashboards

This local chart adds dashboards to Grafana. Each JSON file in `dashboards/<folder>/` becomes a ConfigMap with the label `grafana_dashboard: "1"`. The Grafana sidecar of kube-prometheus-stack loads these ConfigMaps from all namespaces.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/monitoring/grafana-dashboards.yaml` |
| Chart | local chart in this folder, version 0.1.0 |
| Namespace | monitoring |
| Sync wave | 1 in the monitoring stack, after kube-prometheus-stack |

## Dashboards

The folder vLLM holds the official vLLM dashboards from the vLLM repository, tag v0.23.0:

| File | Title in Grafana |
| --- | --- |
| `dashboards/vllm/vllm.json` | vLLM |
| `dashboards/vllm/vllm-performance-statistics.json` | Performance Statistics |
| `dashboards/vllm/vllm-query-statistics.json` | Query Statistics_New4 |

The only change to the files is that the saved variable selections are cleared. Grafana then selects the default Prometheus and the first model.

## Add a dashboard

1. Put the JSON file in `dashboards/<folder>/`.
2. For a new folder, add it under `folders` in `values.yaml`.
3. Push the change.

## Make sure that it works

```bash
kubectl -n monitoring get configmap -l grafana_dashboard=1
```
