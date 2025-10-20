#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

# Generate ephemeral RSA keys for JWT (PEM) into .tmp (gitignored by default in most setups)
TMP_DIR="$ROOT_DIR/.tmp/dev-jwt"
mkdir -p "$TMP_DIR"
PRIV="$TMP_DIR/private.pem"
PUB="$TMP_DIR/public.pem"
if [ ! -s "$PRIV" ] || [ ! -s "$PUB" ]; then
  echo "Generating dev JWT RSA keypair..."
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$PRIV" >/dev/null 2>&1
  openssl pkey -in "$PRIV" -pubout -out "$PUB" >/dev/null 2>&1
fi

# Export required env vars for docker compose variable substitution
export JWT_PRIVATE_KEY_PEM="$(cat "$PRIV")"
export JWT_PUBLIC_KEY_PEM="$(cat "$PUB")"
export S3_BUCKET_NAME="${S3_BUCKET_NAME:-nova-dev}"
export S3_REGION="${S3_REGION:-us-east-1}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test-access}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test-secret}"
export CLOUDFRONT_URL="${CLOUDFRONT_URL:-http://localhost:8082}"

echo "Starting core services (zookeeper, kafka, postgres, redis, clickhouse, user-service)..."
docker compose up -d zookeeper kafka postgres redis clickhouse user-service

echo -n "Waiting for user-service health"
for i in $(seq 1 80); do
  if curl -fsS http://localhost:8080/api/v1/health >/dev/null 2>&1; then
    echo; echo "✅ user-service is healthy"; break
  fi
  sleep 3
  echo -n "."
  if [ "$i" -eq 80 ]; then
    echo; echo "❌ user-service failed to become healthy"; docker compose ps; docker compose logs --no-color --tail=200 user-service || true; exit 1
  fi
done

echo "Tip: to stop: docker compose stop user-service redis postgres kafka clickhouse zookeeper"

