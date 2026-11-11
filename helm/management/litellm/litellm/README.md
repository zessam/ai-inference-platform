# LiteLLM

LiteLLM Proxy is the API entry point for clients. It gives one OpenAI-compatible API, virtual API keys, budgets and rate limits, and a web UI with usage and spend. It sends the requests for the vLLM model to the KServe gateway.

| Item | Value |
| --- | --- |
| Application | `argocd/apps/management/litellm/litellm.yaml` |
| Chart | `litellm-helm` 1.106.7 from ghcr.io/berriai (OCI) |
| Namespace | litellm |
| Sync wave | 2 in the LiteLLM group |
| Node | inference-lab-worker (pool=management) |
| API | `http://localhost:8080/v1` on the host, `http://litellm.litellm.svc:4000/v1` in the cluster |
| UI | `http://localhost:8080/ui`, user `admin`, password `litellmMasterKey` |

## Models

`proxy_config.model_list` in `values.yaml` lists the models. The model `smollm2-135m-instruct` uses the provider `hosted_vllm` and this `api_base`:

```
http://kserve-ingress-gateway.envoy-gateway-system.svc.cluster.local/inference/smollm2/v1
```

This is the KServe gateway, not the vLLM Service. So the llm-d scheduler still picks the vLLM pod for each request.

## Secrets

LiteLLM reads two Secrets. Neither one is in Git:

| Secret | Keys | Created by |
| --- | --- | --- |
| `litellm-secrets` | `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY` | `scripts/create-litellm-secret.sh` or `scripts/argocd-deployment.sh` |
| `litellm-db-app` | `username`, `password`, `host` | CloudNativePG |

The master key is the admin key for the API and the UI. The salt key encrypts the credentials that LiteLLM stores in the database. After the first start, do not change the salt key. LiteLLM then cannot read those credentials.

The chart can generate the master key with Helm `lookup`. Argo CD cannot run `lookup`, so that key changes on every sync. That is why the key comes from a Secret. The chart can also run its own PostgreSQL. That database takes its password from the values file in Git, and its `bitnamilegacy` images get no updates. That is why CloudNativePG runs the database.

## Port

The chart Service has no NodePort field. So `extraResources` adds the Service `litellm-nodeport` on NodePort 30080. kind maps host port 8080 to it.

## Make sure that it works

```bash
kubectl -n litellm get pods
curl -s http://localhost:8080/v1/models -H "Authorization: Bearer <key>"
```
