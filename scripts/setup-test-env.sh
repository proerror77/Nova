#!/bin/bash
# Setup test environment for Nova staging API tests
# This script will:
# 1. Get a test user ID from database
# 2. Generate a JWT token for that user
# 3. Export environment variables for testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}Nova Staging Test Environment Setup${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# 1. Get database password
echo "1. Retrieving database credentials..."
DB_CREDS=$(aws secretsmanager get-secret-value \
    --secret-id nova/staging/nova-db-credentials \
    --region ap-northeast-1 \
    --query SecretString \
    --output text)
DB_PASS=$(echo "$DB_CREDS" | jq -r '.password')
echo -e "   ${GREEN}✓${NC} Database credentials retrieved"

# 2. Get test user from database
echo "2. Querying test user from database..."
USER_DATA=$(kubectl exec -n nova-staging statefulset/postgres -- \
    sh -c "PGPASSWORD='$DB_PASS' psql -U nova -d nova_auth -t -c \
    'SELECT id, username, email FROM users ORDER BY created_at DESC LIMIT 1;'")

export USER_ID=$(echo "$USER_DATA" | awk '{print $1}' | tr -d ' ')
export USERNAME=$(echo "$USER_DATA" | awk '{print $3}')
export EMAIL=$(echo "$USER_DATA" | awk '{print $5}')

echo -e "   ${GREEN}✓${NC} Test user found:"
echo "   User ID:  $USER_ID"
echo "   Username: $USERNAME"
echo "   Email:    $EMAIL"

# 3. Get JWT private key
echo "3. Retrieving JWT signing key..."
JWT_KEY=$(aws secretsmanager get-secret-value \
    --secret-id nova/staging/nova-jwt-keys \
    --region ap-northeast-1 \
    --query SecretString \
    --output text | jq -r '.JWT_PRIVATE_KEY_PEM')
echo "$JWT_KEY" > /tmp/jwt_private_key.pem
echo -e "   ${GREEN}✓${NC} JWT key saved to /tmp/jwt_private_key.pem"

# 4. Check if PyJWT is installed
if ! python3 -c "import jwt" 2>/dev/null; then
    echo -e "   ${YELLOW}⚠${NC} PyJWT not installed. Installing..."
    pip3 install -q pyjwt cryptography
fi

# 5. Generate JWT token
echo "4. Generating JWT token..."
export TOKEN=$(python3 "$SCRIPT_DIR/generate-test-jwt.py" "$USER_ID" /tmp/jwt_private_key.pem)
echo -e "   ${GREEN}✓${NC} JWT token generated (valid for 24 hours)"

# 6. Set gateway URL
export GW_BASE="http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com"

# 7. Save to file for easy sourcing
cat > /tmp/nova-test-env.sh << EOF
# Nova Staging Test Environment Variables
# Source this file: source /tmp/nova-test-env.sh
export GW_BASE="$GW_BASE"
export USER_ID="$USER_ID"
export USERNAME="$USERNAME"
export EMAIL="$EMAIL"
export TOKEN="$TOKEN"
EOF

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Setup Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Environment variables set:"
echo "  GW_BASE=$GW_BASE"
echo "  USER_ID=$USER_ID"
echo "  TOKEN=${TOKEN:0:50}..."
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Source the environment file:"
echo "     ${GREEN}source /tmp/nova-test-env.sh${NC}"
echo ""
echo "  2. Run the smoke test:"
echo "     ${GREEN}./scripts/staging-smoke-test.sh${NC}"
echo ""
echo "  3. Or test manually:"
echo "     ${GREEN}curl -H \"Authorization: Bearer \$TOKEN\" \$GW_BASE/api/v2/channels${NC}"
echo ""
