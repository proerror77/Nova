#!/bin/bash

# 監控 EKS 部署進度

echo "🔍 監控 Terraform Apply 進度..."
echo ""

# 每 30 秒檢查一次
for i in {1..60}; do
  echo -n "[$i/60] 檢查進度... "

  # 檢查 EKS 集群是否存在
  if aws eks describe-cluster --name nova-staging --region ap-northeast-1 &>/dev/null; then
    echo "✅ EKS 集群已創建！"
    echo ""
    echo "集群信息："
    aws eks describe-cluster --name nova-staging --region ap-northeast-1 \
      --query 'cluster.{Name:name,Status:status,Version:version,Endpoint:endpoint}' \
      --output table
    echo ""
    echo "🚀 可以開始 Phase 3 了！"
    echo "執行命令："
    echo "  bash /Users/proerror/Documents/nova/phase-3-k8s-init.sh"
    exit 0
  else
    echo "⏳ 仍在創建中..."
    sleep 30
  fi
done

echo ""
echo "⏱️  EKS 集群創建超時（30分鐘）"
echo "請手動檢查："
echo "  aws eks describe-cluster --name nova-staging --region ap-northeast-1"
