# Monitoring stack

The monitoring stack collects metrics and shows them. Prometheus stores the metrics, and Grafana shows them in dashboards. KEDA reads the vLLM queue metric from this Prometheus to scale the model.

The stack Application is `argocd/stacks/monitoring.yaml`. It has sync wave 0, together with the storage stack.

| App | What it does | Namespace | Sync wave | README |
| --- | --- | --- | --- | --- |
| kube-prometheus-stack | Prometheus, Grafana, Prometheus Operator, kube-state-metrics, node-exporter | monitoring | 0 | [helm/monitoring/kube-prometheus-stack](../../../helm/monitoring/kube-prometheus-stack/README.md) |
| grafana-dashboards | The official vLLM dashboards in the Grafana folder vLLM | monitoring | 1 | [helm/monitoring/grafana-dashboards](../../../helm/monitoring/grafana-dashboards/README.md) |

All pods run on the management node. Prometheus is at `http://localhost:9090`, and Grafana is at `http://localhost:3000`.

To make sure that the stack works, run:

```bash
kubectl -n argocd get application monitoring kube-prometheus-stack grafana-dashboards
kubectl -n monitoring get pods
```
