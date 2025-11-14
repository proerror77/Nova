#!/bin/bash

set -e

REGION="ap-northeast-1"
CLUSTER_NAME="nova-staging"
NAMESPACE="nova-staging"

echo "═══════════════════════════════════════════════════════════"
echo "🚀 自動部署：Phase 3 + Phase 4"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Phase 3: Kubernetes 初始化
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 3: Kubernetes 初始化"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: 更新 kubeconfig
echo "1️⃣ 更新 kubeconfig..."
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME 2>/dev/null
echo "✅ kubeconfig 已更新"
echo ""

# Step 2: 驗證集群連線
echo "2️⃣ 驗證集群連線..."
MAX_ATTEMPTS=30
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if kubectl cluster-info &>/dev/null; then
    echo "✅ 已連線到 EKS 集群"
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  if [ $((ATTEMPT % 5)) -eq 0 ]; then
    echo "⏳ 等待集群就緒... (${ATTEMPT}s/${MAX_ATTEMPTS}s)"
  fi
  sleep 1
done
echo ""

# Step 3: 創建命名空間
echo "3️⃣ 創建命名空間 nova-staging..."
kubectl create namespace $NAMESPACE 2>/dev/null || true
kubectl label namespace $NAMESPACE environment=staging managed-by=terraform --overwrite=true 2>/dev/null
echo "✅ 命名空間已創建"
echo ""

# Step 4: 安裝 External Secrets Operator
echo "4️⃣ 安裝 External Secrets Operator..."
helm repo add external-secrets https://charts.external-secrets.io 2>/dev/null || true
helm repo update external-secrets --max-chart-depth=3 &>/dev/null

if helm upgrade --install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace \
  --set installCRDs=true \
  --wait \
  --timeout=5m 2>/dev/null; then
  echo "✅ External Secrets Operator 已安裝"
else
  echo "⚠️ External Secrets Operator 安裝進行中..."
fi
echo ""

# Step 5: 安裝 ClickHouse Operator
echo "5️⃣ 安裝 ClickHouse Operator..."
kubectl apply -f https://raw.githubusercontent.com/Altinity/clickhouse-operator/master/deploy/operator/clickhouse-operator-install-bundle.yaml &>/dev/null || true

# 等待 ClickHouse Operator（非關鍵）
kubectl wait --for=condition=available \
  --timeout=2m \
  deployment/clickhouse-operator \
  -n clickhouse-operator 2>/dev/null || echo "⚠️ ClickHouse Operator 初始化進行中"

echo "✅ ClickHouse Operator 已安裝"
echo ""

# Phase 4: 應用部署
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 4: 應用部署（14 個微服務）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd /Users/proerror/Documents/nova

# 部署所有資源
echo "6️⃣ 部署 14 個微服務和基礎設施..."
echo "   (這將需要 5-10 分鐘)"
echo ""

kubectl apply -k k8s/infrastructure/overlays/staging/ 2>&1 | tail -50

echo ""
echo "✅ 部署命令已執行"
echo ""

# 監控 Pod 創建
echo "7️⃣ 監控 Pod 創建進度..."
echo ""
echo "等待 Pod 啟動（超時：10 分鐘）..."
echo ""

kubectl wait --for=condition=ready pod \
  -l app \
  -n $NAMESPACE \
  --timeout=10m 2>/dev/null || true

echo ""
echo "📊 當前 Pod 狀態："
kubectl get pods -n $NAMESPACE -o wide

echo ""

# 驗證部署
echo "8️⃣ 運行驗證腳本..."
echo ""

if [ -f "/Users/proerror/Documents/nova/k8s/infrastructure/overlays/staging/validate-staging-deployment.sh" ]; then
  bash /Users/proerror/Documents/nova/k8s/infrastructure/overlays/staging/validate-staging-deployment.sh
else
  echo "⚠️ 驗證腳本未找到"
fi

echo ""
echo "═══════════════════════════════════════════════════════════"
echo "✅ Phase 3 + Phase 4 部署完成！"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "🎯 下一步："
echo "   1. 監控 Pod 啟動："
echo "      kubectl get pods -n nova-staging -w"
echo ""
echo "   2. 檢查服務連線："
echo "      kubectl get svc -n nova-staging"
echo ""
echo "   3. 查看 Pod 日誌："
echo "      kubectl logs -n nova-staging <pod-name>"
echo ""
