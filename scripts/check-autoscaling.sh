#!/usr/bin/env bash
# Checks each link of the vLLM autoscaling chain before a load test:
#   Argo CD apps -> KEDA -> external metrics API -> LLMInferenceService ->
#   ScaledObject -> HPA -> Prometheus metric.
# Prints PASS, WARN or FAIL for each check. Exit code 1 if a check fails.
# Run from any directory. Works in Git Bash on Windows.
# Usage: scripts/check-autoscaling.sh [namespace] [llminferenceservice]
set -uo pipefail

NS="${1:-inference}"
NAME="${2:-smollm2}"
METRIC="vllm:num_requests_waiting"
FAILED=0

pass() { printf '  PASS  %s\n' "$1"; }
warn() { printf '  WARN  %s\n' "$1"; }
fail() { printf '  FAIL  %s\n' "$1"; FAILED=1; }
check() { # check <description> <actual> <expected>
  if [[ "$2" == "$3" ]]; then pass "$1 ($2)"; else fail "$1 (got '${2:-nothing}', want '$3')"; fi
}

echo "==> Argo CD applications"
for app in keda kserve vllm; do
  s=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)
  check "application $app" "$s" "Synced/Healthy"
done

echo "==> KEDA"
for d in keda-operator keda-operator-metrics-apiserver; do
  r=$(kubectl -n keda get deployment "$d" -o jsonpath='{.status.readyReplicas}/{.spec.replicas}' 2>/dev/null)
  if [[ -n "$r" && "${r%/*}" == "${r#*/}" ]]; then pass "deployment $d ready ($r)"; else fail "deployment $d ready (got '${r:-nothing}')"; fi
done
a=$(kubectl get apiservice v1beta1.external.metrics.k8s.io -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
check "APIService v1beta1.external.metrics.k8s.io available" "$a" "True"

echo "==> Model $NS/$NAME"
r=$(kubectl -n "$NS" get llminferenceservice "$NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
check "LLMInferenceService Ready" "$r" "True"
pods=$(kubectl -n "$NS" get pods -l "app.kubernetes.io/name=$NAME,app.kubernetes.io/component=llminferenceservice-workload" \
  -o jsonpath='{range .items[*]}{.metadata.name} {.spec.nodeName} {.status.phase}{"\n"}{end}' 2>/dev/null)
if [[ -n "$pods" ]]; then
  pass "vLLM pods:"; printf '          %s\n' "$pods"
else
  fail "no vLLM pods found"
fi

echo "==> ScaledObject and HPA"
so=$(kubectl -n "$NS" get scaledobject -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -z "$so" ]]; then
  fail "no ScaledObject in $NS (restart the KServe controller: kubectl -n kserve rollout restart deployment/llmisvc-controller-manager)"
else
  r=$(kubectl -n "$NS" get scaledobject "$so" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
  check "ScaledObject $so Ready" "$r" "True"
  hpa=$(kubectl -n "$NS" get hpa -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  if [[ -z "$hpa" ]]; then
    fail "no HPA in $NS"
  else
    r=$(kubectl -n "$NS" get hpa "$hpa" -o jsonpath='{.status.conditions[?(@.type=="ScalingActive")].status}')
    check "HPA $hpa ScalingActive (HPA can read the metric)" "$r" "True"
    kubectl -n "$NS" get hpa "$hpa" | sed 's/^/          /'
  fi
  # Ask the external metrics API directly, the same way the HPA does.
  v=$(kubectl get --raw "/apis/external.metrics.k8s.io/v1beta1/namespaces/$NS/s0-prometheus?labelSelector=scaledobject.keda.sh%2Fname%3D$so" 2>/dev/null \
    | sed -n 's/.*"value":"\([^"]*\)".*/\1/p')
  if [[ -n "$v" ]]; then pass "KEDA external metric value ($v)"; else fail "KEDA external metric has no value"; fi
fi

echo "==> Prometheus"
q="sum($METRIC{namespace=\"$NS\"})"
enc=$(printf '%s' "$q" | sed 's/ /%20/g; s/{/%7B/g; s/}/%7D/g; s/"/%22/g; s/=/%3D/g; s/(/%28/g; s/)/%29/g; s/:/%3A/g')
res=$(kubectl get --raw "/api/v1/namespaces/monitoring/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=$enc" 2>/dev/null)
val=$(printf '%s' "$res" | sed -n 's/.*"value":\[[^,]*,"\([^"]*\)"\].*/\1/p')
if [[ -n "$val" ]]; then pass "Prometheus $q = $val"; else fail "Prometheus has no data for $q (PodMonitor scraping?)"; fi

echo "==> Images on the inference nodes (for a fast scale-up)"
if command -v docker >/dev/null 2>&1; then
  for n in inference-lab-worker2 inference-lab-worker3; do
    if docker exec "$n" crictl images 2>/dev/null | grep -q 'vllm-openai-cpu'; then pass "$n has the vLLM image"; else warn "$n has no vLLM image (the first pod there pulls 1.75 GB)"; fi
  done
else
  warn "docker not found, image check skipped"
fi

echo
if [[ $FAILED -eq 0 ]]; then echo "All checks passed. Ready for scripts/generate-load.sh."; else echo "Some checks failed. Fix them before the load test."; exit 1; fi
