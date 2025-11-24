#!/usr/bin/env bash

# Simple staging smoke test for GraphQL Gateway REST endpoints.
# Requires the following env vars:
#   GW_BASE   - Gateway base URL (e.g. https://your-alb-dns)
#   TOKEN     - Bearer JWT
#   USER_ID   - UUID of the test user
#
# Optional:
#   CHANNEL_ID - Existing channel id to test subscribe/unsubscribe
#   CONV_ID    - Existing conversation id to test chat send_message
#   NONMEMBER_TOKEN - A JWT of a non-member to test 403 on messages/conversation
#
# Usage:
#   GW_BASE=https://... TOKEN=... USER_ID=... ./scripts/staging-smoke-test.sh

set -euo pipefail

if [[ -z "${GW_BASE:-}" || -z "${TOKEN:-}" || -z "${USER_ID:-}" ]]; then
  echo "Please set GW_BASE, TOKEN, USER_ID env vars before running." >&2
  exit 1
fi

AUTH_HEADER="Authorization: Bearer ${TOKEN}"
JSON="Content-Type: application/json"

step() { printf "\n=== %s ===\n" "$1"; }

step "Health (expects 401/403 if auth enforced)"
curl -s -o /dev/null -w "HTTP %{http_code}\n" "${GW_BASE}/health"

step "Profile: GET /api/v2/users/{id}"
curl -s -H "${AUTH_HEADER}" "${GW_BASE}/api/v2/users/${USER_ID}" | sed 's/^/  /'

step "Channels: GET /api/v2/channels"
CHANNEL_JSON=$(curl -s -H "${AUTH_HEADER}" "${GW_BASE}/api/v2/channels")
echo "${CHANNEL_JSON}" | head -c 400 | sed 's/^/  /'
CHANNEL_ID=${CHANNEL_ID:-$(echo "${CHANNEL_JSON}" | jq -r '.channels[0].id // empty')}
if [[ -n "${CHANNEL_ID}" ]]; then
  step "Channels: GET /api/v2/channels/${CHANNEL_ID}"
  curl -s -H "${AUTH_HEADER}" "${GW_BASE}/api/v2/channels/${CHANNEL_ID}" | sed 's/^/  /'

  step "Channels: GET /api/v2/users/{id}/channels"
  curl -s -H "${AUTH_HEADER}" "${GW_BASE}/api/v2/users/${USER_ID}/channels" | sed 's/^/  /'
fi

step "Devices: GET /api/v2/devices"
curl -s -H "${AUTH_HEADER}" "${GW_BASE}/api/v2/devices" | sed 's/^/  /'

step "Invitations: POST /api/v2/invitations/generate"
curl -s -H "${AUTH_HEADER}" -X POST "${GW_BASE}/api/v2/invitations/generate" | sed 's/^/  /'

step "Chat: GET /api/v2/chat/conversations (no auth fallback expected)"
curl -s -H "${AUTH_HEADER}" "${GW_BASE}/api/v2/chat/conversations" | head -c 400 | sed 's/^/  /'

# Optional: send_message smoke (requires an existing conversation_id)
if [[ -n "${CONV_ID:-}" ]]; then
  step "Chat: POST /api/v2/chat/messages (conversation_id=${CONV_ID})"
  curl -s -X POST "${GW_BASE}/api/v2/chat/messages" \
    -H "${AUTH_HEADER}" -H "${JSON}" \
    -d "{\"conversation_id\":\"${CONV_ID}\",\"content\":\"smoke-test\",\"message_type\":0,\"media_url\":\"\",\"reply_to_message_id\":\"\"}" \
    | sed 's/^/  /'

  if [[ -n "${NONMEMBER_TOKEN:-}" ]]; then
    step "Chat (negative): GET /api/v2/chat/conversations/${CONV_ID} with non-member (expect 403)"
    curl -s -o /dev/null -w "HTTP %{http_code}\n" \
      -H "Authorization: Bearer ${NONMEMBER_TOKEN}" \
      "${GW_BASE}/api/v2/chat/conversations/${CONV_ID}"

    step "Chat (negative): GET /api/v2/chat/messages with non-member (expect 403)"
    curl -s -o /dev/null -w "HTTP %{http_code}\n" \
      -H "Authorization: Bearer ${NONMEMBER_TOKEN}" \
      "${GW_BASE}/api/v2/chat/messages?conversation_id=${CONV_ID}&limit=1"
  fi
fi

echo
echo "Smoke test completed. Review HTTP codes and payloads above."
