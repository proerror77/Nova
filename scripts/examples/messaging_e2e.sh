#!/usr/bin/env bash
set -euo pipefail

# Messaging E2E example script
# Runs a minimal direct + group conversation flow against the local API.
#
# Prerequisites:
# - API running locally (defaults to http://localhost:8080)
# - Environment variables (auto mode if omitted):
#     TOKEN         : JWT access token for the acting user (optional; auto if omitted)
#     PEER_ID       : UUID of another existing user (optional; auto if omitted)
#     NEW_MEMBER_ID : UUID of a third user (optional; auto if omitted)
#     REDIS_HOST    : Redis host (default: localhost)
#     REDIS_PORT    : Redis port (default: 6379)
#     REDIS_PASSWORD: Redis password (default: redis123)
# - Tools: curl, jq, redis-cli
#
# Usage examples:
#   # Fully auto (register + verify + login 3 users)
#   bash scripts/examples/messaging_e2e.sh
#
#   # Use existing actor token, auto-create peer and new member
#   TOKEN=... bash scripts/examples/messaging_e2e.sh
#
#   # Provide everything explicitly
#   TOKEN=... PEER_ID=... NEW_MEMBER_ID=... bash scripts/examples/messaging_e2e.sh

API_BASE="${API_BASE:-http://localhost:8080/api/v1}"
REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-redis123}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 is required" >&2; exit 1; }
}

require_env() {
  local name="$1"; shift || true
  if [[ -z "${!name:-}" ]]; then
    echo "Error: environment variable $name is required" >&2
    exit 1
  fi
}

banner() {
  echo
  echo "== $* =="
}

json() { jq -r '.'; }

uuid_sfx() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z' | cut -c1-8
  else
    date +%s%N | tail -c 8
  fi
}

api_post() {
  local path="$1"; shift
  local body="$1"; shift
  curl -sS -f -X POST "$API_BASE$path" -H "Content-Type: application/json" -d "$body"
}

register_user() {
  # args: email username password
  local email="$1" username="$2" password="$3"
  api_post "/auth/register" "{\"email\":\"$email\",\"username\":\"$username\",\"password\":\"$password\"}"
}

redis_get() {
  # args: key
  local key="$1"
  redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -a "$REDIS_PASSWORD" GET "$key"
}

verify_email() {
  # args: token
  local token="$1"
  api_post "/auth/verify-email" "{\"token\":\"$token\"}"
}

login_user() {
  # args: email password
  local email="$1" password="$2"
  api_post "/auth/login" "{\"email\":\"$email\",\"password\":\"$password\"}"
}

main() {
  require_cmd curl
  require_cmd jq
  require_cmd redis-cli

  echo "API_BASE: $API_BASE"
  echo "REDIS: $REDIS_HOST:$REDIS_PORT"

  local actor_email actor_username actor_password
  local peer_email peer_username peer_password
  local nm_email nm_username nm_password
  local ACTOR_ID PEER_ID_LOCAL NEW_MEMBER_ID_LOCAL

  # Auto-create users if not provided
  if [[ -z "${TOKEN:-}" ]]; then
    banner "Auto: register + verify + login actor/peer/new member"
    # Actor
    actor_email="actor_$(uuid_sfx)@example.com"
    actor_username="actor_$(uuid_sfx)"
    actor_password="Aa#123456!"
    ACTOR_REG=$(register_user "$actor_email" "$actor_username" "$actor_password")
    echo "$ACTOR_REG" | json
    ACTOR_ID=$(echo "$ACTOR_REG" | jq -r .id)
    # Fetch verification token from Redis (forward mapping)
    ACTOR_TOKEN=$(redis_get "verify_email:$ACTOR_ID:$actor_email")
    verify_email "$ACTOR_TOKEN" | json >/dev/null
    ACTOR_LOGIN=$(login_user "$actor_email" "$actor_password")
    echo "$ACTOR_LOGIN" | json
    TOKEN=$(echo "$ACTOR_LOGIN" | jq -r .access_token)

    # Peer
    peer_email="peer_$(uuid_sfx)@example.com"
    peer_username="peer_$(uuid_sfx)"
    peer_password="Aa#123456!"
    PEER_REG=$(register_user "$peer_email" "$peer_username" "$peer_password")
    PEER_ID_LOCAL=$(echo "$PEER_REG" | jq -r .id)
    PEER_TOKEN_VAL=$(redis_get "verify_email:$PEER_ID_LOCAL:$peer_email")
    verify_email "$PEER_TOKEN_VAL" | json >/dev/null

    # New member
    nm_email="member_$(uuid_sfx)@example.com"
    nm_username="member_$(uuid_sfx)"
    nm_password="Aa#123456!"
    NM_REG=$(register_user "$nm_email" "$nm_username" "$nm_password")
    NEW_MEMBER_ID_LOCAL=$(echo "$NM_REG" | jq -r .id)
    NM_TOKEN_VAL=$(redis_get "verify_email:$NEW_MEMBER_ID_LOCAL:$nm_email")
    verify_email "$NM_TOKEN_VAL" | json >/dev/null
  else
    banner "Using provided TOKEN; creating missing IDs if needed"
    ACTOR_ID="(unknown)"
    if [[ -z "${PEER_ID:-}" ]]; then
      peer_email="peer_$(uuid_sfx)@example.com"; peer_username="peer_$(uuid_sfx)"; peer_password="Aa#123456!"
      PEER_REG=$(register_user "$peer_email" "$peer_username" "$peer_password")
      PEER_ID_LOCAL=$(echo "$PEER_REG" | jq -r .id)
      PEER_TOKEN_VAL=$(redis_get "verify_email:$PEER_ID_LOCAL:$peer_email")
      verify_email "$PEER_TOKEN_VAL" | json >/dev/null
    else
      PEER_ID_LOCAL="$PEER_ID"
    fi
    if [[ -z "${NEW_MEMBER_ID:-}" ]]; then
      nm_email="member_$(uuid_sfx)@example.com"; nm_username="member_$(uuid_sfx)"; nm_password="Aa#123456!"
      NM_REG=$(register_user "$nm_email" "$nm_username" "$nm_password")
      NEW_MEMBER_ID_LOCAL=$(echo "$NM_REG" | jq -r .id)
      NM_TOKEN_VAL=$(redis_get "verify_email:$NEW_MEMBER_ID_LOCAL:$nm_email")
      verify_email "$NM_TOKEN_VAL" | json >/dev/null
    else
      NEW_MEMBER_ID_LOCAL="$NEW_MEMBER_ID"
    fi
  fi

  # Export for subsequent curl calls
  export TOKEN
  : "${PEER_ID:=${PEER_ID_LOCAL:-}}";
  : "${NEW_MEMBER_ID:=${NEW_MEMBER_ID_LOCAL:-}}";
  require_env TOKEN
  require_env PEER_ID
  require_env NEW_MEMBER_ID

  # Simple health check
  banner "Health check"
  curl -sS "$API_BASE/health" | json >/dev/null || true
  echo "OK"

  # 1) Create direct conversation
  banner "Create direct conversation"
  CREATE_RES=$(curl -sS -f -X POST "$API_BASE/conversations" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"type":"direct","participant_ids":["'"$PEER_ID"'"]}')
  echo "$CREATE_RES" | json
  CONV_ID=$(echo "$CREATE_RES" | jq -r .id)
  if [[ "$CONV_ID" == "null" || -z "$CONV_ID" ]]; then
    echo "Failed to create direct conversation" >&2; exit 1
  fi
  echo "CONV_ID=$CONV_ID"

  # 2) Send a message in direct conversation
  banner "Send message (direct)"
  # Use a 32-character Base64 nonce (24 bytes base64-encoded, no padding)
  NONCE="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  SEND_RES=$(curl -sS -f -X POST "$API_BASE/messages" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "conversation_id":"'"$CONV_ID"'",
      "encrypted_content":"YmFzZTY0LWNpcGhlcnRleHQtY29udGVudA==",
      "nonce":"'"$NONCE"'",
      "message_type":"text"
    }')
  echo "$SEND_RES" | json
  MSG_ID=$(echo "$SEND_RES" | jq -r .id)
  echo "MSG_ID=$MSG_ID"

  # 3) Fetch message history
  banner "Fetch message history (direct)"
  curl -sS -f -G "$API_BASE/conversations/$CONV_ID/messages" \
    -H "Authorization: Bearer $TOKEN" \
    --data-urlencode "limit=50" | json | jq '.messages | length as $n | {messages: $n, has_more, next_cursor}'

  # 4) Mark as read
  banner "Mark as read"
  curl -sS -f -X POST "$API_BASE/conversations/$CONV_ID/read" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"message_id":"'"$MSG_ID"'"}' | json

  # 5) List conversations
  banner "List conversations (archived=false)"
  curl -sS -f "$API_BASE/conversations?limit=20&offset=0&archived=false" \
    -H "Authorization: Bearer $TOKEN" | json | jq '{total, limit, offset, items: (.conversations | length)}'

  # 6) Create group conversation
  banner "Create group conversation"
  G_CREATE_RES=$(curl -sS -f -X POST "$API_BASE/conversations" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "type":"group",
      "name":"Team Chat",
      "participant_ids":["'"$PEER_ID"'"]
    }')
  echo "$G_CREATE_RES" | json
  G_CONV_ID=$(echo "$G_CREATE_RES" | jq -r .id)
  echo "G_CONV_ID=$G_CONV_ID"

  # 7) Add a member to group (owner/admin only)
  banner "Add member to group"
  curl -sS -f -X POST "$API_BASE/conversations/$G_CONV_ID/members" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"user_ids":["'"$NEW_MEMBER_ID"'"]}' | json

  # 8) Update my settings (mute & archive)
  banner "Update my settings (mute & archive)"
  curl -sS -f -X PATCH "$API_BASE/conversations/$G_CONV_ID/settings" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"is_muted":true,"is_archived":true}' | json

  # 9) List conversations again without archived
  banner "List conversations again (archived=false)"
  curl -sS -f "$API_BASE/conversations?limit=20&offset=0&archived=false" \
    -H "Authorization: Bearer $TOKEN" | json | jq '{total, limit, offset, items: (.conversations | length)}'

  # 10) Remove the new member (204 No Content expected)
  banner "Remove member from group"
  STATUS=$(curl -sS -o /dev/null -w "%{http_code}" -X DELETE "$API_BASE/conversations/$G_CONV_ID/members/$NEW_MEMBER_ID" \
    -H "Authorization: Bearer $TOKEN")
  echo "HTTP $STATUS (expected 204)"
  if [[ "$STATUS" != "204" ]]; then
    echo "Unexpected status removing member" >&2; exit 1
  fi

  echo
  echo "All steps completed successfully."
}

main "$@"
