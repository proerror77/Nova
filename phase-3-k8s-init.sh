#!/bin/bash

set -e

REGION="ap-northeast-1"
CLUSTER_NAME="nova-staging"
NAMESPACE="nova-staging"

echo "═══════════════════════════════════════════════════════════"
echo "🚀 Phase 3: Kubernetes 初始化"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Step 1: 驗證 EKS 集群就緒
echo "1️⃣ 驗證 EKS 集群連線..."
echo ""

MAX_ATTEMPTS=60
ATTEMPT=0

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if kubectl cluster-info &>/dev/null; then
    echo "✅ EKS 集群已連線！"
    echo "   API Server: $(kubectl cluster-info 2>/dev/null | grep 'Kubernetes master' | head -1)"
    break
  else
    ATTEMPT=$((ATTEMPT + 1))
    if [ $((ATTEMPT % 10)) -eq 0 ]; then
      echo "⏳ 等待集群就緒... (${ATTEMPT}s/${MAX_ATTEMPTS}s)"
    fi
    sleep 1
  fi
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
  echo "❌ EKS 集群連線超時"
  exit 1
fi

echo ""
echo "2️⃣ 創建 nova-staging 命名空間..."
kubectl create namespace $NAMESPACE 2>/dev/null || true
kubectl label namespace $NAMESPACE environment=staging managed-by=terraform --overwrite=true

echo "✅ 命名空間已創建"
echo ""

# Step 2: 安裝 Helm
echo "3️⃣ 安裝 Helm 依賴..."
echo ""

# External Secrets Operator
echo "   📦 安裝 External Secrets Operator..."
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update external-secrets --max-chart-depth=3 &>/dev/null

helm upgrade --install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --set installCRDs=true \
  --wait \
  --timeout=5m &>/dev/null

echo "   ✅ External Secrets Operator 已安裝"

echo ""

# ClickHouse Operator
echo "   📦 安裝 ClickHouse Operator..."
kubectl apply -f https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml &>/dev/null

# 等待 ClickHouse Operator 就緒
kubectl wait --for=condition=available \
  --timeout=5m \
  deployment/clickhouse-operator \
  -n clickhouse-operator 2>/dev/null || true

echo "   ✅ ClickHouse Operator 已安裝"
echo ""

# Step 3: 驗證 Kubernetes 就緒
echo "4️⃣ 驗證集群配置..."
echo ""

echo "   📊 集群信息:"
kubectl cluster-info 2>/dev/null | grep -E "Kubernetes master|CoreDNS" || true

echo ""
echo "   📦 節點狀態:"
kubectl get nodes -o wide

echo ""
echo "   💾 存儲類:"
kubectl get storageclass

echo ""
echo "5️⃣ 驗證命名空間和服務帳戶..."
kubectl get serviceaccount -n $NAMESPACE

echo ""

echo "═══════════════════════════════════════════════════════════"
echo "✅ Phase 3 完成！Kubernetes 已初始化"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "🎯 下一步："
echo "   1. 運行 Phase 4 應用部署："
echo "      kubectl apply -k k8s/infrastructure/overlays/staging/"
echo ""
echo "   2. 監控 Pod 創建："
echo "      kubectl get pods -n nova-staging -w"
echo ""
echo "   3. 運行驗證腳本："
echo "      bash k8s/infrastructure/overlays/staging/validate-staging-deployment.sh"
echo ""
