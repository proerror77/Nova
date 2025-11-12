#!/bin/bash
##
## Production mTLS Certificate Generation Script
##
## This script generates a complete CA and signed certificates for production use.
## WARNING: Store private keys securely and never commit them to version control!
##
## Usage:
##   ./generate-production-certs.sh <output-dir> <domain-name>
##
## Example:
##   ./generate-production-certs.sh ./certs auth-service.nova.internal
##

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -ne 2 ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    echo "Usage: $0 <output-dir> <domain-name>"
    echo "Example: $0 ./certs auth-service.nova.internal"
    exit 1
fi

OUTPUT_DIR="$1"
DOMAIN_NAME="$2"
VALIDITY_DAYS=365

echo -e "${GREEN}=== Nova mTLS Production Certificate Generation ===${NC}"
echo "Output directory: $OUTPUT_DIR"
echo "Domain name: $DOMAIN_NAME"
echo "Validity: $VALIDITY_DAYS days"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# 1. Generate CA Certificate
echo -e "${YELLOW}[1/5] Generating CA certificate...${NC}"
openssl req -x509 -newkey rsa:4096 -nodes \
  -keyout "$OUTPUT_DIR/ca-key.pem" \
  -out "$OUTPUT_DIR/ca-cert.pem" \
  -days $VALIDITY_DAYS \
  -subj "/CN=Nova Production CA/O=Nova/OU=Infrastructure" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,digitalSignature,keyCertSign,cRLSign"

echo -e "${GREEN}✓ CA certificate generated${NC}"

# 2. Generate Server Certificate Request
echo -e "${YELLOW}[2/5] Generating server certificate request...${NC}"
openssl req -newkey rsa:4096 -nodes \
  -keyout "$OUTPUT_DIR/server-key.pem" \
  -out "$OUTPUT_DIR/server-req.pem" \
  -subj "/CN=$DOMAIN_NAME/O=Nova/OU=Services"

echo -e "${GREEN}✓ Server CSR generated${NC}"

# 3. Sign Server Certificate with CA
echo -e "${YELLOW}[3/5] Signing server certificate...${NC}"
cat > "$OUTPUT_DIR/server-ext.cnf" <<EOF
subjectAltName=DNS:$DOMAIN_NAME,DNS:*.$DOMAIN_NAME,DNS:localhost,IP:127.0.0.1
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
EOF

openssl x509 -req \
  -in "$OUTPUT_DIR/server-req.pem" \
  -CA "$OUTPUT_DIR/ca-cert.pem" \
  -CAkey "$OUTPUT_DIR/ca-key.pem" \
  -CAcreateserial \
  -out "$OUTPUT_DIR/server-cert.pem" \
  -days $VALIDITY_DAYS \
  -extfile "$OUTPUT_DIR/server-ext.cnf"

echo -e "${GREEN}✓ Server certificate signed${NC}"

# 4. Generate Client Certificate Request
echo -e "${YELLOW}[4/5] Generating client certificate request...${NC}"
openssl req -newkey rsa:4096 -nodes \
  -keyout "$OUTPUT_DIR/client-key.pem" \
  -out "$OUTPUT_DIR/client-req.pem" \
  -subj "/CN=nova-client/O=Nova/OU=Services"

echo -e "${GREEN}✓ Client CSR generated${NC}"

# 5. Sign Client Certificate with CA
echo -e "${YELLOW}[5/5] Signing client certificate...${NC}"
cat > "$OUTPUT_DIR/client-ext.cnf" <<EOF
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
EOF

openssl x509 -req \
  -in "$OUTPUT_DIR/client-req.pem" \
  -CA "$OUTPUT_DIR/ca-cert.pem" \
  -CAkey "$OUTPUT_DIR/ca-key.pem" \
  -CAcreateserial \
  -out "$OUTPUT_DIR/client-cert.pem" \
  -days $VALIDITY_DAYS \
  -extfile "$OUTPUT_DIR/client-ext.cnf"

echo -e "${GREEN}✓ Client certificate signed${NC}"

# Cleanup temporary files
rm -f "$OUTPUT_DIR/server-req.pem" "$OUTPUT_DIR/client-req.pem"
rm -f "$OUTPUT_DIR/server-ext.cnf" "$OUTPUT_DIR/client-ext.cnf"
rm -f "$OUTPUT_DIR/ca-cert.srl"

# Set secure permissions
chmod 600 "$OUTPUT_DIR"/*-key.pem
chmod 644 "$OUTPUT_DIR"/*-cert.pem

echo ""
echo -e "${GREEN}=== Certificate Generation Complete ===${NC}"
echo ""
echo "Generated files:"
echo "  CA:     $OUTPUT_DIR/ca-cert.pem (public)"
echo "  CA Key: $OUTPUT_DIR/ca-key.pem (KEEP SECRET!)"
echo ""
echo "  Server Cert: $OUTPUT_DIR/server-cert.pem"
echo "  Server Key:  $OUTPUT_DIR/server-key.pem (KEEP SECRET!)"
echo ""
echo "  Client Cert: $OUTPUT_DIR/client-cert.pem"
echo "  Client Key:  $OUTPUT_DIR/client-key.pem (KEEP SECRET!)"
echo ""
echo -e "${YELLOW}Security Warnings:${NC}"
echo "  1. NEVER commit private keys (*-key.pem) to version control"
echo "  2. Store private keys in secure secret management (AWS Secrets Manager, Vault)"
echo "  3. Rotate certificates before expiration (recommended: every 90 days)"
echo "  4. Use different certificates for each service in production"
echo ""
echo -e "${GREEN}Verification:${NC}"
echo "  View certificate: openssl x509 -in $OUTPUT_DIR/server-cert.pem -text -noout"
echo "  Verify signature: openssl verify -CAfile $OUTPUT_DIR/ca-cert.pem $OUTPUT_DIR/server-cert.pem"
echo ""
