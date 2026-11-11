# Storage stack

The storage stack stores the model files. It has one app, SeaweedFS, which serves an S3 API. When a vLLM pod starts, it downloads its model from SeaweedFS.

The stack Application is `argocd/stacks/storage.yaml`. It has sync wave 0, so it starts first, together with the monitoring stack.

| App | What it does | Namespace | Sync wave | README |
| --- | --- | --- | --- | --- |
| seaweedfs | S3 storage for the models, bucket `models` | storage | 0 | [helm/storage/seaweedfs](../../../helm/storage/seaweedfs/README.md) |

SeaweedFS runs on the storage node `inference-lab-worker4`. Its data is on the Windows host in `C:\kind-storage\seaweedfs`. If you delete the cluster and create it again, the models stay.

To make sure that the stack works, run:

```bash
kubectl -n argocd get application storage seaweedfs
kubectl -n storage get pods -o wide
```
