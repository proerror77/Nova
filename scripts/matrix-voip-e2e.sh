#!/usr/bin/env bash
set -euo pipefail

MATRIX_BASE_URL="${MATRIX_BASE_URL:-https://matrix.staging.gcp.icered.com}"
NAMESPACE="${NAMESPACE:-nova-staging}"
TOKEN_SECRET_NAME="${TOKEN_SECRET_NAME:-nova-matrix-service-token}"
TOKEN_KEY="${TOKEN_KEY:-MATRIX_ACCESS_TOKEN}"
CURL_MAX_TIME="${CURL_MAX_TIME:-10}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd python3

if [[ "$MATRIX_BASE_URL" == */ ]]; then
  MATRIX_BASE_URL="${MATRIX_BASE_URL%/}"
fi

if [[ -z "${MATRIX_ACCESS_TOKEN:-}" ]]; then
  require_cmd kubectl
  require_cmd base64

  token_b64="$(
    kubectl get secret "$TOKEN_SECRET_NAME" -n "$NAMESPACE" --request-timeout=30s \
      -o jsonpath="{.data.${TOKEN_KEY}}" 2>/dev/null || true
  )"
  if [[ -z "$token_b64" ]]; then
    echo "Missing access token. Set MATRIX_ACCESS_TOKEN or ensure secret ${TOKEN_SECRET_NAME} has key ${TOKEN_KEY}." >&2
    exit 1
  fi
  MATRIX_ACCESS_TOKEN="$(printf '%s' "$token_b64" | base64 -d)"
fi

echo "Checking Matrix versions endpoint..."
versions_url="${MATRIX_BASE_URL}/_matrix/client/versions"
if ! curl -fsS --max-time "$CURL_MAX_TIME" "${versions_url}" >/dev/null; then
  versions_url="${MATRIX_BASE_URL}/_matrix/client/v3/versions"
  curl -fsS --max-time "$CURL_MAX_TIME" "${versions_url}" >/dev/null
fi
echo "OK: versions endpoint reachable"

echo "Fetching TURN credentials from Matrix..."
turn_json=""
turn_endpoint=""
for path in "/_matrix/client/v3/voip/turnServer" "/_matrix/client/v1/voip/turnServer" "/_matrix/client/r0/voip/turnServer"; do
  resp="$(curl -fsS --max-time "$CURL_MAX_TIME" -H "Authorization: Bearer ${MATRIX_ACCESS_TOKEN}" "${MATRIX_BASE_URL}${path}" || true)"
  if [[ -z "$resp" ]]; then
    continue
  fi
  if TURN_JSON="$resp" python3 - <<'PY'
import json
import os
import sys

raw = os.environ.get("TURN_JSON", "")
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print("ERROR: turnServer response not valid JSON", file=sys.stderr)
    sys.exit(1)

uris = data.get("uris") or []
if not uris:
    print("ERROR: turnServer response missing uris", file=sys.stderr)
    sys.exit(1)
if not any(u.startswith("turn:") or u.startswith("turns:") for u in uris):
    print("ERROR: turnServer response uris missing turn/turns schemes", file=sys.stderr)
    sys.exit(1)
if not data.get("username") or not data.get("password"):
    print("ERROR: turnServer response missing username/password", file=sys.stderr)
    sys.exit(1)

print(f"OK: turn_uris_count={len(uris)}")
ttl = data.get("ttl")
if ttl is not None:
    print(f"OK: turn_ttl_seconds={ttl}")
PY
  then
    turn_json="$resp"
    turn_endpoint="$path"
    break
  fi
done

if [[ -z "$turn_json" ]]; then
  echo "ERROR: no valid TURN credentials returned from Matrix" >&2
  exit 1
fi
echo "OK: turnServer endpoint=${turn_endpoint}"

if command -v kubectl >/dev/null 2>&1; then
  echo "Checking turn-server Service external address..."
  turn_ip=""
  turn_host=""
  for svc in turn-server turn-server-tcp; do
    turn_ip="$(kubectl get svc "$svc" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    turn_host="$(kubectl get svc "$svc" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    if [[ -n "$turn_ip" || -n "$turn_host" ]]; then
      break
    fi
  done
  if [[ -n "$turn_ip" ]]; then
    echo "OK: turn-server external IP=${turn_ip}"
  elif [[ -n "$turn_host" ]]; then
    echo "OK: turn-server external hostname=${turn_host}"
  else
    echo "WARN: turn-server external address pending"
  fi
fi
