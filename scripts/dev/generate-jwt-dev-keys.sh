#!/usr/bin/env bash
set -euo pipefail

# Generate RSA key pair for local development and output base64 one-line env values

OUT_DIR=${1:-".dev-keys"}
mkdir -p "$OUT_DIR"

PRIV_PEM="$OUT_DIR/jwt_private.pem"
PUB_PEM="$OUT_DIR/jwt_public.pem"

echo "Generating RSA 2048-bit key pair into $OUT_DIR ..."
openssl genrsa -out "$PRIV_PEM" 2048 >/dev/null 2>&1
openssl rsa -in "$PRIV_PEM" -pubout -out "$PUB_PEM" >/dev/null 2>&1

echo ""
echo "Base64-encoded values (single-line) to paste into your .env:" 

# macOS/Linux compatible base64 to single line
PRIV_B64=$(base64 < "$PRIV_PEM" | tr -d '\n')
PUB_B64=$(base64 < "$PUB_PEM" | tr -d '\n')

cat <<EOF
JWT_PRIVATE_KEY_PEM=$PRIV_B64
JWT_PUBLIC_KEY_PEM=$PUB_B64
EOF

echo ""
echo "Files generated:" 
echo "  - $PRIV_PEM"
echo "  - $PUB_PEM"
echo ""
echo "Next:" 
echo "  1) Create .env (or .env.dev) in repo root if missing"
echo "  2) Paste the two lines above into the file"
echo "  3) docker-compose --env-file .env up -d user-service"

