# LiteLLM database

This local chart creates the PostgreSQL database of LiteLLM as a CloudNativePG Cluster. LiteLLM stores its virtual keys, budgets and spend logs there.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/management/litellm/litellm-db.yaml` |
| Chart | local chart in this folder, version 0.1.0 |
| Namespace | litellm |
| Sync wave | 1 in the LiteLLM group |
| Image | `ghcr.io/cloudnative-pg/postgresql:17.9-minimal-trixie` |
| Storage | 2Gi on the default StorageClass of kind |

## What CloudNativePG creates

From the Cluster `litellm-db`, the operator creates these objects:

- The PostgreSQL pod and its volume.
- The Service `litellm-db-rw` for reads and writes.
- The Secret `litellm-db-app` with the keys `username`, `password`, `host`, `port`, `dbname` and `uri`.

LiteLLM reads the Secret `litellm-db-app`. Nobody types the password.

## Make sure that it works

```bash
kubectl -n litellm get cluster litellm-db
kubectl -n litellm get secret litellm-db-app
```
