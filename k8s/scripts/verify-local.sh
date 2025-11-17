#!/bin/bash

# Nova Messaging Service - Local Verification Script
# 本地验证脚本 - 快速检查部署状态

NAMESPACE="nova-messaging"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

check_status() {
    local name=$1
    local command=$2

    if eval "$command" &> /dev/null; then
        echo -e "${GREEN}✅${NC} $name"
        return 0
    else
        echo -e "${RED}❌${NC} $name"
        return 1
    fi
}

print_section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
}

main() {
    print_section "Nova Messaging Service 本地验证"

    # 1. Check cluster
    print_section "1. K8s集群"
    if kubectl cluster-info &> /dev/null; then
        echo -e "${GREEN}✅${NC} 集群运行中"
        CONTEXT=$(kubectl config current-context)
        echo "   上下文: $CONTEXT"
    else
        echo -e "${RED}❌${NC} 集群未运行"
        exit 1
    fi

    # 2. Check namespace
    print_section "2. 命名空间"
    check_status "nova-messaging 命名空间" "kubectl get ns $NAMESPACE"

    # 3. Check RBAC
    print_section "3. RBAC (已改用 realtime-chat-service，messaging-service 已淘汰)"

    # 4. Check ConfigMap and Secret
    print_section "4. 配置 (messaging-service 已淘汰，如需即時聊天請檢查 realtime-chat-service)"

    # 5. Check Deployment
    print_section "5. 部署 (messaging-service 已淘汰)"

    # 6. Check Pods
    print_section "6. Pod (messaging-service 已淘汰)"
    POD_COUNT=0
    if [ $POD_COUNT -gt 0 ]; then
        echo -e "${GREEN}✅${NC} Pod运行中 ($POD_COUNT 个)"
        kubectl get pods -n $NAMESPACE -l component=messaging-service --no-headers | while read line; do
            POD_NAME=$(echo $line | awk '{print $1}')
            STATUS=$(echo $line | awk '{print $3}')
            if [ "$STATUS" = "Running" ]; then
                echo "   ${GREEN}✓${NC} $POD_NAME ($STATUS)"
            elif [ "$STATUS" = "Pending" ]; then
                echo "   ${YELLOW}⏳${NC} $POD_NAME ($STATUS)"
            else
                echo "   ${RED}✗${NC} $POD_NAME ($STATUS)"
            fi
        done
    else
        echo -e "${RED}❌${NC} 没有Pod运行"
    fi

    # 7. Check Services
    print_section "7. 服务 (messaging-service 已淘汰)"
    SVC_COUNT=$(kubectl get svc -n $NAMESPACE --no-headers 2>/dev/null | wc -l)
    if [ $SVC_COUNT -gt 0 ]; then
        echo -e "${GREEN}✅${NC} 服务 ($SVC_COUNT 个)"
        kubectl get svc -n $NAMESPACE --no-headers | while read line; do
            SVC_NAME=$(echo $line | awk '{print $1}')
            SVC_TYPE=$(echo $line | awk '{print $2}')
            PORT=$(echo $line | awk '{print $5}')
            echo "   • $SVC_NAME ($SVC_TYPE) $PORT"
        done
    else
        echo -e "${RED}❌${NC} 没有服务"
    fi

    # 8. Check Deployment Status
    print_section "8. 部署状态 (messaging-service 已淘汰，請改用 realtime-chat-service 檢查)"

    # 9. Test Health Check
    print_section "9. 健康检查 (messaging-service 已淘汰)"

    # 10. Recent Logs
    print_section "10. 最近日志 (messaging-service 已淘汰)"

    # 11. Resource Usage
    print_section "11. 资源使用"
    if kubectl top pods -n $NAMESPACE &> /dev/null; then
        kubectl top pods -n $NAMESPACE 2>/dev/null | sed 's/^/   /'
    else
        echo -e "${YELLOW}⚠️${NC}  Metrics还未就绪 (稍后重试)"
    fi

    # 12. Recent Events
    print_section "12. 最近事件"
    EVENT_COUNT=$(kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' 2>/dev/null | tail -n +2 | wc -l)
    if [ $EVENT_COUNT -gt 0 ]; then
        echo "   (最后3个):"
        kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' 2>/dev/null | tail -n 4 | sed 's/^/   /'
    else
        echo -e "${YELLOW}⚠️${NC}  没有事件"
    fi

    # Summary
    print_section "总结"

    # Count checks
    NAMESPACE_OK=$(kubectl get ns $NAMESPACE &> /dev/null && echo 1 || echo 0)
    PODS_OK=$([ $POD_COUNT -gt 0 ] && echo 1 || echo 0)

    if [ $NAMESPACE_OK -eq 1 ] && [ $PODS_OK -eq 1 ]; then
        echo -e "${GREEN}✅ 集群可用（messaging-service 已淘汰）${NC}"
        echo ""
        echo "接下来:"
        echo "1. 如需聊天功能，請檢查 realtime-chat-service 的部署與健康狀態"
    else
        echo -e "${YELLOW}⚠️  部署仍在进行中${NC}"
        echo ""
        echo "故障排查:"
        echo "1. 检查Pod状态: kubectl describe pod <pod-name> -n $NAMESPACE"
        echo "2. 查看日志: kubectl logs <pod-name> -n $NAMESPACE --all-containers=true"
        echo "3. 检查事件: kubectl get events -n $NAMESPACE"
    fi

    echo ""
}

main "$@"
