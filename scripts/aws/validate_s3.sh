#!/usr/bin/env bash
set -euo pipefail

# validate_s3.sh
# Verifies S3 access using aws CLI and prints diagnostics
#
# Usage: scripts/aws/validate_s3.sh -p PROFILE -b BUCKET -r REGION

PROFILE="default"
BUCKET=""
REGION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--profile) PROFILE="$2"; shift 2;;
    -b|--bucket) BUCKET="$2"; shift 2;;
    -r|--region) REGION="$2"; shift 2;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ -z "$BUCKET" || -z "$REGION" ]]; then
  echo "Usage: $0 -p PROFILE -b BUCKET -r REGION" >&2
  exit 2
fi

command -v aws >/dev/null 2>&1 || { echo "aws CLI not found" >&2; exit 127; }

echo "Checking identity for profile=$PROFILE..."
AWS_PROFILE="$PROFILE" aws sts get-caller-identity

echo "Listing bucket s3://$BUCKET (region=$REGION)..."
AWS_PROFILE="$PROFILE" aws s3 ls "s3://$BUCKET" --region "$REGION"

echo "Putting small test object..."
TMPFILE=$(mktemp)
echo "nova-s3-validation" > "$TMPFILE"
AWS_PROFILE="$PROFILE" aws s3 cp "$TMPFILE" "s3://$BUCKET/_health/s3_validation.txt" --region "$REGION"

echo "Fetching test object..."
AWS_PROFILE="$PROFILE" aws s3 cp "s3://$BUCKET/_health/s3_validation.txt" - --region "$REGION" | sed -n '1p'

echo "OK: S3 access validated."
rm -f "$TMPFILE"

