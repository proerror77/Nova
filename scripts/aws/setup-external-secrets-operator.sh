#!/bin/bash
# scripts/aws/setup-external-secrets-operator.sh
# 安装和配置 External Secrets Operator

set -euo pipefail

NAMESPACE="${NAMESPACE:-external-secrets-system}"
RELEASE_NAME="${RELEASE_NAME:-external-secrets}"

echo "🚀 Installing External Secrets Operator"
echo "   Namespace: $NAMESPACE"
echo "   Release: $RELEASE_NAME"
echo ""

# 添加 Helm repo
echo "📦 Adding Helm repository..."
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# 安装 External Secrets Operator
echo "⚙️  Installing External Secrets Operator..."
helm upgrade --install "$RELEASE_NAME" \
    external-secrets/external-secrets \
    --namespace "$NAMESPACE" \
    --create-namespace \
    --set installCRDs=true \
    --set webhook.port=9443 \
    --set certController.create=true \
    --wait

echo ""
echo "✅ External Secrets Operator installed successfully!"
echo ""

# 验证安装
echo "🔍 Verifying installation..."
kubectl get pods -n "$NAMESPACE"
echo ""

# 检查 CRD
echo "📋 Checking CRDs..."
kubectl get crd | grep external-secrets
echo ""

echo "✅ Setup complete!"
echo ""
echo "📝 Next steps:"
echo "1. Apply SecretStore:"
echo "   kubectl apply -f k8s/base/external-secrets/secretstore.yaml"
echo ""
echo "2. Apply ExternalSecret for staging:"
echo "   kubectl apply -f k8s/overlays/staging/external-secret.yaml"
echo ""
echo "3. Verify secret creation:"
echo "   kubectl get externalsecrets -n nova-staging"
echo "   kubectl get secrets -n nova-staging"
echo ""
