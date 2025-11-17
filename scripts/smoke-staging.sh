#!/usr/bin/env bash

set -euo pipefail

# Tuning knobs (can be overridden via env)
SMOKE_RETRIES=${SMOKE_RETRIES:-3}
SMOKE_RETRY_DELAY=${SMOKE_RETRY_DELAY:-5}
SMOKE_ALLOW_POD_WAIT_FAIL=${SMOKE_ALLOW_POD_WAIT_FAIL:-false}
SMOKE_SKIP_METRICS=${SMOKE_SKIP_METRICS:-false}
SMOKE_SKIP_OPENAPI=${SMOKE_SKIP_OPENAPI:-false}
# Comma-separated service names to skip entirely (e.g. "notification-service,search-service")
SKIP_SERVICES=${SKIP_SERVICES:-}

NAMESPACE="${NAMESPACE:-nova}"
CURL_IMAGE="${CURL_IMAGE:-curlimages/curl:8.10.1}"
TIMEOUT="${TIMEOUT:-10}"

CHECKS=(
  "auth-service:8084:/health"
  "content-service:8081:/api/v1/health"
  "media-service:8082:/api/v1/health"
  "realtime-chat-service:8080:/health"
  "feed-service:8000:/health"
  "notification-service:8000:/health"
)

METRICS_CHECKS=(
  "auth-service:8084:/metrics"
  "media-service:8082:/metrics"
  "feed-service:8000:/metrics"
  "content-service:8081:/metrics"
  "notification-service:8000:/metrics"
)

OPENAPI_CHECKS=(
  "auth-service:8084:/api/v1/openapi.json"
  "content-service:8081:/api/v1/openapi.json"
  "feed-service:8000:/api/v1/openapi.json"
  "media-service:8082:/api/v1/openapi.json"
  "search-service:8080:/api/v1/openapi.json"
)

echo ">>> Using namespace: ${NAMESPACE}"
echo ">>> Verifying kubectl context..."
kubectl cluster-info >/dev/null

echo ">>> Current pods:"
kubectl -n "${NAMESPACE}" get pods

echo ">>> Waiting for pods to become Ready... (timeout 300s)"
if ! kubectl -n "${NAMESPACE}" wait --for=condition=Ready pods --all --timeout=300s; then
  if [ "${SMOKE_ALLOW_POD_WAIT_FAIL}" = "true" ]; then
    echo "!!! Warning: pod readiness wait failed; continuing due to SMOKE_ALLOW_POD_WAIT_FAIL=true"
  else
    echo "❌ Pods not ready within timeout"; exit 1
  fi
fi

contains_in_csv() {
  # $1: csv, $2: needle
  IFS=',' read -r -a arr <<<"$1"
  for it in "${arr[@]}"; do
    if [ "${it}" = "$2" ]; then return 0; fi
  done
  return 1
}

run_curl() {
  local name="$1"
  local host="$2"
  local port="$3"
  local path="$4"

  local url="http://${host}:${port}${path}"
  echo ">>> [${name}] GET ${url} (retries=${SMOKE_RETRIES}, delay=${SMOKE_RETRY_DELAY}s)"

  local attempt=1
  while [ "$attempt" -le "$SMOKE_RETRIES" ]; do
    if kubectl -n "${NAMESPACE}" run "smoke-${name}" \
      --image="${CURL_IMAGE}" \
      --restart=Never \
      --rm \
      -- curl -fsS --max-time "${TIMEOUT}" "${url}" >/dev/null; then
      return 0
    fi
    echo "    attempt ${attempt}/${SMOKE_RETRIES} failed; retrying..."
    attempt=$((attempt+1))
    sleep "${SMOKE_RETRY_DELAY}"
  done
  return 1
}

echo ">>> Checking service health endpoints"
for entry in "${CHECKS[@]}"; do
  IFS=":" read -r service port path <<<"${entry}"
  if [ -n "${SKIP_SERVICES}" ] && contains_in_csv "${SKIP_SERVICES}" "${service}"; then
    echo "    Skipping ${service} (listed in SKIP_SERVICES)"
    continue
  fi
  if ! run_curl "${service}-health" "${service}" "${port}" "${path}"; then
    echo "❌ Health check failed for ${service}"
    if [ "${SMOKE_ALLOW_PARTIAL:-false}" = "true" ]; then
      echo "    Continuing due to SMOKE_ALLOW_PARTIAL=true"
      continue
    fi
    exit 1
  fi
done

if [ "${SMOKE_SKIP_METRICS}" = "true" ]; then
  echo ">>> Skipping Prometheus metrics checks (SMOKE_SKIP_METRICS=true)"
else
  echo ">>> Checking Prometheus metrics endpoints"
  for entry in "${METRICS_CHECKS[@]}"; do
    IFS=":" read -r service port path <<<"${entry}"
    if [ -n "${SKIP_SERVICES}" ] && contains_in_csv "${SKIP_SERVICES}" "${service}"; then
      echo "    Skipping ${service} metrics (listed in SKIP_SERVICES)"; continue
    fi
    run_curl "${service}-metrics" "${service}" "${port}" "${path}" || {
      echo "!!! Warning: metrics endpoint failed for ${service}"
    }
  done
fi

if [ "${SMOKE_SKIP_OPENAPI}" = "true" ]; then
  echo ">>> Skipping OpenAPI checks (SMOKE_SKIP_OPENAPI=true)"
else
  echo ">>> Checking OpenAPI documentation endpoints"
  for entry in "${OPENAPI_CHECKS[@]}"; do
    IFS=":" read -r service port path <<<"${entry}"
    if [ -n "${SKIP_SERVICES}" ] && contains_in_csv "${SKIP_SERVICES}" "${service}"; then
      echo "    Skipping ${service} openapi (listed in SKIP_SERVICES)"; continue
    fi
    if ! run_curl "${service}-openapi" "${service}" "${port}" "${path}"; then
      echo "❌ OpenAPI check failed for ${service}"
      if [ "${SMOKE_ALLOW_PARTIAL:-false}" = "true" ]; then
        echo "    Continuing due to SMOKE_ALLOW_PARTIAL=true"
        continue
      fi
      exit 1
    fi
  done
fi

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
