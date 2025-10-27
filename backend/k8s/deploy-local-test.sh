#!/bin/bash

# 简化的本地测试部署脚本

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_info "=== Nova 本地 Kubernetes 部署 ==="
log_info ""

# 1. 创建命名空间
log_info "1. 创建命名空间..."
kubectl create namespace nova-redis --ignore-already-exists 2>/dev/null || true
kubectl create namespace nova-database --ignore-already-exists 2>/dev/null || true
kubectl create namespace nova-services --ignore-already-exists 2>/dev/null || true
log_success "命名空间创建完成"

# 2. 部署 Redis Sentinel
log_info ""
log_info "2. 部署 Redis Sentinel..."
kubectl apply -f redis-sentinel-statefulset.yaml
log_success "Redis 配置已应用"

# 3. 部署 PostgreSQL HA
log_info ""
log_info "3. 部署 PostgreSQL HA..."
kubectl apply -f postgres-ha-statefulset.yaml
log_success "PostgreSQL 配置已应用"

# 4. 部署微服务
log_info ""
log_info "4. 部署 Secrets..."
kubectl apply -f microservices-secrets.yaml
log_success "Secrets 已应用"

# 等待基础设施准备就绪
log_info ""
log_info "等待 Redis 就绪 (最多 5 分钟)..."
kubectl wait --for=condition=ready pod -l app=redis -n nova-redis --timeout=300s 2>/dev/null || {
    log_error "Redis Pod 未就绪"
    kubectl describe pod -l app=redis -n nova-redis
    exit 1
}
log_success "Redis 已就绪"

log_info ""
log_info "等待 PostgreSQL 就绪 (最多 5 分钟)..."
kubectl wait --for=condition=ready pod -l app=postgres -n nova-database --timeout=300s 2>/dev/null || {
    log_error "PostgreSQL Pod 未就绪"
    kubectl describe pod -l app=postgres -n nova-database
    exit 1
}
log_success "PostgreSQL 已就绪"

# 显示部署状态
log_info ""
log_info "=== 部署完成 ==="
log_info ""
log_info "=== 资源状态 ==="
echo ""
echo "Redis 节点:"
kubectl get pod -n nova-redis -o wide
echo ""
echo "PostgreSQL 节点:"
kubectl get pod -n nova-database -o wide
echo ""

# 显示访问信息
log_info ""
log_info "=== 访问信息 ==="
echo "Redis Sentinel:"
echo "  kubectl port-forward svc/redis-sentinel 6379:6379 -n nova-redis"
echo ""
echo "PostgreSQL Primary:"
echo "  kubectl port-forward svc/postgres-primary 5432:5432 -n nova-database"
echo ""

log_success "部署完成！"
