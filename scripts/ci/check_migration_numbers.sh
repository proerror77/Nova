#!/usr/bin/env bash
set -euo pipefail

fail=0

check_dir() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  mapfile -t nums < <(ls "$dir" | grep -E '^[0-9]{4}_.+\.sql$' | sed -E 's/^([0-9]{4})_.+$/\1/' | sort)
  if [ "${#nums[@]}" -gt 0 ]; then
    dups=$(printf '%s\n' "${nums[@]}" | uniq -d || true)
    if [ -n "$dups" ]; then
      echo "[ERROR] Duplicate migration numbers in $dir:" >&2
      printf '  %s\n' $dups >&2
      fail=1
    fi
  fi
}

check_dir backend/messaging-service/migrations
check_dir backend/migrations

exit $fail

