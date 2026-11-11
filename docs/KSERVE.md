# KServe in this platform

This file explains the KServe setup in the management stack. It lists each component and what it does. Then it follows one model from deployment to the first answer.

KServe serves machine learning models on Kubernetes. This platform uses the KServe resource LLMInferenceService, which deploys vLLM with llm-d routing. All the components are Argo CD Applications in the group `kserve`. The Application files are in `argocd/apps/management/kserve/`, and the Helm values are in `helm/management/kserve/`.

## Terms

These terms appear in the rest of this file:

- A CRD (custom resource definition) adds a new object type to Kubernetes.
- A controller is a program that watches objects and creates what they describe.
- A webhook is an HTTPS service that the Kubernetes API server calls before it saves an object. It can fill in defaults or reject the object.
- An LLMInferenceService describes one model: the model location, the image and the number of replicas.
- An LLMInferenceServiceConfig is a reusable template for parts of an LLMInferenceService.
- An InferencePool is a group of model server pods that serve the same model.
- The endpoint picker is the llm-d scheduler. It chooses the pod for each request.
- The KV cache is the data that vLLM keeps for the tokens of earlier prompts.

## Components

Argo CD installs the components in sync waves. A sync wave is a number on an Application. Argo CD starts a wave only after all Applications in the lower waves are Healthy.

| Wave | Argo CD Application | Namespace | What it does |
| --- | --- | --- | --- |
| -1 | repositories | argocd | Tells Argo CD that three registries hold Helm charts in OCI format: docker.io/envoyproxy, ghcr.io/kserve/charts and registry.k8s.io/lws/charts. |
| 0 | cert-manager | cert-manager | Issues and renews the TLS certificates for the webhooks of KServe, LeaderWorkerSet and Envoy AI Gateway. |
| 1 | lws | lws-system | Runs LeaderWorkerSet. When one model runs on several nodes, KServe uses it. |
| 1 | envoy-gateway | envoy-gateway-system | Runs Envoy Gateway, the entry point for traffic. It also installs the Gateway API CRDs. |
| 1 | envoy-ai-gateway-crds | envoy-ai-gateway-system | Adds the CRDs of Envoy AI Gateway. |
| 1 | kserve-llmisvc-crd | kserve | Adds the CRDs for LLMInferenceService and LLMInferenceServiceConfig. |
| 2 | envoy-ai-gateway | envoy-ai-gateway-system | Lets Envoy Gateway send traffic to an InferencePool. |
| 2 | kserve-llmisvc-resources | kserve | Runs the KServe controller for LLMInferenceService. It also adds the InferencePool and llm-d CRDs and the S3 configuration for SeaweedFS. |
| 3 | kserve-runtime-configs | kserve | Adds the LLMInferenceServiceConfig templates for the vLLM container, the scheduler and the router. |
| 3 | kserve-gateway | kserve | Creates the Gateway `kserve/kserve-ingress-gateway`, its GatewayClass `envoy` and its EnvoyProxy. |

All pods of these components run on the management node (`pool: management`).

### Why each component is necessary

The repository Secrets are necessary because Envoy Gateway, LeaderWorkerSet and KServe publish their charts only to OCI registries. Without the Secrets, Argo CD cannot download these charts. The Secrets hold no passwords, because the registries are public.

cert-manager is necessary because the API server calls webhooks only over HTTPS. Each webhook needs a certificate that the API server trusts. cert-manager issues the certificate and writes the CA into the `caBundle` field of the webhook configuration. The Applications tell Argo CD to ignore `caBundle`, so that a sync does not remove it.

LeaderWorkerSet is necessary for models that do not fit on the GPUs of one node. vLLM then runs as a leader pod and worker pods on several nodes. A Deployment cannot start and restart these pods as one unit, but a LeaderWorkerSet can.

Envoy Gateway is necessary because KServe does not route traffic itself. KServe creates an HTTPRoute, and a Gateway API implementation must serve it. Envoy Gateway is that implementation. It runs the Envoy proxy pods that receive the requests.

Envoy AI Gateway is necessary because plain Envoy Gateway cannot send traffic to an InferencePool. Envoy Gateway calls the AI Gateway controller each time that it builds a routing configuration. The controller adds a step to that configuration: ask the endpoint picker which pod to use.

The KServe controller turns each LLMInferenceService into the objects that serve the model. The runtime templates keep each LLMInferenceService short. The model file names only the model, the image and the replicas, and it takes the rest from the templates.

The kserve-gateway chart is the only component that this repository defines. KServe expects a Gateway but does not create one. The chart creates these resources:

- The EnvoyProxy runs the Envoy proxy pods on the management node. It names their Service `kserve-ingress-gateway` and opens it on NodePort 30081.
- The GatewayClass `envoy` connects the Gateway API to Envoy Gateway.
- The Gateway `kserve/kserve-ingress-gateway` listens on port 80. KServe uses this Gateway by default.

kind maps host port 8081 to NodePort 30081. So, on the Windows host, the gateway is at `http://localhost:8081`. Inside the cluster, the gateway is at `http://kserve-ingress-gateway.envoy-gateway-system.svc`. The EnvoyProxy gives the proxy Service this fixed name, so that LiteLLM can send requests to it.

## Scenario: deploy a model

In this scenario, you deploy the model `smollm2` with vLLM. The model files are in `s3://models/smollm2-135m-instruct` in SeaweedFS. The components above must be Healthy before you start.

1. You apply an LLMInferenceService. It names the model URI, the vLLM image and one replica.
2. The Kubernetes API server sends the object to the KServe webhook over HTTPS. The webhook fills in defaults and makes sure that the fields are correct. If a field is wrong, the API server rejects the object, and `kubectl` shows the error.
3. The KServe controller reads the new object. It merges your spec with the templates from `kserve-runtime-configs`.
4. The controller creates the vLLM pods on the inference nodes. For one node, it uses a Deployment. For several nodes, it uses a LeaderWorkerSet.
5. Before vLLM starts, an init step downloads the model from SeaweedFS into the pod. It reads the S3 endpoint from the KServe configuration and the keys from your Secret.
6. vLLM loads the model. It opens its OpenAI-compatible API and its `/metrics` endpoint.
7. The controller creates the InferencePool for the vLLM pods and starts the endpoint picker.
8. The controller creates an HTTPRoute on the Gateway `kserve/kserve-ingress-gateway`. The route sends the traffic for the model to the InferencePool.
9. Envoy Gateway builds a new routing configuration for the Envoy proxy. Envoy AI Gateway adds the call to the endpoint picker.
10. KServe marks the LLMInferenceService as Ready.

## Scenario: send a request

In this scenario, the model `smollm2` is Ready, and you send a chat request from the Windows host.

1. You send the request to `http://localhost:8081`.
2. kind forwards it to NodePort 30081, and it reaches the Envoy proxy on the management node.
3. Envoy finds the HTTPRoute for the model. The target of the route is the InferencePool.
4. Envoy asks the endpoint picker which pod to use.
5. The endpoint picker chooses a pod. It prefers a pod that already has the start of the prompt in its KV cache. Otherwise, it chooses the pod with the shortest queue.
6. Envoy forwards the request to that pod.
7. vLLM generates the answer, and Envoy sends it back to you.
8. Prometheus reads the vLLM metrics from each pod, for example the number of requests that wait in the queue.

With one replica, the endpoint picker has only one choice. When two or more replicas run, the choice changes the response time. With large models on GPUs, the effect is larger.

## Not installed yet

KEDA is not installed. So, if the queue grows, the number of vLLM replicas does not change. KEDA will read the metric `vllm:num_requests_waiting` from Prometheus. When requests wait in the queue, KEDA will add replicas. Then the new pod downloads the model, joins the InferencePool, and gets traffic from the endpoint picker.

The vLLM model `inference/smollm2` is defined in `helm/inference/vllm`. The section "Inference stack" in `docs/PLAN.md` describes it.
