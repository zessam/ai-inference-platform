#!/usr/bin/env bash
# Sends parallel chat requests to the vLLM model through the KServe gateway,
# so that requests wait in the vLLM queue and KEDA scales the model.
# Each worker sends one request after another until the time is up.
# Prints the HPA state every 15 seconds and a summary at the end.
# Press Ctrl+C to stop early.
# Run from any directory. Works in Git Bash on Windows.
#
# Usage: scripts/generate-load.sh [workers] [seconds] [max_tokens]
#   workers     parallel requests (default 12; vLLM runs 4, the rest wait)
#   seconds     duration of the load (default 240)
#   max_tokens  tokens per answer (default 400; longer answers keep vLLM busy)
# Environment:
#   GATEWAY_URL  base URL of the gateway (default http://localhost:8081). If it
#                does not answer, the script starts a port-forward itself.
set -uo pipefail

WORKERS="${1:-12}"
SECONDS_TOTAL="${2:-240}"
MAX_TOKENS="${3:-400}"
NS="inference"
NAME="smollm2"
MODEL="smollm2-135m-instruct"
GATEWAY_URL="${GATEWAY_URL:-http://localhost:8081}"

TMP=$(mktemp -d)
PF_PID=""
cleanup() {
  jobs -p | xargs -r kill 2>/dev/null
  [[ -n "$PF_PID" ]] && kill "$PF_PID" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'echo; echo "Stopped."; exit 130' INT

models_url() { echo "$1/$NS/$NAME/v1/models"; }

# Use the gateway on GATEWAY_URL, or start a port-forward to it.
if ! curl -s -o /dev/null --max-time 5 "$(models_url "$GATEWAY_URL")"; then
  echo "==> $GATEWAY_URL does not answer. Starting a port-forward on localhost:18081."
  svc=$(kubectl -n envoy-gateway-system get svc -l gateway.envoyproxy.io/owning-gateway-name=kserve-ingress-gateway -o jsonpath='{.items[0].metadata.name}')
  [[ -n "$svc" ]] || { echo "Gateway Service not found."; exit 1; }
  kubectl -n envoy-gateway-system port-forward "svc/$svc" 18081:80 >/dev/null 2>&1 &
  PF_PID=$!
  GATEWAY_URL="http://localhost:18081"
  for _ in $(seq 1 20); do curl -s -o /dev/null --max-time 2 "$(models_url "$GATEWAY_URL")" && break; sleep 1; done
fi
curl -s -o /dev/null --max-time 5 "$(models_url "$GATEWAY_URL")" || { echo "Gateway does not answer on $GATEWAY_URL."; exit 1; }

URL="$GATEWAY_URL/$NS/$NAME/v1/chat/completions"
BODY="{\"model\":\"$MODEL\",\"max_tokens\":$MAX_TOKENS,\"messages\":[{\"role\":\"user\",\"content\":\"Write a long story about a robot who learns Kubernetes.\"}]}"
END=$(( $(date +%s) + SECONDS_TOTAL ))

echo "==> $WORKERS workers for $SECONDS_TOTAL seconds against $URL"
for w in $(seq 1 "$WORKERS"); do
  (
    while (( $(date +%s) < END )); do
      code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 300 \
        -H 'Content-Type: application/json' -d "$BODY" "$URL" || echo 000)
      echo "$code" >> "$TMP/worker-$w"
    done
  ) &
done

# Show the scaling while the load runs.
while (( $(date +%s) < END )); do
  sleep 15
  done_n=$(cat "$TMP"/worker-* 2>/dev/null | wc -l)
  hpa=$(kubectl -n "$NS" get hpa --no-headers 2>/dev/null | awk '{print "target " $3 "  replicas " $(NF-1)}')
  pods=$(kubectl -n "$NS" get pods -l "app.kubernetes.io/name=$NAME,app.kubernetes.io/component=llminferenceservice-workload" \
    --no-headers -o custom-columns=POD:.metadata.name,NODE:.spec.nodeName,READY:.status.containerStatuses[0].ready 2>/dev/null | tr '\n' ' ')
  printf '%s  done %-4s  %s  pods: %s\n' "$(date +%H:%M:%S)" "$done_n" "${hpa:-hpa ?}" "$pods"
done

echo "==> Waiting for the last requests to finish"
wait $(jobs -p | grep -v "^${PF_PID:-x}$") 2>/dev/null

total=$(cat "$TMP"/worker-* 2>/dev/null | wc -l)
ok=$(cat "$TMP"/worker-* 2>/dev/null | grep -c '^200$')
echo "==> Requests: $total, successful (200): $ok, failed: $(( total - ok ))"
echo "    Codes: $(cat "$TMP"/worker-* 2>/dev/null | sort | uniq -c | tr '\n' ' ')"
echo "    The HPA scales back to 1 replica about 5 minutes after the queue is empty."
echo "    Watch it with: kubectl -n $NS get hpa,pods -o wide -w"
