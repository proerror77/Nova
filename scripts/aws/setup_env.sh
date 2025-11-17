#!/usr/bin/env bash

set -euo pipefail

# setup_env.sh
# - Exports AWS credentials from an AWS CLI profile to service .env files
# - Appends required S3/media-service variables with sensible defaults
#
# Usage:
#   scripts/aws/setup_env.sh [-p PROFILE] [-r REGION] [-b BUCKET] [-c CLOUDFRONT_URL] \
#                            [--media-grpc URL] [--service user|media|both]
#
# Examples:
#   scripts/aws/setup_env.sh -p default -r ap-northeast-1 -b nova-media-bucket \
#     -c https://media-cdn.nova.app --media-grpc http://127.0.0.1:9082 --service both

PROFILE="default"
REGION=""
BUCKET=""
CLOUDFRONT_URL=""
MEDIA_GRPC_URL="http://127.0.0.1:9082"
SERVICE_TARGET="both" # user | media | both

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--profile) PROFILE="$2"; shift 2;;
    -r|--region) REGION="$2"; shift 2;;
    -b|--bucket) BUCKET="$2"; shift 2;;
    -c|--cloudfront) CLOUDFRONT_URL="$2"; shift 2;;
    --media-grpc) MEDIA_GRPC_URL="$2"; shift 2;;
    --service) SERVICE_TARGET="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

command -v aws >/dev/null 2>&1 || { echo "aws CLI not found" >&2; exit 127; }

echo "[1/5] Verifying AWS identity (profile=${PROFILE})..."
AWS_PROFILE="$PROFILE" aws sts get-caller-identity >/dev/null
echo "    OK"

if [[ -z "$REGION" ]]; then
  REGION=$(AWS_PROFILE="$PROFILE" aws configure get region || true)
fi
if [[ -z "$REGION" ]]; then
  echo "Region not detected. Provide via -r/--region." >&2
  exit 1
fi

if [[ -z "$BUCKET" ]]; then
  echo "S3 bucket not provided. Use -b/--bucket to set S3 bucket." >&2
  exit 1
fi

echo "[2/5] Exporting credentials from profile to env lines..."
TMP_ENV=$(mktemp)
AWS_PROFILE="$PROFILE" aws configure export-credentials --format env > "$TMP_ENV"

echo "[3/5] Validating S3 access (bucket=$BUCKET, region=$REGION)..."
AWS_PROFILE="$PROFILE" aws s3 ls "s3://$BUCKET" --region "$REGION" >/dev/null || {
  echo "Unable to access s3://$BUCKET in region $REGION. Check permissions/policy." >&2
  rm -f "$TMP_ENV"; exit 1
}
echo "    OK"

gen_env_file() {
  local target_dir="$1"
  local outfile="$target_dir/.env"
  mkdir -p "$target_dir"

  {
    # credentials (may include temporary session token)
    cat "$TMP_ENV"
    echo "AWS_REGION=$REGION"
    echo "S3_BUCKET_NAME=$BUCKET"
    echo "S3_REGION=$REGION"
    echo "CLOUDFRONT_URL=${CLOUDFRONT_URL}"
    echo "S3_PRESIGNED_URL_EXPIRY_SECS=900"
    echo "MEDIA_SERVICE_GRPC_URL=${MEDIA_GRPC_URL}"
    echo "# Optional: S3_ENDPOINT=http://minio:9000"
    echo "# Optional: JWT_PRIVATE_KEY_FILE=/run/secrets/jwt_private.pem"
    echo "# Optional: JWT_PUBLIC_KEY_FILE=/run/secrets/jwt_public.pem"
  } > "$outfile"

  echo "    Wrote $outfile"
}

echo "[4/5] Writing .env files..."
case "$SERVICE_TARGET" in
  user)
    gen_env_file "backend/user-service" ;;
  media)
    gen_env_file "backend/media-service" ;;
  both)
    gen_env_file "backend/user-service"
    gen_env_file "backend/media-service" ;;
  *)
    echo "Unknown service target: $SERVICE_TARGET" >&2; rm -f "$TMP_ENV"; exit 2;;
esac

echo "[5/5] Done. Next steps:"
echo "  - Review backend/*-service/.env contents"
echo "  - Start services with those environments loaded"

rm -f "$TMP_ENV"

