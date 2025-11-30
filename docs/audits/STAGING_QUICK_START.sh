#!/bin/bash
# Nova Staging 快速启动脚本
# 使用: chmod +x STAGING_QUICK_START.sh && ./STAGING_QUICK_START.sh

set -e

echo "🚀 Nova Staging 环境快速启动"
echo "======================================"
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. 检查前置条件
echo "📋 检查前置条件..."
command -v terraform &> /dev/null || { echo -e "${RED}❌ Terraform 未安装${NC}"; exit 1; }
command -v kubectl &> /dev/null || { echo -e "${RED}❌ kubectl 未安装${NC}"; exit 1; }
command -v aws &> /dev/null || { echo -e "${RED}❌ AWS CLI 未安装${NC}"; exit 1; }
echo -e "${GREEN}✓ 所有工具已安装${NC}"
echo ""

# 2. 确认 AWS 区域和账户
echo "🌍 验证 AWS 配置..."
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="ap-northeast-1"
echo -e "${GREEN}✓ AWS 账户: $AWS_ACCOUNT${NC}"
echo -e "${GREEN}✓ AWS 区域: $AWS_REGION${NC}"
echo ""

# 3. 创建 S3 后端
echo "📦 设置 Terraform S3 后端..."
cd terraform
if bash setup-s3-backend.sh; then
    echo -e "${GREEN}✓ S3 后端已创建${NC}"
else
    echo -e "${RED}❌ S3 后端创建失败${NC}"
    exit 1
fi
cd ..
echo ""

# 4. 初始化 Terraform
echo "⚙️  初始化 Terraform..."
cd terraform
if terraform init -backend-config=backend.hcl; then
    echo -e "${GREEN}✓ Terraform 已初始化${NC}"
else
    echo -e "${RED}❌ Terraform 初始化失败${NC}"
    exit 1
fi
cd ..
echo ""

# 5. 验证 EKS kubeconfig
echo "🔐 验证 EKS 连接..."
if aws eks update-kubeconfig \
    --name nova-staging-eks \
    --region ap-northeast-1 2>/dev/null; then
    echo -e "${GREEN}✓ EKS kubeconfig 已更新${NC}"
else
    echo -e "${YELLOW}⚠️  EKS 集群不存在，需要先创建${NC}"
    echo "   运行: terraform apply -var-file=staging.tfvars"
    exit 1
fi
echo ""

# 6. 创建 namespace
echo "📦 创建 Kubernetes namespace..."
if kubectl create namespace nova-staging 2>/dev/null || true; then
    echo -e "${GREEN}✓ nova-staging namespace 已创建/存在${NC}"
fi
echo ""

# 7. 检查 External Secrets Operator
echo "🔓 检查 External Secrets Operator..."
if kubectl get deployment -n external-secrets-system external-secrets &>/dev/null; then
    echo -e "${GREEN}✓ ESO 已安装${NC}"
else
    echo -e "${YELLOW}⚠️  ESO 未安装，安装中...${NC}"
    helm repo add external-secrets https://charts.external-secrets.io
    helm repo update
    helm install external-secrets \
        external-secrets/external-secrets \
        -n external-secrets-system \
        --create-namespace
    echo -e "${GREEN}✓ ESO 已安装${NC}"
fi
echo ""

# 8. 检查 AWS Secrets
echo "🔐 检查 AWS Secrets Manager..."
SECRETS_EXIST=0
for secret in "nova/staging/nova-db-credentials" "nova/staging/nova-clickhouse-credentials" "nova/staging/nova-jwt-keys"; do
    if aws secretsmanager describe-secret --secret-id "$secret" --region ap-northeast-1 2>/dev/null; then
        echo -e "${GREEN}✓ Secret 存在: $secret${NC}"
        SECRETS_EXIST=$((SECRETS_EXIST + 1))
    else
        echo -e "${YELLOW}⚠️  Secret 不存在: $secret${NC}"
    fi
done

if [ $SECRETS_EXIST -lt 3 ]; then
    echo ""
    echo -e "${YELLOW}⚠️  部分 secrets 缺失，需要手动创建${NC}"
    echo "   详见 STAGING_SETUP.md 第二步"
fi
echo ""

# 9. 部署 Staging 环境
echo "🚀 部署 Staging 应用..."
cd k8s/infrastructure
if kustomize build overlays/staging | kubectl apply -f -; then
    echo -e "${GREEN}✓ 应用已部署${NC}"
else
    echo -e "${RED}❌ 应用部署失败${NC}"
    exit 1
fi
cd ../..
echo ""

# 10. 等待 PostgreSQL 就绪
echo "⏳ 等待 PostgreSQL 启动 (最多 5 分钟)..."
if kubectl rollout status -n nova-staging statefulset/postgres --timeout=300s; then
    echo -e "${GREEN}✓ PostgreSQL 已就绪${NC}"
else
    echo -e "${YELLOW}⚠️  PostgreSQL 启动超时${NC}"
fi
echo ""

# 11. 等待数据库初始化完成
echo "⏳ 等待数据库初始化完成..."
if kubectl wait --for=condition=complete job/seed-data-init \
    -n nova-staging --timeout=300s 2>/dev/null; then
    echo -e "${GREEN}✓ 数据库初始化完成${NC}"
else
    echo -e "${YELLOW}⚠️  初始化 Job 未完成，查看日志:${NC}"
    echo "   kubectl logs -n nova-staging job/seed-data-init"
fi
echo ""

# 12. 显示部署摘要
echo "📊 部署摘要"
echo "======================================"
echo -e "${GREEN}✓ Staging 环境部署完成!${NC}"
echo ""
echo "📝 下一步:"
echo "   1. 验证服务状态:"
echo "      kubectl get all -n nova-staging"
echo ""
echo "   2. 查看 PostgreSQL 日志:"
echo "      kubectl logs postgres-0 -n nova-staging"
echo ""
echo "   3. 测试数据库连接:"
echo "      kubectl port-forward -n nova-staging svc/postgres 5432:5432 &"
echo "      psql -h localhost -U nova_staging -d nova_auth"
echo ""
echo "   4. 监控应用部署:"
echo "      kubectl get pods -n nova-staging -w"
echo ""
echo "📚 详细信息: 见 STAGING_SETUP.md"
