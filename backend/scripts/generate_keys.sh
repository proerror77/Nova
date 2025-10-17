#!/bin/bash

# Generate RSA keypair for JWT signing (RS256)
# Keys should be stored in secure location (AWS Secrets Manager, HashiCorp Vault, etc.)

KEYS_DIR="backend/keys"

# Create keys directory if it doesn't exist
mkdir -p "$KEYS_DIR"

# Generate private key (4096-bit for production security)
openssl genrsa -out "$KEYS_DIR/private_key.pem" 4096

# Extract public key from private key
openssl rsa -in "$KEYS_DIR/private_key.pem" -pubout -out "$KEYS_DIR/public_key.pem"

# Verify keys were created
if [ -f "$KEYS_DIR/private_key.pem" ] && [ -f "$KEYS_DIR/public_key.pem" ]; then
    echo "✅ RSA keypair generated successfully"
    echo "📁 Private key: $KEYS_DIR/private_key.pem"
    echo "📁 Public key: $KEYS_DIR/public_key.pem"
    echo ""
    echo "⚠️  IMPORTANT: In production, store these keys in:"
    echo "   - AWS Secrets Manager"
    echo "   - HashiCorp Vault"
    echo "   - Azure Key Vault"
    echo "   - Never commit to git!"
else
    echo "❌ Failed to generate keys"
    exit 1
fi
