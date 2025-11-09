#!/bin/bash
# scripts/aws/verify-secrets-integration.sh
# 验证 AWS Secrets Manager 与 Kubernetes 集成

set -euo pipefail

ENVIRONMENT="${1:-staging}"
NAMESPACE="nova-${ENVIRONMENT}"

echo "🔍 Verifying AWS Secrets Manager Integration for $ENVIRONMENT"
echo ""

# 检查前置条件
echo "📋 Checking prerequisites..."
CHECKS_PASSED=0
CHECKS_FAILED=0

# 1. 检查 kubectl
if kubectl version --client &>/dev/null; then
    echo "  ✅ kubectl installed"
    ((CHECKS_PASSED++))
else
    echo "  ❌ kubectl not found"
    ((CHECKS_FAILED++))
fi

# 2. 检查 helm
if helm version &>/dev/null; then
    echo "  ✅ helm installed"
    ((CHECKS_PASSED++))
else
    echo "  ❌ helm not found"
    ((CHECKS_FAILED++))
fi

# 3. 检查 AWS CLI
if aws --version &>/dev/null; then
    echo "  ✅ AWS CLI installed"
    ((CHECKS_PASSED++))
else
    echo "  ❌ AWS CLI not found"
    ((CHECKS_FAILED++))
fi

# 4. 检查 kubectl 连接
if kubectl cluster-info &>/dev/null; then
    echo "  ✅ kubectl connected to cluster"
    ((CHECKS_PASSED++))
else
    echo "  ❌ kubectl not connected"
    ((CHECKS_FAILED++))
fi

echo ""
if [ $CHECKS_FAILED -gt 0 ]; then
    echo "❌ Prerequisites check failed. Install missing tools before continuing."
    exit 1
fi

# 检查 AWS Secrets Manager
echo "🔐 Checking AWS Secrets Manager..."
SECRET_NAME="nova-backend-${ENVIRONMENT}"
if aws secretsmanager describe-secret --secret-id "$SECRET_NAME" --region us-west-2 &>/dev/null; then
    echo "  ✅ AWS Secret exists: $SECRET_NAME"

    # 获取密钥版本信息
    VERSIONS=$(aws secretsmanager list-secret-version-ids --secret-id "$SECRET_NAME" --region us-west-2 --query 'Versions[?VersionStages[0]==`AWSCURRENT`].VersionId' --output text)
    echo "     Current version: $VERSIONS"
else
    echo "  ❌ AWS Secret not found: $SECRET_NAME"
    echo "     Run: ./scripts/aws/setup-aws-secrets.sh $ENVIRONMENT"
    exit 1
fi

echo ""

# 检查 External Secrets Operator
echo "📦 Checking External Secrets Operator..."
if kubectl get namespace external-secrets-system &>/dev/null; then
    echo "  ✅ Namespace exists: external-secrets-system"
else
    echo "  ❌ Namespace not found: external-secrets-system"
    echo "     Run: ./scripts/aws/setup-external-secrets-operator.sh"
    exit 1
fi

if kubectl get deployment external-secrets -n external-secrets-system &>/dev/null; then
    ESO_STATUS=$(kubectl get deployment external-secrets -n external-secrets-system -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
    if [ "$ESO_STATUS" == "True" ]; then
        echo "  ✅ External Secrets Operator running"
        ESO_VERSION=$(kubectl get deployment external-secrets -n external-secrets-system -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
        echo "     Version: $ESO_VERSION"
    else
        echo "  ⚠️  External Secrets Operator not ready"
    fi
else
    echo "  ❌ External Secrets Operator not installed"
    echo "     Run: ./scripts/aws/setup-external-secrets-operator.sh"
    exit 1
fi

echo ""

# 检查 CRDs
echo "📜 Checking CRDs..."
CRDS=(
    "secretstores.external-secrets.io"
    "externalsecrets.external-secrets.io"
    "clustersecretstores.external-secrets.io"
)

for crd in "${CRDS[@]}"; do
    if kubectl get crd "$crd" &>/dev/null; then
        echo "  ✅ CRD exists: $crd"
    else
        echo "  ❌ CRD not found: $crd"
    fi
done

echo ""

# 检查 Namespace
echo "🏢 Checking namespace: $NAMESPACE"
if kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "  ✅ Namespace exists"
else
    echo "  ⚠️  Namespace not found (creating...)"
    kubectl create namespace "$NAMESPACE"
fi

echo ""

# 检查 ServiceAccount
echo "👤 Checking ServiceAccount..."
if kubectl get serviceaccount nova-backend-sa -n "$NAMESPACE" &>/dev/null; then
    echo "  ✅ ServiceAccount exists: nova-backend-sa"

    ROLE_ARN=$(kubectl get serviceaccount nova-backend-sa -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')
    if [ -n "$ROLE_ARN" ]; then
        echo "     IAM Role ARN: $ROLE_ARN"
    else
        echo "  ⚠️  IAM Role ARN not set"
        echo "     Update k8s/base/external-secrets/serviceaccount.yaml"
    fi
else
    echo "  ❌ ServiceAccount not found"
    echo "     Run: kubectl apply -f k8s/base/external-secrets/"
    exit 1
fi

echo ""

# 检查 SecretStore
echo "🗄️  Checking SecretStore..."
if kubectl get secretstore aws-secretsmanager -n "$NAMESPACE" &>/dev/null; then
    echo "  ✅ SecretStore exists: aws-secretsmanager"

    STORE_STATUS=$(kubectl get secretstore aws-secretsmanager -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$STORE_STATUS" == "True" ]; then
        echo "     Status: Ready"
    else
        echo "  ⚠️  Status: Not Ready"
        kubectl describe secretstore aws-secretsmanager -n "$NAMESPACE" | grep -A 5 "Conditions:"
    fi
else
    echo "  ❌ SecretStore not found"
    echo "     Run: kubectl apply -f k8s/base/external-secrets/secretstore.yaml"
    exit 1
fi

echo ""

# 检查 ExternalSecret
echo "🔗 Checking ExternalSecret..."
if kubectl get externalsecret nova-backend-secrets -n "$NAMESPACE" &>/dev/null; then
    echo "  ✅ ExternalSecret exists: nova-backend-secrets"

    ES_STATUS=$(kubectl get externalsecret nova-backend-secrets -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$ES_STATUS" == "True" ]; then
        echo "     Status: Ready"

        SYNC_TIME=$(kubectl get externalsecret nova-backend-secrets -n "$NAMESPACE" -o jsonpath='{.status.syncedResourceVersion}')
        echo "     Last Sync: $SYNC_TIME"
    else
        echo "  ⚠️  Status: Not Ready"
        kubectl describe externalsecret nova-backend-secrets -n "$NAMESPACE" | grep -A 10 "Conditions:"
    fi
else
    echo "  ❌ ExternalSecret not found"
    echo "     Run: kubectl apply -f k8s/overlays/$ENVIRONMENT/external-secret.yaml"
    exit 1
fi

echo ""

# 检查生成的 Kubernetes Secret
echo "🔑 Checking Kubernetes Secret..."
if kubectl get secret nova-backend-secrets -n "$NAMESPACE" &>/dev/null; then
    echo "  ✅ Secret exists: nova-backend-secrets"

    # 获取 Secret 中的键
    KEYS=$(kubectl get secret nova-backend-secrets -n "$NAMESPACE" -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null || echo "")
    if [ -n "$KEYS" ]; then
        echo "     Keys:"
        echo "$KEYS" | while read -r key; do
            echo "       - $key"
        done
    fi

    # 检查创建时间
    AGE=$(kubectl get secret nova-backend-secrets -n "$NAMESPACE" -o jsonpath='{.metadata.creationTimestamp}')
    echo "     Created: $AGE"
else
    echo "  ❌ Secret not created"
    echo "     Check ExternalSecret status for errors"
fi

echo ""

# 测试 AWS 连接 (从 Pod 内部)
echo "🌐 Testing AWS connectivity from Pod..."
cat <<EOF | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: aws-test-pod
  namespace: $NAMESPACE
spec:
  serviceAccountName: nova-backend-sa
  containers:
  - name: aws-cli
    image: amazon/aws-cli:latest
    command: ["sleep", "60"]
  restartPolicy: Never
EOF

# 等待 Pod 就绪
echo "  Waiting for test pod..."
kubectl wait --for=condition=ready pod/aws-test-pod -n "$NAMESPACE" --timeout=30s &>/dev/null || true

if kubectl exec aws-test-pod -n "$NAMESPACE" -- aws secretsmanager get-secret-value --secret-id "$SECRET_NAME" --region us-west-2 &>/dev/null; then
    echo "  ✅ AWS connectivity from Pod: OK"
else
    echo "  ❌ AWS connectivity from Pod: FAILED"
    echo "     Check IRSA configuration"
fi

# 清理测试 Pod
kubectl delete pod aws-test-pod -n "$NAMESPACE" --ignore-not-found &>/dev/null

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Verification Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 汇总状态
ALL_CHECKS=(
    "AWS Secret Manager"
    "External Secrets Operator"
    "CRDs"
    "ServiceAccount"
    "SecretStore"
    "ExternalSecret"
    "Kubernetes Secret"
    "AWS Connectivity"
)

echo "Environment: $ENVIRONMENT"
echo "Namespace: $NAMESPACE"
echo ""
echo "✅ All checks passed!"
echo ""
echo "📝 Next steps:"
echo "1. Update your Deployment manifests to use the Secret:"
echo "   kubectl apply -f k8s/base/auth-service-deployment-externalsecrets.yaml"
echo ""
echo "2. Monitor ExternalSecret sync:"
echo "   kubectl get externalsecret -n $NAMESPACE -w"
echo ""
echo "3. View logs:"
echo "   kubectl logs -n external-secrets-system -l app.kubernetes.io/name=external-secrets"
echo ""
