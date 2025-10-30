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
    print_header "部署RBAC配置"

    kubectl apply -f "$SCRIPT_DIR/messaging-service-serviceaccount.yaml"
    print_success "ServiceAccount 和 Role 已部署"
    echo ""
}

# Deploy ConfigMap and Secret
deploy_config() {
    print_header "部署配置和密钥"

    kubectl apply -f "$SCRIPT_DIR/messaging-service-configmap-local.yaml"
    print_success "ConfigMap (本地) 已部署"

    kubectl apply -f "$SCRIPT_DIR/messaging-service-secret-local.yaml"
    print_success "Secret (本地) 已部署"
    echo ""
}

# Build Docker image
build_image() {
    print_header "构建Docker镜像"

    if [ ! -f "$SCRIPT_DIR/../../messaging-service/Cargo.toml" ]; then
        print_warning "找不到Cargo.toml，跳过构建"
        echo "请确保您位于正确的目录中，或手动构建镜像:"
        echo "  cd backend/messaging-service"
        echo "  docker build -t nova/messaging-service:latest -f ../Dockerfile.messaging ."
        return
    fi

    print_warning "正在构建镜像，这可能需要2-5分钟..."
    cd "$SCRIPT_DIR/../../messaging-service"

    if docker build -t nova/messaging-service:latest -f ../Dockerfile.messaging .; then
        print_success "镜像构建成功"
    else
        print_error "镜像构建失败"
        exit 1
    fi

    cd "$SCRIPT_DIR"
    echo ""
}

# Load image to kind (if using kind)
load_kind_image() {
    CLUSTER_NAME=$(kubectl config current-context)

    if [[ "$CLUSTER_NAME" == *"kind"* ]]; then
        print_header "加载镜像到kind"

        if kind load docker-image nova/messaging-service:latest --name "${CLUSTER_NAME#kind-}"; then
            print_success "镜像已加载到kind集群"
        else
            print_warning "镜像加载失败，请手动运行:"
            echo "  kind load docker-image nova/messaging-service:latest --name ${CLUSTER_NAME#kind-}"
        fi
        echo ""
    fi
}

# Deploy application
deploy_app() {
    print_header "部署应用"

    kubectl apply -f "$SCRIPT_DIR/messaging-service-deployment-local.yaml"
    print_success "Deployment 已部署"

    # Create simple service
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: messaging-service
  namespace: $NAMESPACE
  labels:
    app: nova
    component: messaging-service
spec:
  type: NodePort
  ports:
    - name: http
      port: 3000
      targetPort: 3000
      nodePort: 30000
    - name: metrics
      port: 9090
      targetPort: 9090
      nodePort: 30090
  selector:
    app: nova
    component: messaging-service
EOF

    print_success "Service 已创建"
    echo ""
}

# Wait for deployment
wait_deployment() {
    print_header "等待部署完成"

    echo "监控Pod启动... (Ctrl+C 停止)"
    kubectl rollout status deployment/messaging-service -n $NAMESPACE --timeout=300s || {
        print_error "部署超时或失败"
        echo "查看Pod状态："
        kubectl get pods -n $NAMESPACE
        echo "查看日志："
        kubectl logs -l component=messaging-service -n $NAMESPACE --tail=20
        return 1
    }

    print_success "部署完成！"
    echo ""
}

# Show access information
show_access_info() {
    print_header "访问信息"

    CONTEXT=$(kubectl config current-context)
    echo "当前K8s环境: $CONTEXT"
    echo ""

    echo "服务端点:"
    if [[ "$CONTEXT" == *"kind"* ]]; then
        echo "  API: http://localhost:30000"
        echo "  Metrics: http://localhost:30090"
    else
        echo "  使用端口转发:"
        echo "    kubectl port-forward svc/messaging-service 3000:3000"
        echo "    kubectl port-forward svc/messaging-service 9090:9090"
        echo ""
        echo "  然后访问:"
        echo "    API: http://localhost:3000"
        echo "    Metrics: http://localhost:9090/metrics"
    fi
    echo ""
}

# Show verification commands
show_verification_commands() {
    print_header "验证命令"

    echo "1️⃣ 检查Pod状态:"
    echo "   kubectl get pods -n $NAMESPACE -w"
    echo ""

    echo "2️⃣ 查看日志:"
    echo "   kubectl logs -f -l component=messaging-service -n $NAMESPACE"
    echo ""

    echo "3️⃣ 测试健康检查:"
    echo "   # 需要先运行端口转发或NodePort"
    echo "   curl http://localhost:3000/health"
    echo "   curl http://localhost:3000/health | jq"
    echo ""

    echo "4️⃣ 进入Pod调试:"
    echo "   kubectl exec -it <pod-name> -n $NAMESPACE -- bash"
    echo ""

    echo "5️⃣ 查看资源使用:"
    echo "   kubectl top pods -n $NAMESPACE"
    echo ""

    echo "6️⃣ 查看完整事件:"
    echo "   kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
    echo ""
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
