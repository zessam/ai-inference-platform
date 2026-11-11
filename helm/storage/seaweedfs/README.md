# SeaweedFS

SeaweedFS stores the model files and serves them over the S3 API. When a vLLM pod starts, it downloads its model from the bucket `models`.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/storage/seaweedfs.yaml` |
| Chart | `seaweedfs` 4.53.0 from https://seaweedfs.github.io/seaweedfs/helm |
| Namespace | storage |
| Sync wave | 0 in the storage stack |
| Node | inference-lab-worker4 (pool=storage) |
| S3 endpoint | `http://localhost:8333` on the host, `seaweedfs-all-in-one.storage.svc:8333` in the cluster |

## Configuration

SeaweedFS runs as one all-in-one pod: master, volume, filer and S3 gateway together. The data is in the hostPath `/data` of the storage node. kind mounts that path from `C:\kind-storage\seaweedfs` on the Windows host.

S3 authentication is on. The chart can generate the keys with Helm `lookup`. Argo CD cannot run `lookup`, so those keys change on every sync. That is why the keys come from a Secret. Both identities read their keys from the Secret `storage/seaweedfs-s3-creds`. `scripts/argocd-deployment.sh` creates it from `.lab-secrets.json`.

| Identity | Keys in `.lab-secrets.json` | Rights |
| --- | --- | --- |
| admin | `adminAccessKey`, `adminSecretKey` | read, write, list |
| read | `readAccessKey`, `readSecretKey` | read, list |

The vLLM model download uses the read keys.

## Upload a model

The section "Upload the model" in `docs/PLAN.md` gives the `aws` commands. Use the admin keys, because the read keys cannot write.

## Make sure that it works

```bash
kubectl -n storage get pods -o wide
kubectl -n storage get svc seaweedfs-all-in-one
```
