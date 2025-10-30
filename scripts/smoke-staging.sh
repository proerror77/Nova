#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${NAMESPACE:-nova}"
CURL_IMAGE="${CURL_IMAGE:-curlimages/curl:8.10.1}"
TIMEOUT="${TIMEOUT:-10}"

CHECKS=(
  "auth-service:8084:/health"
  "user-service:8080:/api/v1/health"
  "content-service:8081:/api/v1/health"
  "media-service:8082:/api/v1/health"
  "messaging-service:3000:/health"
  "feed-service:8000:/health"
  "notification-service:8000:/health"
  "streaming-service:8083:/health"
)

METRICS_CHECKS=(
  "auth-service:8084:/metrics"
  "media-service:8082:/metrics"
  "feed-service:8000:/metrics"
  "messaging-service:3000:/metrics"
  "user-service:8080:/metrics"
  "content-service:8081:/metrics"
  "notification-service:8000:/metrics"
  "streaming-service:8083:/metrics"
)

echo ">>> Using namespace: ${NAMESPACE}"
echo ">>> Verifying kubectl context..."
kubectl cluster-info >/dev/null

echo ">>> Current pods:"
kubectl -n "${NAMESPACE}" get pods

echo ">>> Waiting for pods to become Ready..."
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pods --all --timeout=300s

run_curl() {
  local name="$1"
  local host="$2"
  local port="$3"
  local path="$4"

  local url="http://${host}:${port}${path}"
  echo ">>> [${name}] GET ${url}"

  kubectl -n "${NAMESPACE}" run "smoke-${name}" \
    --image="${CURL_IMAGE}" \
    --restart=Never \
    --rm \
    -- curl -fsS --max-time "${TIMEOUT}" "${url}" >/dev/null
}

echo ">>> Checking service health endpoints"
for entry in "${CHECKS[@]}"; do
  IFS=":" read -r service port path <<<"${entry}"
  run_curl "${service}-health" "${service}" "${port}" "${path}"
done

echo ">>> Checking Prometheus metrics endpoints"
for entry in "${METRICS_CHECKS[@]}"; do
  IFS=":" read -r service port path <<<"${entry}"
  run_curl "${service}-metrics" "${service}" "${port}" "${path}" || {
    echo "!!! Warning: metrics endpoint failed for ${service}"
  }
done

echo ">>> Verifying Redis Sentinel topology (optional)"
if kubectl -n "${NAMESPACE}" get statefulset redis-sentinel >/dev/null 2>&1; then
  kubectl -n "${NAMESPACE}" exec redis-sentinel-0 -- redis-cli SENTINEL masters
else
  echo "    Sentinel statefulset not found, skipping."
fi

echo ">>> Verifying Kafka topic availability (optional)"
if kubectl -n "${NAMESPACE}" get statefulset kafka >/dev/null 2>&1; then
  kubectl -n "${NAMESPACE}" exec kafka-0 -- \
    kafka-topics.sh --bootstrap-server kafka:9092 --list
else
  echo "    Kafka statefulset not found, skipping."
fi

echo ">>> Smoke test completed successfully."
