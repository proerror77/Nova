#!/bin/bash

# mTLS Certificate Generation Script
# Based on Codex P0 recommendation for service-to-service authentication
#
# This script generates:
# - Root CA certificate
# - Server certificates for each service
# - Client certificates for service-to-service communication

set -e

CERT_DIR="./certs"
VALIDITY_DAYS=365
KEY_SIZE=4096

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}🔐 Generating mTLS certificates for Nova microservices${NC}"

# Create certificate directory
mkdir -p $CERT_DIR/{ca,services,clients}

# Generate Root CA
echo -e "${YELLOW}Generating Root CA...${NC}"
openssl req -x509 -new -nodes \
    -newkey rsa:$KEY_SIZE \
    -days $VALIDITY_DAYS \
    -keyout $CERT_DIR/ca/ca.key \
    -out $CERT_DIR/ca/ca.crt \
    -subj "/C=US/ST=CA/L=SF/O=Nova/OU=Infrastructure/CN=Nova Root CA"

# Services list (based on V2 architecture)
SERVICES=(
    "identity-service"
    "user-service"
    "content-service"
    "social-service"
    "media-service"
    "communication-service"
    "search-service"
    "events-service"
    "graphql-gateway"
)

# Generate server certificates for each service
for SERVICE in "${SERVICES[@]}"; do
    echo -e "${YELLOW}Generating certificate for $SERVICE...${NC}"

    # Create service directory
    mkdir -p $CERT_DIR/services/$SERVICE

    # Generate private key
    openssl genrsa -out $CERT_DIR/services/$SERVICE/server.key $KEY_SIZE

    # Generate certificate signing request
    openssl req -new \
        -key $CERT_DIR/services/$SERVICE/server.key \
        -out $CERT_DIR/services/$SERVICE/server.csr \
        -subj "/C=US/ST=CA/L=SF/O=Nova/OU=$SERVICE/CN=$SERVICE.nova.svc.cluster.local"

    # Create SAN extension file for Kubernetes service DNS
    cat > $CERT_DIR/services/$SERVICE/san.ext <<EOF
subjectAltName=DNS:$SERVICE,DNS:$SERVICE.nova,DNS:$SERVICE.nova.svc,DNS:$SERVICE.nova.svc.cluster.local,DNS:localhost,IP:127.0.0.1
EOF

    # Sign the certificate with CA
    openssl x509 -req \
        -in $CERT_DIR/services/$SERVICE/server.csr \
        -CA $CERT_DIR/ca/ca.crt \
        -CAkey $CERT_DIR/ca/ca.key \
        -CAcreateserial \
        -out $CERT_DIR/services/$SERVICE/server.crt \
        -days $VALIDITY_DAYS \
        -sha256 \
        -extfile $CERT_DIR/services/$SERVICE/san.ext

    # Generate client certificate for this service
    echo -e "${YELLOW}Generating client certificate for $SERVICE...${NC}"

    mkdir -p $CERT_DIR/clients/$SERVICE

    # Generate client private key
    openssl genrsa -out $CERT_DIR/clients/$SERVICE/client.key $KEY_SIZE

    # Generate client CSR
    openssl req -new \
        -key $CERT_DIR/clients/$SERVICE/client.key \
        -out $CERT_DIR/clients/$SERVICE/client.csr \
        -subj "/C=US/ST=CA/L=SF/O=Nova/OU=$SERVICE-client/CN=$SERVICE-client"

    # Sign client certificate
    openssl x509 -req \
        -in $CERT_DIR/clients/$SERVICE/client.csr \
        -CA $CERT_DIR/ca/ca.crt \
        -CAkey $CERT_DIR/ca/ca.key \
        -CAcreateserial \
        -out $CERT_DIR/clients/$SERVICE/client.crt \
        -days $VALIDITY_DAYS \
        -sha256

    # Clean up CSR files
    rm $CERT_DIR/services/$SERVICE/server.csr
    rm $CERT_DIR/clients/$SERVICE/client.csr
    rm $CERT_DIR/services/$SERVICE/san.ext
done

# Create Kubernetes secrets YAML
echo -e "${YELLOW}Generating Kubernetes secrets...${NC}"

cat > $CERT_DIR/k8s-tls-secrets.yaml <<'EOF'
# mTLS Secrets for Nova Microservices
# Deploy with: kubectl apply -f k8s-tls-secrets.yaml -n nova

apiVersion: v1
kind: Namespace
metadata:
  name: nova
---
apiVersion: v1
kind: Secret
metadata:
  name: ca-cert
  namespace: nova
type: Opaque
data:
  ca.crt: $(cat $CERT_DIR/ca/ca.crt | base64 | tr -d '\n')
EOF

for SERVICE in "${SERVICES[@]}"; do
    cat >> $CERT_DIR/k8s-tls-secrets.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: $SERVICE-tls
  namespace: nova
type: kubernetes.io/tls
data:
  tls.crt: $(cat $CERT_DIR/services/$SERVICE/server.crt | base64 | tr -d '\n')
  tls.key: $(cat $CERT_DIR/services/$SERVICE/server.key | base64 | tr -d '\n')
---
apiVersion: v1
kind: Secret
metadata:
  name: $SERVICE-client-tls
  namespace: nova
type: Opaque
data:
  client.crt: $(cat $CERT_DIR/clients/$SERVICE/client.crt | base64 | tr -d '\n')
  client.key: $(cat $CERT_DIR/clients/$SERVICE/client.key | base64 | tr -d '\n')
EOF
done

# Generate cert-manager resources for automatic renewal
cat > $CERT_DIR/cert-manager-config.yaml <<'EOF'
# Cert-manager configuration for automatic certificate renewal
# Install cert-manager first: kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml

apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: nova-ca-issuer
  namespace: cert-manager
spec:
  ca:
    secretName: ca-key-pair
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: nova-services-tls
  namespace: nova
spec:
  secretName: nova-services-tls
  duration: 8760h # 1 year
  renewBefore: 720h # 30 days
  issuerRef:
    name: nova-ca-issuer
    kind: ClusterIssuer
  commonName: "*.nova.svc.cluster.local"
  dnsNames:
  - "*.nova.svc.cluster.local"
  - "*.nova.svc"
  - "*.nova"
EOF

echo -e "${GREEN}✅ mTLS certificates generated successfully!${NC}"
echo -e "${GREEN}Files created in: $CERT_DIR${NC}"
echo ""
echo "Next steps:"
echo "1. Review certificates in $CERT_DIR"
echo "2. Deploy to Kubernetes: kubectl apply -f $CERT_DIR/k8s-tls-secrets.yaml"
echo "3. Configure services to use TLS certificates"
echo "4. Install cert-manager for automatic renewal"