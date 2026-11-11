# LiteLLM group

The LiteLLM group runs the API entry point for clients. LiteLLM gives one OpenAI-compatible API, API keys, budgets and a UI. It stores its keys and its spend data in PostgreSQL.

The group Application is `argocd/apps/management/litellm.yaml`, with the name `litellm-group`. It has sync wave 2 in the management stack, so it starts after the KServe group. Inside the group, the apps sync in this order:

| Sync wave | App | What it does | Namespace | README |
| --- | --- | --- | --- | --- |
| -1 | repositories | Argo CD repository Secret for ghcr.io/berriai (OCI) | argocd | this file |
| 0 | cloudnative-pg | Operator that runs PostgreSQL | cnpg-system | [cloudnative-pg](../../../../helm/management/litellm/cloudnative-pg/README.md) |
| 1 | litellm-db | PostgreSQL database for LiteLLM | litellm | [litellm-db](../../../../helm/management/litellm/litellm-db/README.md) |
| 2 | litellm | LiteLLM proxy and UI | litellm | [litellm](../../../../helm/management/litellm/litellm/README.md) |

The group Application has the name `litellm-group`, because the app inside it already has the name `litellm`.

`repositories.yaml` holds one Secret. It tells Argo CD that ghcr.io/berriai holds Helm charts in OCI format. The Secret has no password, because the registry is public.

To make sure that the group works, run:

```bash
kubectl -n argocd get application litellm-group cloudnative-pg litellm-db litellm
kubectl -n litellm get cluster,pods
```
