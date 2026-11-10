# Argo CD patches for the local lab

## Purpose

These files make the Argo CD UI reachable at http://localhost:8085 on the Windows host over plain HTTP, not TLS. Use them only in a local lab. Argo CD sends the login password without encryption, so anyone on the network can read it.

## Prerequisite

Before you create the kind cluster `inference-lab`, the file `cluster/kind-config.yaml` must contain this port mapping on the control-plane node:

```yaml
- {containerPort: 30085, hostPort: 8085, listenAddress: "127.0.0.1"}  # Argo CD UI
```

It forwards port 8085 on the host to port 30085 on the control-plane node. You cannot add kind port mappings to a running cluster. If the mapping is missing, run `kind delete cluster --name inference-lab` and create the cluster again. That deletes everything in the cluster.

## Files

A merge patch sets the keys you list and leaves the other keys alone. A strategic merge patch merges list entries by name, here the port name.

| File | Target resource | Namespace | Patch type | What it changes |
| --- | --- | --- | --- | --- |
| `argocd-insecure.yaml` | ConfigMap `argocd-cmd-params-cm` | `argocd` | Merge | Sets `server.insecure` to `"true"`, so argocd-server serves plain HTTP |
| `argocd-nodeport.yaml` | Service `argocd-server` | `argocd` | Strategic merge | Sets the type to `NodePort` and maps node port 30085 to container port 8080 |

## Apply

Run these commands in PowerShell from the root of the repository, in this order:

```powershell
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side
kubectl -n argocd patch configmap argocd-cmd-params-cm --type merge --patch-file patches/argocd-insecure.yaml
kubectl -n argocd patch svc argocd-server --patch-file patches/argocd-nodeport.yaml
kubectl -n argocd rollout restart deployment argocd-server
kubectl -n argocd rollout status deployment argocd-server
```

The `--server-side` flag is needed because the install manifest is too large for the default client-side apply. The restart makes argocd-server read the new ConfigMap.

## Check

```powershell
kubectl -n argocd get configmap argocd-cmd-params-cm -o yaml   # expect server.insecure: "true"
kubectl -n argocd get svc argocd-server                        # expect 80:30085/TCP
```

## Sign in

Open http://localhost:8085. The username is `admin`. Read the initial password with:

```powershell
kubectl -n argocd get secret argocd-initial-admin-secret -o go-template="{{.data.password | base64decode}}"
```

Change the password after the first sign-in. Argo CD deletes that secret when you change the password.

## Helm alternative

If you install Argo CD with the Helm chart, you do not need these patches. Put this in the values file instead. Helm applies it on every upgrade, so an upgrade does not undo the change.

```yaml
configs:
  params:
    server.insecure: true
server:
  service:
    type: NodePort
    nodePortHttp: 30085
```

## Troubleshooting

If port 8085 is already in use, run `netstat -ano | findstr :8085` to find the process ID, then stop that program.

If the secret is not found, the Argo CD pods are not ready yet, so wait and run the command again. Or you changed the admin password, and Argo CD deleted the secret. Use the password you set.

The command `kind delete cluster` deletes the cluster and Argo CD with it. Apply these patches again after you create the cluster again.
