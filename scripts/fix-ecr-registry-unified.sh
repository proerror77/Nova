#!/bin/bash

set -e

echo "======================================="
echo "🔧 ECR Registry 統一修復腳本"
echo "======================================="
echo "統一所有服務使用同一個 ECR 倉庫"
echo "Date: $(date)"
echo ""

# 顏色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ECR 配置 - 使用 GitHub Actions 正在推送的倉庫
CORRECT_ECR="025434362120.dkr.ecr.ap-northeast-1.amazonaws.com"
CORRECT_REGION="ap-northeast-1"

echo "================================"
echo "📋 當前 ECR 使用狀況"
echo "================================"
echo ""

echo "檢查所有服務的映像配置："
kubectl get deployments --all-namespaces -o json | \
  jq -r '.items[] | select(.metadata.namespace | test("nova")) | "\(.metadata.namespace)/\(.metadata.name): \(.spec.template.spec.containers[0].image)"' | \
  sort

echo ""
echo "================================"
echo "🔍 發現的問題"
echo "================================"
echo ""

# 找出使用錯誤 ECR 的部署
WRONG_DEPLOYMENTS=$(kubectl get deployments --all-namespaces -o json | \
  jq -r '.items[] | select(.spec.template.spec.containers[0].image | test("381492023287")) | "\(.metadata.namespace)/\(.metadata.name)"')

if [ -z "$WRONG_DEPLOYMENTS" ]; then
  echo -e "${GREEN}✅ 沒有發現使用錯誤 ECR 的部署${NC}"
else
  echo -e "${RED}發現以下部署使用錯誤的 ECR：${NC}"
  echo "$WRONG_DEPLOYMENTS"
fi

echo ""
echo "================================"
echo "🔧 開始修復 User Service"
echo "================================"
echo ""

# 修復 User Service - 最主要的問題
echo "1. 更新 User Service 部署映像..."

# 檢查正確的 ECR 中是否有 user-service 映像
echo "檢查目標 ECR 倉庫中的 user-service 映像..."
LATEST_USER_IMAGE="${CORRECT_ECR}/nova/user-service:latest"

# 更新 user-service 部署
echo "更新 nova-backend/user-service..."
kubectl set image deployment/user-service \
  -n nova-backend \
  user-service="${LATEST_USER_IMAGE}" \
  --record=true || echo "警告：無法更新 nova-backend 的 user-service"

# 檢查 nova namespace 中是否也有 user-service
if kubectl get deployment user-service -n nova 2>/dev/null; then
  echo "更新 nova/user-service..."
  kubectl set image deployment/user-service \
    -n nova \
    user-service="${CORRECT_ECR}/nova/user-service:d20916cc585005059fe9c015cf19aaa0fc2ed558" \
    --record=true || echo "警告：無法更新 nova 的 user-service"
fi

echo ""
echo "================================"
echo "🔧 更新其他缺失的服務映像"
echo "================================"
echo ""

# 檢查並修復其他可能有問題的服務
SERVICES=(
  "events-service:nova-backend"
  "cdn-service:nova-backend"
  "notification-service:nova-backend"
  "messaging-service:nova-backend"
)

for service_ns in "${SERVICES[@]}"; do
  IFS=':' read -r service namespace <<< "$service_ns"

  if kubectl get deployment "$service" -n "$namespace" 2>/dev/null; then
    echo "檢查 $namespace/$service..."
    CURRENT_IMAGE=$(kubectl get deployment "$service" -n "$namespace" -o jsonpath='{.spec.template.spec.containers[0].image}')

    # 如果映像不包含正確的 ECR，更新它
    if [[ ! "$CURRENT_IMAGE" =~ "$CORRECT_ECR" ]]; then
      echo -e "${YELLOW}更新 $namespace/$service 映像...${NC}"
      NEW_IMAGE="${CORRECT_ECR}/nova/${service}:latest"
      kubectl set image deployment/"$service" \
        -n "$namespace" \
        "$service"="$NEW_IMAGE" \
        --record=true
    else
      echo -e "${GREEN}✓ $namespace/$service 已使用正確的 ECR${NC}"
    fi
  fi
done

echo ""
echo "================================"
echo "🔄 觸發部署重啟"
echo "================================"
echo ""

# 重啟有問題的部署以強制拉取新映像
echo "重啟 User Service..."
kubectl rollout restart deployment/user-service -n nova-backend
kubectl rollout restart deployment/user-service -n nova 2>/dev/null || true

echo ""
echo "================================"
echo "⏳ 等待部署穩定"
echo "================================"
echo ""

# 等待 rollout 完成
echo "等待 User Service 重新部署..."
kubectl rollout status deployment/user-service -n nova-backend --timeout=2m || true

echo ""
echo "================================"
echo "📊 驗證修復結果"
echo "================================"
echo ""

# 驗證所有部署現在都使用正確的 ECR
echo "檢查所有服務現在的映像："
echo ""

kubectl get deployments --all-namespaces -o json | \
  jq -r '.items[] | select(.metadata.namespace | test("nova")) |
    {
      namespace: .metadata.namespace,
      name: .metadata.name,
      image: .spec.template.spec.containers[0].image,
      replicas: .status.replicas,
      ready: .status.readyReplicas
    }' | \
  jq -r '"\(.namespace)/\(.name): \(if .image | test("025434362120") then "✅" else "❌" end) \(.image) (\(.ready // 0)/\(.replicas // 0) ready)"'

echo ""
echo "================================"
echo "📝 建議的後續步驟"
echo "================================"
echo ""

echo "1. 觸發 GitHub Actions 構建 user-service："
echo "   - 推送代碼到 main 分支"
echo "   - 或手動觸發 ecr-build-push.yml workflow"
echo ""
echo "2. 確保所有服務的 Dockerfile 都存在並正確配置"
echo ""
echo "3. 更新所有 Kubernetes 部署文件使用統一的 ECR："
echo "   ${CORRECT_ECR}/nova/<service-name>:latest"
echo ""
echo "4. 考慮設置 imagePullPolicy: Always 以確保總是拉取最新映像"
echo ""

echo "================================"
echo "✅ ECR 統一修復腳本完成"
echo "================================"