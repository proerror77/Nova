#!/usr/bin/env bash
set -euo pipefail

API="http://localhost:${USER_SERVICE_PORT:-8080}/api/v1"
REDIS_PW="${REDIS_PASSWORD:-redis123}"

log() { echo -e "[validate] $*"; }

req() { curl -sS -H 'Content-Type: application/json' "$@"; }

# 1) Register + verify + login A/B
SUFFIX=$(date +%s)
A_EMAIL="alice+$SUFFIX@example.com"
B_EMAIL="bob+$SUFFIX@example.com"

log "registering users..."
A_REG=$(req -X POST -d '{"email":"'$A_EMAIL'","username":"a'$SUFFIX'","password":"Aa1!aaaa"}' "$API/auth/register")
A_ID=$(jq -r .id <<< "$A_REG")
B_REG=$(req -X POST -d '{"email":"'$B_EMAIL'","username":"b'$SUFFIX'","password":"Aa1!aaaa"}' "$API/auth/register")
B_ID=$(jq -r .id <<< "$B_REG")

log "verifying emails..."
A_TOKEN=$(docker compose exec -T redis redis-cli -a "$REDIS_PW" --raw GET "verify_email:$A_ID:$A_EMAIL" | tr -d '\r')
B_TOKEN=$(docker compose exec -T redis redis-cli -a "$REDIS_PW" --raw GET "verify_email:$B_ID:$B_EMAIL" | tr -d '\r')
req -X POST -d '{"token":"'$A_TOKEN'"}' "$API/auth/verify-email" >/dev/null
req -X POST -d '{"token":"'$B_TOKEN'"}' "$API/auth/verify-email" >/dev/null

log "logging in..."
A_JWT=$(req -X POST -d '{"email":"'$A_EMAIL'","password":"Aa1!aaaa"}' "$API/auth/login" | jq -r .access_token)
B_JWT=$(req -X POST -d '{"email":"'$B_EMAIL'","password":"Aa1!aaaa"}' "$API/auth/login" | jq -r .access_token)

# 2) Create direct conversation A->B
log "creating conversation..."
CONV=$(curl -sS -H "Authorization: Bearer $A_JWT" -H 'Content-Type: application/json' -d '{"type":"direct","participant_ids":["'$B_ID'"]}' "$API/conversations")
CONV_ID=$(jq -r .id <<< "$CONV")
log "conversation: $CONV_ID"

# 3) Send message (with search_text)
log "sending message..."
MSG=$(curl -sS -H "Authorization: Bearer $A_JWT" -H 'Content-Type: application/json' \
  -d '{"conversation_id":"'$CONV_ID'","encrypted_content":"hello","nonce":"0123456789abcdefghijklmnopqrstuv","message_type":"text","search_text":"hello world"}' \
  "$API/messages")
MID=$(jq -r .id <<< "$MSG")
log "message id: $MID"

# 4) Search
log "searching..."
curl -sS -H "Authorization: Bearer $A_JWT" "$API/messages/search?conversation_id=$CONV_ID&q=hello&limit=5" | jq .

# 5) Edit + Delete
log "editing..."
curl -sS -H "Authorization: Bearer $A_JWT" -H 'Content-Type: application/json' -X PATCH \
  -d '{"encrypted_content":"hello-edited","nonce":"0123456789abcdefghijklmnopqrstuv","search_text":"hello edited"}' \
  "$API/messages/$MID" | jq . >/dev/null

log "deleting..."
curl -sS -H "Authorization: Bearer $A_JWT" -X DELETE "$API/messages/$MID" -o /dev/null -w '%{http_code}\n'

log "done"

