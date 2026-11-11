# kube-prometheus-stack

This app installs Prometheus, Grafana, the Prometheus Operator, kube-state-metrics and node-exporter. Prometheus stores the metrics of the cluster and of vLLM. KEDA reads the vLLM queue metric from it.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/monitoring/kube-prometheus-stack.yaml` |
| Chart | `kube-prometheus-stack` 93.1.2 from https://prometheus-community.github.io/helm-charts |
| Namespace | monitoring |
| Sync wave | 0 in the monitoring stack |
| Node | inference-lab-worker (pool=management) |
| Prometheus | `http://localhost:9090`, NodePort 30090 |
| Grafana | `http://localhost:3000`, NodePort 30030 |

## Configuration

These values differ from the chart defaults:

- Alertmanager is off. Prometheus keeps data for 2 days.
- The monitors for etcd, kube-controller-manager, kube-scheduler and kube-proxy are off, because kind does not expose them.
- Prometheus reads ServiceMonitors and PodMonitors from all Helm releases (`*SelectorNilUsesHelmValues: false`). The vLLM PodMonitor needs this.
- node-exporter runs only on the management node (`tolerations: []`). So Prometheus has node metrics only for that node.
- The Grafana sidecar puts dashboards in the folder from the annotation `grafana_folder`.

## Grafana password

The user is `admin`. The password is `grafanaAdminPassword` in `.lab-secrets.json`. Grafana reads it from the Secret `monitoring/grafana-admin`, which `scripts/argocd-deployment.sh` creates. Without that Secret, the chart generates a password with Helm `lookup`, and the password changes on every Argo CD sync.

## Make sure that it works

```bash
kubectl -n monitoring get pods
kubectl -n monitoring get svc | grep -E "prometheus|grafana"
```
