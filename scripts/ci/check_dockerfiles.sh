#!/usr/bin/env bash
set -euo pipefail

fail=0
extra=$(ls backend/Dockerfile.messaging.* 2>/dev/null || true)
if [ -n "$extra" ]; then
  echo "[ERROR] Unexpected extra Dockerfile variants detected:" >&2
  echo "$extra" >&2
  fail=1
fi

exit $fail

