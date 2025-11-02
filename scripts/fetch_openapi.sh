#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <api-base-url>" >&2
  echo "Example: $0 https://staging-api.nova.example.com" >&2
  exit 1
fi

BASE_URL="$1"
shift || true

OUTPUT_DIR=${1:-specs}
mkdir -p "${OUTPUT_DIR}"

fetch() {
  local service=$1
  local path=$2
  local target="${OUTPUT_DIR}/${service}.openapi.json"
  echo "Downloading ${service} OpenAPI → ${target}" >&2
  curl -sf "${BASE_URL}${path}" -o "${target}"
}

fetch auth "/auth/api/v1/openapi.json"
fetch user "/users/api/v1/openapi.json"
fetch content "/content/api/v1/openapi.json"
fetch feed "/feed/api/v1/openapi.json"
fetch messaging "/messaging/api/v1/openapi.json"
fetch media "/media/api/v1/openapi.json"
fetch search "/search/api/v1/openapi.json"
fetch streaming "/streaming/api/v1/openapi.json"

echo "✅ OpenAPI specs downloaded to ${OUTPUT_DIR}" >&2
