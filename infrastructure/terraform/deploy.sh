#!/bin/bash

# ============================================================================
# Nova EKS Infrastructure Deployment Script
# ============================================================================
# 用法: ./deploy.sh [init|plan|apply|destroy|refresh]

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_FILE="${SCRIPT_DIR}/deployment.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

# ============================================================================
# 日志函数
# ============================================================================

log() {
    echo "[${TIMESTAMP}] $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo "✅ $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo "❌ $*" | tee -a "${LOG_FILE}"
}

log_info() {
    echo "ℹ️  $*" | tee -a "${LOG_FILE}"
}

# ============================================================================
# 前置条件检查
# ============================================================================

check_prerequisites() {
    log_info "检查前置条件..."

    # 检查 terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform 未安装。请运行: brew install terraform"
        exit 1
    fi

    # 检查 aws cli
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI 未安装。请运行: brew install awscli"
        exit 1
    fi

    # 检查 kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "Kubectl 未安装。请运行: brew install kubectl"
        exit 1
    fi

    # 检查 AWS 凭证
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS 凭证未配置。请运行: aws configure"
        exit 1
    fi

    log_success "所有前置条件都已满足"
}

# ============================================================================
# 初始化 Terraform
# ============================================================================

init() {
    log_info "初始化 Terraform..."

    if [ ! -f "${SCRIPT_DIR}/terraform.tfvars" ]; then
        log_error "terraform.tfvars 不存在"
        log_info "请运行: cp terraform.tfvars.example terraform.tfvars"
        exit 1
    fi

    terraform init -upgrade

    log_success "Terraform 初始化完成"
}

# ============================================================================
# 验证配置
# ============================================================================

validate() {
    log_info "验证 Terraform 配置..."
    terraform validate
    log_success "配置验证通过"
}

# ============================================================================
# 查看执行计划
# ============================================================================

plan() {
    log_info "生成 Terraform 执行计划..."
    init
    validate
    terraform plan -out="${SCRIPT_DIR}/tfplan"
    log_success "执行计划已生成: ${SCRIPT_DIR}/tfplan"
}

# ============================================================================
# 应用配置
# ============================================================================

apply() {
    log_info "应用 Terraform 配置..."

    check_prerequisites
    init
    validate

    # 读取集群名称
    CLUSTER_NAME=$(grep 'cluster_name' "${SCRIPT_DIR}/terraform.tfvars" | grep -v '#' | cut -d'"' -f2)

    log_info "准备部署 EKS 集群: ${CLUSTER_NAME}"
    log_info "这需要 10-15 分钟..."

    terraform apply -auto-approve

    log_success "基础设施部署完成！"

    # 配置 kubeconfig
    configure_kubeconfig "${CLUSTER_NAME}"
}

# ============================================================================
# 配置 kubeconfig
# ============================================================================

configure_kubeconfig() {
    local cluster_name=$1
    local region=$(grep 'aws_region' "${SCRIPT_DIR}/terraform.tfvars" | grep -v '#' | cut -d'"' -f2)

    log_info "配置 kubeconfig..."

    aws eks update-kubeconfig \
        --region "${region}" \
        --name "${cluster_name}"

    log_success "kubeconfig 已配置"

    log_info "验证集群连接..."
    kubectl get nodes
    kubectl get pods -A

    log_success "集群验证成功！"
}

# ============================================================================
# 销毁资源
# ============================================================================

destroy() {
    log_info "准备销毁所有 AWS 资源..."
    log_error "这将删除 EKS 集群、ECR 仓库和所有相关资源！"

    read -p "确认销毁？(yes/no): " confirmation

    if [ "${confirmation}" != "yes" ]; then
        log_info "取消销毁"
        return
    fi

    log_info "删除 Kubernetes Load Balancer 服务..."
    kubectl delete svc --all -A 2>/dev/null || true

    log_info "应用销毁配置..."
    terraform destroy -auto-approve

    log_success "资源销毁完成"
}

# ============================================================================
# 刷新状态
# ============================================================================

refresh() {
    log_info "刷新 Terraform 状态..."
    terraform refresh
    log_success "状态已刷新"
}

# ============================================================================
# 输出信息
# ============================================================================

output_info() {
    log_info "获取部署输出..."
    terraform output
}

# ============================================================================
# 主函数
# ============================================================================

main() {
    local action="${1:-help}"

    case "${action}" in
        init)
            check_prerequisites
            init
            ;;
        validate)
            check_prerequisites
            init
            validate
            ;;
        plan)
            check_prerequisites
            plan
            ;;
        apply)
            apply
            ;;
        destroy)
            check_prerequisites
            destroy
            ;;
        refresh)
            check_prerequisites
            refresh
            ;;
        output)
            check_prerequisites
            output_info
            ;;
        *)
            cat << 'EOF'
使用: ./deploy.sh [命令]

命令:
  init       初始化 Terraform
  validate   验证配置
  plan       生成执行计划
  apply      应用配置并部署 EKS
  destroy    销毁所有资源
  refresh    刷新 Terraform 状态
  output     显示输出值

示例:
  ./deploy.sh init      # 首次初始化
  ./deploy.sh plan      # 查看计划
  ./deploy.sh apply     # 部署集群
  ./deploy.sh destroy   # 删除所有资源

EOF
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
