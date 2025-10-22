#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
USER_SVC="$ROOT_DIR/backend/user-service/src"
MAIN_RS="$USER_SVC/main.rs"

pass=true

check() {
  local what="$1"; shift
  if eval "$@" >/dev/null 2>&1; then
    echo "[OK]  $what"
  else
    echo "[ERR] $what" >&2
    pass=false
  fi
}

# Files exist
check "messaging handlers present" test -f "$USER_SVC/handlers/messaging.rs"
check "stories handlers present" test -f "$USER_SVC/handlers/stories.rs"
check "messaging repo present" test -f "$USER_SVC/db/messaging_repo.rs"
check "stories repo present" test -f "$USER_SVC/db/stories_repo.rs"
check "messaging migration present" test -f "$ROOT_DIR/backend/migrations/018_messaging_schema.sql"
check "stories migration present" test -f "$ROOT_DIR/backend/migrations/019_stories_schema.sql"

# Routes mounted
check "messages scope mounted" grep -q "scope\(\"/messages\"\)" "$MAIN_RS"
check "conversations scope mounted" grep -q "scope\(\"/conversations\"\)" "$MAIN_RS"
check "stories scope mounted" grep -q "scope\(\"/stories\"\)" "$MAIN_RS"

# Build check (fast)
(
  cd "$ROOT_DIR/backend/user-service"
  cargo check -q
) && echo "[OK]  cargo check user-service" || { echo "[ERR] cargo check user-service"; pass=false; }

if [ "$pass" = true ]; then
  echo "All spec checks passed."
  exit 0
else
  echo "One or more spec checks failed." >&2
  exit 1
fi

