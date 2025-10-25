#!/usr/bin/env bash
set -euo pipefail

# Simple E2E smoke test: register -> verify -> login -> upload PK -> create convo -> ws -> send -> history

USER_SERVICE_BASE="${USER_SERVICE_BASE:-http://localhost:8080}"
WS_BASE="${WS_BASE:-ws://localhost:8085}"

# Load .env if present to pick up REDIS_URL/USER_SERVICE_PORT etc.
if [[ -f .env ]]; then
  set -a; source .env; set +a
elif [[ -f .env.example ]]; then
  set -a; source .env.example; set +a
fi

# Derive Redis connection from REDIS_URL if provided; fallback to defaults
REDIS_HOST="${REDIS_HOST:-}"
REDIS_PORT="${REDIS_PORT:-}"
REDIS_PASS="${REDIS_PASS:-}"
if [[ -n "${REDIS_URL:-}" ]]; then
  # Expected format: redis://:password@host:port/db
  py='import os,sys,urllib.parse as u; p=u.urlparse(os.environ["REDIS_URL"]); pw=(p.password or ""); host=p.hostname or "127.0.0.1"; port=p.port or 6379; print(host, port, pw)'
  read -r host port pass <<<"$( REDIS_URL="$REDIS_URL" python3 -c "$py" )"
  REDIS_HOST=${REDIS_HOST:-$host}
  REDIS_PORT=${REDIS_PORT:-$port}
  REDIS_PASS=${REDIS_PASS:-$pass}
fi
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASS="${REDIS_PASS:-redis123}"

function jget() { python3 -c "import sys, json; print(json.load(sys.stdin)$1)"; }

function curl_json() {
  local method="$1"; shift
  local url="$1"; shift
  curl -sS -m 10 -X "$method" "$url" -H 'Content-Type: application/json' "$@"
}

function redis_get() {
  local key="$1"
  # Try without AUTH first
  local resp
  resp=$( printf "*2\r\n\$3\r\nGET\r\n\$%d\r\n%s\r\n" ${#key} "$key" | nc -w 2 "$REDIS_HOST" "$REDIS_PORT" || true )
  if printf "%s" "$resp" | grep -q -- "^-NOAUTH"; then
    resp=$( printf "*2\r\n\$4\r\nAUTH\r\n\$%d\r\n%s\r\n*2\r\n\$3\r\nGET\r\n\$%d\r\n%s\r\n" \
      ${#REDIS_PASS} "$REDIS_PASS" ${#key} "$key" | nc -w 2 "$REDIS_HOST" "$REDIS_PORT" || true )
  fi
  # Parse bulk string: find the last non-control line
  local line token=""
  while IFS= read -r line; do
    case "$line" in
      (""|+*|\$*|\**|-*) ;;
      (*) token="$line" ;;
    esac
  done <<<"$resp"
  token="${token%%$'\r'}"
  printf "%s" "$token"
}

echo "== Healthchecks =="
curl -sS -i "$USER_SERVICE_BASE/api/v1/health" | head -n 1 || true
curl -sS -i "http://localhost:8085/health" | head -n 1 || true

ts=$(date +%s)
EMAIL_A="alice+$ts@local.test"
EMAIL_B="bob+$ts@local.test"
PASS="Passw0rd!A$ts"

echo "== Register users =="
REG_A=$(curl_json POST "$USER_SERVICE_BASE/api/v1/auth/register" -d "{\"email\":\"$EMAIL_A\",\"username\":\"alice$ts\",\"password\":\"$PASS\"}")
REG_B=$(curl_json POST "$USER_SERVICE_BASE/api/v1/auth/register" -d "{\"email\":\"$EMAIL_B\",\"username\":\"bob$ts\",\"password\":\"$PASS\"}")
ID_A=$(printf "%s" "$REG_A" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')
ID_B=$(printf "%s" "$REG_B" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')
echo "A: $ID_A  B: $ID_B"

echo "== Login (or fallback to Redis verify) =="
LOGIN_A=$(curl_json POST "$USER_SERVICE_BASE/api/v1/auth/login" -d "{\"email\":\"$EMAIL_A\",\"password\":\"$PASS\"}") || true
LOGIN_B=$(curl_json POST "$USER_SERVICE_BASE/api/v1/auth/login" -d "{\"email\":\"$EMAIL_B\",\"password\":\"$PASS\"}") || true
JWT_A=$(printf "%s" "$LOGIN_A" | python3 -c 'import sys,json;import json as j; s=sys.stdin.read();
try:
 d=j.loads(s); print(d.get("access_token",""))
except Exception: print("")')
JWT_B=$(printf "%s" "$LOGIN_B" | python3 -c 'import sys,json;import json as j; s=sys.stdin.read();
try:
 d=j.loads(s); print(d.get("access_token",""))
except Exception: print("")')

if [[ -z "$JWT_A" || -z "$JWT_B" ]]; then
  echo "Login blocked by email verification. Fallback to Redis token flow..."
  KEY_A="verify_email:${ID_A}:${EMAIL_A}"
  KEY_B="verify_email:${ID_B}:${EMAIL_B}"
  TOK_A=$(redis_get "$KEY_A")
  TOK_B=$(redis_get "$KEY_B")
  if [[ -z "$TOK_A" || -z "$TOK_B" ]]; then
    echo "Failed to read verify tokens from Redis. Ensure Redis is accessible and REDIS_PASS is correct." >&2
    exit 1
  fi
  echo "TOK_A=${TOK_A:0:8}.. TOK_B=${TOK_B:0:8}.."
  echo "== Verify emails =="
  curl_json POST "$USER_SERVICE_BASE/api/v1/auth/verify-email" -d "{\"token\":\"$TOK_A\"}" >/dev/null
  curl_json POST "$USER_SERVICE_BASE/api/v1/auth/verify-email" -d "{\"token\":\"$TOK_B\"}" >/dev/null
  echo "== Login =="
  LOGIN_A=$(curl_json POST "$USER_SERVICE_BASE/api/v1/auth/login" -d "{\"email\":\"$EMAIL_A\",\"password\":\"$PASS\"}")
  LOGIN_B=$(curl_json POST "$USER_SERVICE_BASE/api/v1/auth/login" -d "{\"email\":\"$EMAIL_B\",\"password\":\"$PASS\"}")
  JWT_A=$(printf "%s" "$LOGIN_A" | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
  JWT_B=$(printf "%s" "$LOGIN_B" | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')
fi

echo "JWT_A len=${#JWT_A} JWT_B len=${#JWT_B}"

echo "== Upload public keys =="
PK_A=$(openssl rand -base64 32)
PK_B=$(openssl rand -base64 32)
curl_json PUT "$USER_SERVICE_BASE/api/v1/users/me/public-key" -H "Authorization: Bearer $JWT_A" -d "{\"public_key\":\"$PK_A\"}" -i | head -n 1
curl_json PUT "$USER_SERVICE_BASE/api/v1/users/me/public-key" -H "Authorization: Bearer $JWT_B" -d "{\"public_key\":\"$PK_B\"}" -i | head -n 1

echo "== Create direct conversation (A -> B) =="
CONV=$(curl_json POST "$USER_SERVICE_BASE/api/v1/conversations" -H "Authorization: Bearer $JWT_A" -d "{\"type\":\"direct\",\"participant_ids\":[\"$ID_B\"]}")
CONV_ID=$(printf "%s" "$CONV" | python3 -c 'import sys,json;print(json.load(sys.stdin)["id"])')
echo "CONV_ID=$CONV_ID"

echo "== Start WS listener as B (10s) and send message from A =="
NONCE=$(openssl rand -base64 24)
CT=$(openssl rand -base64 48)

PYWS=$(cat <<'PY'
import asyncio, json, os, sys
import websockets

ws_base = os.environ['WS_BASE']
conv = os.environ['CONV_ID']
uid = os.environ['USER_ID']
url = f"{ws_base}/ws?conversation_id={conv}&user_id={uid}"

async def main():
    async with websockets.connect(url, ping_interval=None) as ws:
        try:
            msg = await asyncio.wait_for(ws.recv(), timeout=10)
            print("WS_RECEIVED:", msg)
        except Exception as e:
            print("WS_TIMEOUT", e)

asyncio.run(main())
PY
)

export WS_BASE
export CONV_ID
export USER_ID="$ID_B"

set +e
python3 -c "$PYWS" &
WS_PID=$!
sleep 1
set -e

curl_json POST "$USER_SERVICE_BASE/api/v1/messages" -H "Authorization: Bearer $JWT_A" \
  -d "{\"conversation_id\":\"$CONV_ID\",\"encrypted_content\":\"$CT\",\"nonce\":\"$NONCE\",\"message_type\":\"text\"}"

wait $WS_PID || true

echo "== Get history =="
curl_json GET "$USER_SERVICE_BASE/api/v1/conversations/$CONV_ID/messages" -H "Authorization: Bearer $JWT_A" | python3 - <<'PY'
import sys, json
d=json.load(sys.stdin)
print("count=", len(d.get("messages", [])))
PY

echo "✅ Smoke test completed"
