#!/bin/bash

set -e

echo "════════════════════════════════════════════════════"
echo "  Nova Staging 部署脚本"
echo "════════════════════════════════════════════════════"
echo ""

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. 检查节点就绪
echo -e "${YELLOW}1️⃣  检查 EKS 节点就绪...${NC}"
NODE_STATUS=$(aws eks describe-nodegroup --cluster-name nova-eks --nodegroup-name nova-nodes-staging --query 'nodegroup.status' --output text)

if [ "$NODE_STATUS" != "ACTIVE" ]; then
  echo -e "${RED}❌ 节点组还未就绪（状态: $NODE_STATUS）${NC}"
  echo "请稍候后重新运行此脚本"
  exit 1
fi

echo -e "${GREEN}✅ 节点组已就绪${NC}"

# 2. 等待节点加入集群
echo ""
echo -e "${YELLOW}2️⃣  等待节点加入 Kubernetes 集群...${NC}"

aws eks update-kubeconfig --name nova-eks --region ap-northeast-1 --quiet

sleep 10

NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
echo -e "${GREEN}✅ 发现 $NODES 个节点${NC}"
kubectl get nodes

# 3. 创建命名空间
echo ""
echo -e "${YELLOW}3️⃣  创建 Kubernetes 命名空间...${NC}"
kubectl create namespace nova-production --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
echo -e "${GREEN}✅ 命名空间就绪${NC}"

# 4. 部署微服务
echo ""
echo -e "${YELLOW}4️⃣  部署 Nova 微服务...${NC}"
cd /Users/proerror/Documents/nova/k8s

# 应用 Kustomize 部署
kubectl apply -k . -n nova-production

echo -e "${GREEN}✅ 部署命令已提交${NC}"

# 5. 等待 Pod 就绪
echo ""
echo -e "${YELLOW}5️⃣  等待 Pod 启动（这需要 1-2 分钟）...${NC}"

sleep 30

echo ""
echo "=== Pod 状态 ==="
kubectl get pods -n nova-production --watch &
WATCH_PID=$!

# 等待 30 秒然后显示统计
sleep 30
kill $WATCH_PID 2>/dev/null || true

echo ""
echo "=== Pod 统计 ==="
TOTAL=$(kubectl get pods -n nova-production --no-headers 2>/dev/null | wc -l)
RUNNING=$(kubectl get pods -n nova-production --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)

echo "总数: $TOTAL | 运行中: $RUNNING"

# 6. 显示服务信息
echo ""
echo -e "${YELLOW}6️⃣  服务信息${NC}"
echo ""
echo "=== Kubernetes Services ==="
kubectl get svc -n nova-production

echo ""
echo "=== Ingress ==="
kubectl get ingress -n nova-production || echo "未配置 Ingress"

echo ""
echo "════════════════════════════════════════════════════"
echo -e "${GREEN}🎉 部署完成！${NC}"
echo "════════════════════════════════════════════════════"
echo ""
echo "检查 Pod 日志："
echo "  kubectl logs -n nova-production <pod-name>"
echo ""
echo "监看实时 Pod 状态："
echo "  kubectl get pods -n nova-production -w"
echo ""
echo "检查所有资源："
echo "  kubectl get all -n nova-production"
