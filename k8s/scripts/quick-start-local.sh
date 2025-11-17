#!/bin/bash

# Nova Messaging Service - Local Kubernetes Quick Start
# 本地K8s快速启动脚本

set -e

NAMESPACE="nova-messaging"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_header "检查前提条件"

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl 未安装"
        echo "请安装 kubectl: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi
    print_success "kubectl 已安装 ($(kubectl version --client --short))"

    # Check docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装"
        echo "请安装 Docker: https://www.docker.com/get-started/"
        exit 1
    fi
    print_success "Docker 已安装 ($(docker --version))"

    # Check K8s cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "K8s集群不可用"
        echo "请启动本地K8s集群:"
        echo "  1. Docker Desktop: 设置 → Kubernetes → 启用"
        echo "  2. Minikube: minikube start --driver=docker"
        echo "  3. kind: kind create cluster"
        exit 1
    fi
    print_success "K8s集群正在运行"

    # Show cluster info
    echo "集群信息:"
    kubectl cluster-info | head -1
    echo ""
}

# Create namespace
create_namespace() {
    print_header "创建命名空间"

    if kubectl get ns $NAMESPACE &> /dev/null; then
        print_warning "命名空间 $NAMESPACE 已存在"
    else
        kubectl create namespace $NAMESPACE
        print_success "命名空间 $NAMESPACE 已创建"
    fi

    # Set as default
    kubectl config set-context --current --namespace=$NAMESPACE
    print_success "设置默认命名空间为 $NAMESPACE"
    echo ""
}

# Deploy RBAC
deploy_rbac() {
    print_header "部署RBAC配置 (messaging-service 已淘汰，請改用 realtime-chat-service 專用腳本)"
}

# Deploy ConfigMap and Secret
deploy_config() {
    print_header "部署配置和密钥 (messaging-service 已淘汰，請改用 realtime-chat-service 專用腳本)"
}

# Build Docker image
build_image() {
    print_header "构建Docker镜像 (messaging-service 已淘汰，本脚本僅保留為歷史記錄，不再執行實際構建)"
}

# Load image to kind (if using kind)
load_kind_image() {
    print_header "加载镜像到kind (messaging-service 已淘汰，略過)"
}

# Deploy application
deploy_app() {
    print_header "部署应用 (messaging-service 已淘汰，請改用 realtime-chat-service 的部署腳本)"
}

# Wait for deployment
wait_deployment() {
    print_header "等待部署完成 (messaging-service 已淘汰)"
}

# Show access information
show_access_info() {
    print_header "访问信息 (messaging-service 已淘汰，請改用 realtime-chat-service 的端點)"
}

# Show verification commands
show_verification_commands() {
    print_header "验证命令 (messaging-service 已淘汰，請改用 realtime-chat-service 的驗證流程)"
}

# Cleanup function
cleanup() {
    print_header "清理"

    read -p "确定要删除 $NAMESPACE 命名空间吗? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete namespace $NAMESPACE
        print_success "命名空间已删除"
    fi
}

# Main menu
main_menu() {
    while true; do
        echo ""
        echo -e "${BLUE}=== Nova Messaging Service 本地验证 ===${NC}"
        echo ""
        echo "选择操作:"
        echo "1) 完整部署 (检查 → 部署RBAC → 部署配置 → 构建镜像 → 部署应用)"
        echo "2) 仅检查前提条件"
        echo "3) 查看状态"
        echo "4) 查看日志"
        echo "5) 进行端口转发"
        echo "6) 运行验证命令"
        echo "7) 清理环境"
        echo "8) 退出"
        echo ""

        read -p "请选择 (1-8): " choice

        case $choice in
            1)
                check_prerequisites
                create_namespace
                deploy_rbac
                deploy_config
                build_image
                load_kind_image
                deploy_app
                wait_deployment
                show_access_info
                show_verification_commands
                ;;
            2)
                check_prerequisites
                ;;
            3)
                print_header "Pod状态"
                kubectl get pods -n $NAMESPACE
                echo ""
                print_header "服务状态"
                kubectl get svc -n $NAMESPACE
                echo ""
                ;;
            4)
                print_header "应用日志"
                kubectl logs -f -l component=messaging-service -n $NAMESPACE --tail=50 || echo "没有Pod运行"
                ;;
            5)
                print_header "启动端口转发"
                echo "转发端口3000和9090..."
                echo "按 Ctrl+C 停止"
                kubectl port-forward svc/messaging-service 3000:3000 9090:9090 -n $NAMESPACE
                ;;
            6)
                show_verification_commands
                ;;
            7)
                cleanup
                ;;
            8)
                echo "退出"
                exit 0
                ;;
            *)
                print_error "无效选择"
                ;;
        esac
    done
}

# Script entry point
if [ $# -eq 0 ]; then
    # Interactive mode
    main_menu
else
    # Command line mode
    case "$1" in
        deploy)
            check_prerequisites
            create_namespace
            deploy_rbac
            deploy_config
            build_image
            load_kind_image
            deploy_app
            wait_deployment
            show_access_info
            ;;
        check)
            check_prerequisites
            ;;
        cleanup)
            cleanup
            ;;
        *)
            echo "用法: $0 [deploy|check|cleanup]"
            echo "或直接运行 $0 进入交互式菜单"
            ;;
    esac
fi
