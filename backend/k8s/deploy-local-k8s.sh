#!/bin/bash

# ============================================================================
# 本地 Kubernetes 部署腳本 (Minikube / Kind)
# ============================================================================
# 使用說明：
#   ./deploy-local-k8s.sh deploy    # 部署所有資源
#   ./deploy-local-k8s.sh cleanup   # 清理所有資源
#   ./deploy-local-k8s.sh status    # 查看部署狀態
#   ./deploy-local-k8s.sh logs      # 查看日誌
# ============================================================================

set -e

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
KUBECONFIG="${KUBECONFIG:-$(kubectl config view --raw 2>/dev/null | grep current-context)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 日誌函數
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 檢查前置條件
check_prerequisites() {
    log_info "檢查前置條件..."

    # 檢查 kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl 未安裝"
        exit 1
    fi

    # 檢查 Kubernetes 連接
    if ! kubectl cluster-info &> /dev/null; then
        log_error "無法連接到 Kubernetes 集群"
        log_info "請確保 Minikube 或 Kind 正在運行："
        echo "  Minikube: minikube start"
        echo "  Kind: kind create cluster --name=nova"
        exit 1
    fi

    # 檢查集群節點數
    local node_count=$(kubectl get nodes -o jsonpath='{.items | length}')
    log_info "集群有 $node_count 個節點"

    if [ "$node_count" -lt 3 ]; then
        log_warning "建議至少 3 個節點以實現 Pod 反親和性"
    fi

    log_success "前置條件檢查完畢"
}

# 創建命名空間
create_namespaces() {
    log_info "創建命名空間..."

    kubectl create namespace nova-redis --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace nova-database --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace nova-services --dry-run=client -o yaml | kubectl apply -f -

    log_success "命名空間創建完畢"
}

# 部署 Redis Sentinel
deploy_redis() {
    log_info "部署 Redis Sentinel..."

    # 檢查文件存在
    if [ ! -f "$SCRIPT_DIR/redis-sentinel-statefulset.yaml" ]; then
        log_error "找不到 redis-sentinel-statefulset.yaml"
        return 1
    fi

    kubectl apply -f "$SCRIPT_DIR/redis-sentinel-statefulset.yaml"

    log_info "等待 Redis 啟動..."
    kubectl wait --for=condition=ready pod -l app=redis -n nova-redis --timeout=300s 2>/dev/null || true

    log_success "Redis Sentinel 部署完畢"
}

# 部署 PostgreSQL
deploy_postgres() {
    log_info "部署 PostgreSQL..."

    if [ ! -f "$SCRIPT_DIR/postgres-ha-statefulset.yaml" ]; then
        log_error "找不到 postgres-ha-statefulset.yaml"
        return 1
    fi

    kubectl apply -f "$SCRIPT_DIR/postgres-ha-statefulset.yaml"

    log_info "等待 PostgreSQL 啟動..."
    kubectl wait --for=condition=ready pod -l app=postgres -n nova-database --timeout=300s 2>/dev/null || true

    log_success "PostgreSQL 部署完畢"
}

# 部署微服務
deploy_microservices() {
    log_info "部署微服務..."

    # 部署 Secrets
    if [ ! -f "$SCRIPT_DIR/microservices-secrets.yaml" ]; then
        log_error "找不到 microservices-secrets.yaml"
        return 1
    fi

    log_info "  應用 Secrets..."
    kubectl apply -f "$SCRIPT_DIR/microservices-secrets.yaml"

    # 部署 Deployments
    if [ ! -f "$SCRIPT_DIR/microservices-deployments.yaml" ]; then
        log_error "找不到 microservices-deployments.yaml"
        return 1
    fi

    log_info "  應用 Deployments..."
    kubectl apply -f "$SCRIPT_DIR/microservices-deployments.yaml"

    log_info "等待微服務啟動..."
    kubectl wait --for=condition=ready pod -l component=social -n nova-services --timeout=300s 2>/dev/null || true

    log_success "微服務部署完畢"
}

# 驗證部署
verify_deployment() {
    log_info "驗證部署狀態..."

    echo ""
    log_info "Redis 狀態："
    kubectl get pods -n nova-redis -o wide

    echo ""
    log_info "PostgreSQL 狀態："
    kubectl get pods -n nova-database -o wide

    echo ""
    log_info "微服務狀態："
    kubectl get pods -n nova-services -o wide

    echo ""
    log_info "服務狀態："
    kubectl get svc -n nova-services

    log_success "驗證完畢"
}

# 顯示部署信息
show_info() {
    log_info "部署完成！"

    echo ""
    echo "================================"
    echo "  連接信息"
    echo "================================"

    # Redis Sentinel
    local redis_service=$(kubectl get svc -n nova-redis redis-sentinel --no-headers 2>/dev/null | awk '{print $3}')
    echo "Redis Sentinel: $redis_service:26379"

    # PostgreSQL
    local postgres_service=$(kubectl get svc -n nova-database postgres-primary --no-headers 2>/dev/null | awk '{print $3}')
    echo "PostgreSQL: $postgres_service:5432"

    # 微服務
    echo ""
    echo "微服務（ClusterIP）："
    kubectl get svc -n nova-services --no-headers | awk '{print "  " $1 ": " $3 ":" $5}' | sed 's/\/TCP.*//'

    echo ""
    echo "================================"
    echo "  常用命令"
    echo "================================"
    echo "查看日誌："
    echo "  kubectl logs -f -l app=user-service -n nova-services"
    echo ""
    echo "進入 Pod："
    echo "  kubectl exec -it <pod-name> -n nova-services -- /bin/sh"
    echo ""
    echo "端口轉發 (本地訪問)："
    echo "  kubectl port-forward svc/user-service 8080:8080 -n nova-services"
    echo ""
    echo "刪除部署："
    echo "  $0 cleanup"
    echo ""
}

# 清理資源
cleanup() {
    log_warning "準備清理所有資源..."
    read -p "確認清理？(y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "已取消"
        return
    fi

    log_info "刪除微服務命名空間..."
    kubectl delete namespace nova-services --ignore-not-found=true

    log_info "刪除數據庫命名空間..."
    kubectl delete namespace nova-database --ignore-not-found=true

    log_info "刪除 Redis 命名空間..."
    kubectl delete namespace nova-redis --ignore-not-found=true

    log_success "清理完畢"
}

# 顯示狀態
show_status() {
    echo ""
    echo "================================"
    echo "  Redis 狀態"
    echo "================================"
    kubectl get all -n nova-redis

    echo ""
    echo "================================"
    echo "  PostgreSQL 狀態"
    echo "================================"
    kubectl get all -n nova-database

    echo ""
    echo "================================"
    echo "  微服務狀態"
    echo "================================"
    kubectl get all -n nova-services
}

# 顯示日誌
show_logs() {
    local component=${1:-user-service}
    log_info "顯示 $component 日誌..."

    kubectl logs -f -l app=$component -n nova-services --tail=50 --timestamps=true 2>/dev/null || \
        log_error "找不到 $component，請指定有效的服務名"
}

# 幫助信息
show_help() {
    cat << EOF
使用說明：
  $0 [command]

命令：
  deploy      - 部署所有資源到本地 Kubernetes
  cleanup     - 清理所有資源
  status      - 顯示部署狀態
  logs [app]  - 查看應用日誌 (默認: user-service)
  help        - 顯示此幫助信息

例子：
  $0 deploy
  $0 status
  $0 logs auth-service
  $0 cleanup

環境變量：
  KUBECONFIG - Kubernetes 配置文件路徑

EOF
}

# 主函數
main() {
    local command=${1:-help}

    case "$command" in
        deploy)
            check_prerequisites
            create_namespaces
            deploy_redis
            deploy_postgres
            deploy_microservices
            verify_deployment
            show_info
            ;;
        cleanup)
            cleanup
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "$2"
            ;;
        help)
            show_help
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

# 運行
main "$@"
