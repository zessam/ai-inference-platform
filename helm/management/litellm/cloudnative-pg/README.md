# CloudNativePG

CloudNativePG is an operator that runs PostgreSQL clusters in Kubernetes. It runs the database of LiteLLM. It generates the database password inside the cluster, so the password is never in Git.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/management/litellm/cloudnative-pg.yaml` |
| Chart | `cloudnative-pg` 0.29.1 (operator 1.30.1) from https://cloudnative-pg.github.io/charts |
| Namespace | cnpg-system |
| Sync wave | 0 in the LiteLLM group |
| Node | inference-lab-worker (pool=management) |

## Configuration

The chart installs its CRDs (`crds.create: true`). The operator generates its own webhook certificate, so the Application ignores the `caBundle` fields.

## Make sure that it works

```bash
kubectl -n cnpg-system get pods
```
