#!/bin/bash
# Security Quick Start Script for Nova Backend
# Generates certificates, creates secrets, and validates security configuration

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NAMESPACE="${NAMESPACE:-nova-backend}"
CERT_DIR="${CERT_DIR:-./certs}"

echo -e "${GREEN}=== Nova Backend Security Quick Start ===${NC}\n"

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."

    command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}❌ kubectl not found${NC}"; exit 1; }
    command -v openssl >/dev/null 2>&1 || { echo -e "${RED}❌ openssl not found${NC}"; exit 1; }

    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        echo -e "${YELLOW}Creating namespace $NAMESPACE...${NC}"
        kubectl create namespace "$NAMESPACE"
    fi

    echo -e "${GREEN}✅ Prerequisites OK${NC}\n"
}

# Generate JWT keys
generate_jwt_keys() {
    echo "Generating JWT RSA key pair (4096-bit)..."

    mkdir -p "$CERT_DIR"

    # Generate private key
    openssl genrsa -out "$CERT_DIR/jwt-private.pem" 4096 2>/dev/null

    # Extract public key
    openssl rsa -in "$CERT_DIR/jwt-private.pem" -pubout -out "$CERT_DIR/jwt-public.pem" 2>/dev/null

    # Verify key strength
    KEY_BITS=$(openssl rsa -in "$CERT_DIR/jwt-private.pem" -text -noout 2>/dev/null | grep "Private-Key" | grep -o "[0-9]*")

    if [ "$KEY_BITS" -eq 4096 ]; then
        echo -e "${GREEN}✅ JWT keys generated (4096-bit RSA)${NC}"
    else
        echo -e "${RED}❌ Key generation failed${NC}"
        exit 1
    fi

    # Create Kubernetes secret
    kubectl create secret generic jwt-keys \
        --from-file=private-key="$CERT_DIR/jwt-private.pem" \
        --from-file=public-key="$CERT_DIR/jwt-public.pem" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${GREEN}✅ JWT keys secret created${NC}\n"
}

# Generate TLS certificates
generate_tls_certs() {
    echo "Generating TLS certificates for gRPC..."

    # CA certificate
    echo "  Generating CA certificate..."
    openssl req -x509 -newkey rsa:4096 -days 3650 -nodes \
        -keyout "$CERT_DIR/ca-key.pem" -out "$CERT_DIR/ca-cert.pem" \
        -subj "/CN=Nova Internal CA/O=Nova/C=US" 2>/dev/null

    # Server certificate
    echo "  Generating server certificate..."
    openssl req -newkey rsa:4096 -nodes \
        -keyout "$CERT_DIR/server-key.pem" -out "$CERT_DIR/server-req.pem" \
        -subj "/CN=*.nova-backend.svc.cluster.local/O=Nova" 2>/dev/null

    # Create SAN config
    cat > "$CERT_DIR/san.cnf" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name

[req_distinguished_name]

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = *.nova-backend.svc.cluster.local
DNS.2 = localhost
IP.1 = 127.0.0.1
EOF

    # Sign server certificate
    openssl x509 -req -in "$CERT_DIR/server-req.pem" -days 365 \
        -CA "$CERT_DIR/ca-cert.pem" -CAkey "$CERT_DIR/ca-key.pem" -CAcreateserial \
        -out "$CERT_DIR/server-cert.pem" \
        -extfile "$CERT_DIR/san.cnf" -extensions v3_req 2>/dev/null

    # Client certificate (for mTLS)
    echo "  Generating client certificate..."
    openssl req -newkey rsa:4096 -nodes \
        -keyout "$CERT_DIR/client-key.pem" -out "$CERT_DIR/client-req.pem" \
        -subj "/CN=nova-client/O=Nova" 2>/dev/null

    openssl x509 -req -in "$CERT_DIR/client-req.pem" -days 365 \
        -CA "$CERT_DIR/ca-cert.pem" -CAkey "$CERT_DIR/ca-key.pem" -CAcreateserial \
        -out "$CERT_DIR/client-cert.pem" 2>/dev/null

    echo -e "${GREEN}✅ TLS certificates generated${NC}"

    # Create Kubernetes secrets
    kubectl create secret tls grpc-server-tls \
        --cert="$CERT_DIR/server-cert.pem" \
        --key="$CERT_DIR/server-key.pem" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    kubectl create secret generic grpc-ca-cert \
        --from-file=ca.crt="$CERT_DIR/ca-cert.pem" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    kubectl create secret tls grpc-client-tls \
        --cert="$CERT_DIR/client-cert.pem" \
        --key="$CERT_DIR/client-key.pem" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${GREEN}✅ TLS secrets created${NC}\n"
}

# Setup CORS configuration
setup_cors() {
    echo "Setting up CORS configuration..."

    read -p "Enter allowed origins (comma-separated, e.g., https://nova.example.com): " ORIGINS

    if [ -z "$ORIGINS" ]; then
        echo -e "${YELLOW}⚠️  Using default development origins${NC}"
        ORIGINS="http://localhost:3000,http://localhost:3001"
    fi

    # Validate no wildcards
    if [[ "$ORIGINS" == *"*"* ]]; then
        echo -e "${RED}❌ Wildcard origins not allowed for security${NC}"
        exit 1
    fi

    kubectl create configmap cors-config \
        --from-literal=CORS_ALLOWED_ORIGINS="$ORIGINS" \
        --from-literal=CORS_ALLOW_CREDENTIALS="true" \
        --from-literal=CORS_MAX_AGE="3600" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${GREEN}✅ CORS configuration created${NC}\n"
}

# Deploy Redis for rate limiting
deploy_redis() {
    echo "Deploying Redis for rate limiting and token blacklist..."

    # Check if Helm is installed
    if ! command -v helm &> /dev/null; then
        echo -e "${YELLOW}⚠️  Helm not found, skipping Redis deployment${NC}"
        echo "  Install Redis manually and create 'redis' secret with URL"
        return
    fi

    # Generate Redis password
    REDIS_PASSWORD=$(openssl rand -base64 32)

    # Deploy Redis using Helm
    helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
    helm repo update

    helm upgrade --install redis bitnami/redis \
        --set auth.password="$REDIS_PASSWORD" \
        --set master.persistence.enabled=true \
        --set master.persistence.size=5Gi \
        --namespace="$NAMESPACE" \
        --wait \
        --timeout=5m || {
        echo -e "${YELLOW}⚠️  Redis deployment failed or timed out${NC}"
        echo "  You may need to deploy Redis manually"
        return
    }

    # Create Redis URL secret
    REDIS_URL="redis://:${REDIS_PASSWORD}@redis-master.${NAMESPACE}.svc.cluster.local:6379"
    kubectl create secret generic redis \
        --from-literal=password="$REDIS_PASSWORD" \
        --from-literal=url="$REDIS_URL" \
        --namespace="$NAMESPACE" \
        --dry-run=client -o yaml | kubectl apply -f -

    echo -e "${GREEN}✅ Redis deployed and configured${NC}\n"
}

# Validate security configuration
validate_security() {
    echo "Validating security configuration..."

    ERRORS=0

    # Check secrets
    echo "  Checking secrets..."
    if ! kubectl get secret jwt-keys -n "$NAMESPACE" &>/dev/null; then
        echo -e "${RED}    ❌ JWT keys secret missing${NC}"
        ERRORS=$((ERRORS + 1))
    fi

    if ! kubectl get secret grpc-server-tls -n "$NAMESPACE" &>/dev/null; then
        echo -e "${RED}    ❌ gRPC server TLS secret missing${NC}"
        ERRORS=$((ERRORS + 1))
    fi

    if ! kubectl get secret grpc-ca-cert -n "$NAMESPACE" &>/dev/null; then
        echo -e "${RED}    ❌ gRPC CA cert secret missing${NC}"
        ERRORS=$((ERRORS + 1))
    fi

    if ! kubectl get configmap cors-config -n "$NAMESPACE" &>/dev/null; then
        echo -e "${RED}    ❌ CORS config missing${NC}"
        ERRORS=$((ERRORS + 1))
    fi

    # Check certificate validity
    echo "  Checking certificate validity..."
    kubectl get secret grpc-server-tls -n "$NAMESPACE" -o jsonpath='{.data.tls\.crt}' | \
        base64 -d | \
        openssl x509 -checkend 2592000 -noout || {
        echo -e "${YELLOW}    ⚠️  Server certificate expires within 30 days${NC}"
    }

    if [ $ERRORS -eq 0 ]; then
        echo -e "${GREEN}✅ Security validation passed${NC}\n"
    else
        echo -e "${RED}❌ Security validation failed with $ERRORS errors${NC}\n"
        exit 1
    fi
}

# Print summary
print_summary() {
    echo -e "${GREEN}=== Security Setup Complete ===${NC}\n"

    echo "Generated files in $CERT_DIR/:"
    echo "  - jwt-private.pem, jwt-public.pem (JWT keys)"
    echo "  - ca-cert.pem, ca-key.pem (CA certificate)"
    echo "  - server-cert.pem, server-key.pem (Server TLS)"
    echo "  - client-cert.pem, client-key.pem (Client mTLS)"
    echo ""

    echo "Created Kubernetes resources:"
    echo "  - Secret: jwt-keys (JWT RSA keys)"
    echo "  - Secret: grpc-server-tls (Server certificate)"
    echo "  - Secret: grpc-ca-cert (CA certificate)"
    echo "  - Secret: grpc-client-tls (Client certificate)"
    echo "  - ConfigMap: cors-config (CORS settings)"
    if kubectl get secret redis -n "$NAMESPACE" &>/dev/null; then
        echo "  - Secret: redis (Redis credentials)"
    fi
    echo ""

    echo -e "${YELLOW}⚠️  IMPORTANT SECURITY NOTES:${NC}"
    echo "  1. Store private keys securely (DO NOT commit to git)"
    echo "  2. Rotate JWT keys every 90 days"
    echo "  3. Monitor certificate expiration"
    echo "  4. Review CORS origins for production"
    echo "  5. Enable Redis persistence in production"
    echo ""

    echo "Next steps:"
    echo "  1. Deploy services with security configuration:"
    echo "     kubectl apply -f k8s/microservices/"
    echo ""
    echo "  2. Verify deployment:"
    echo "     ./scripts/security-check.sh"
    echo ""
    echo "  3. Review documentation:"
    echo "     - docs/SECURITY_DEPLOYMENT_GUIDE.md"
    echo "     - docs/SECURITY_COMPLIANCE_CHECKLIST.md"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    generate_jwt_keys
    generate_tls_certs
    setup_cors
    deploy_redis
    validate_security
    print_summary
}

main "$@"
