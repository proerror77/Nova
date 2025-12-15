#!/bin/bash

# Nova API Services Port Forward Script
# 用于本地测试 iOS app 连接到 K8s staging 环境

set -e

echo "🚀 启动 Nova API 服务 Port Forward..."
echo ""

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 检查是否已有 port-forward 进程
cleanup_existing() {
    echo "🧹 清理已有的 port-forward 进程..."
    pkill -f "kubectl port-forward.*nova-staging" 2>/dev/null || true
    sleep 1
}

# 启动 port-forward
start_port_forward() {
    local service=$1
    local local_port=$2
    local remote_port=$3

    echo -e "${YELLOW}启动 $service port-forward: localhost:$local_port → $remote_port${NC}"

    kubectl port-forward -n nova-staging svc/$service $local_port:$remote_port > /tmp/pf-$service.log 2>&1 &
    local pid=$!

    echo "  PID: $pid"
    echo "  日志: /tmp/pf-$service.log"
}

# 测试连接
test_service() {
    local service=$1
    local port=$2
    local path=$3

    echo -n "  测试 $service ... "

    sleep 2

    if curl -s -f -m 3 http://localhost:$port$path > /dev/null 2>&1; then
        echo -e "${GREEN}✅ OK${NC}"
        return 0
    else
        echo -e "${RED}❌ 失败${NC}"
        return 1
    fi
}

# 主流程
main() {
    cleanup_existing

    echo ""
    echo "📡 启动核心服务 Port Forward:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Identity Service (认证)
    start_port_forward "identity-service" 8080 8080

    # Content Service (内容)
    start_port_forward "content-service" 8081 8080

    # Media Service (媒体)
    start_port_forward "media-service" 8082 8082

    # Search Service (搜索)
    start_port_forward "search-service" 8086 8086

    # Notification Service (通知)
    start_port_forward "notification-service" 8087 8080

    echo ""
    echo "⏳ 等待服务就绪..."
    sleep 5

    echo ""
    echo "🔍 测试服务连接:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    test_service "identity-service" 8080 "/health" || true
    test_service "content-service" 8081 "/health" || true
    test_service "media-service" 8082 "/health" || true
    test_service "search-service" 8086 "/health" || true
    test_service "notification-service" 8087 "/health" || true

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${GREEN}✅ Port Forward 已启动!${NC}"
    echo ""
    echo "📱 iOS App 可以连接到:"
    echo "  - http://localhost:8080 (identity-service - 认证)"
    echo "  - http://localhost:8081 (content-service - 内容)"
    echo "  - http://localhost:8082 (media-service - 媒体)"
    echo "  - http://localhost:8086 (search-service - 搜索)"
    echo "  - http://localhost:8087 (notification-service - 通知)"
    echo ""
    echo "💡 提示:"
    echo "  1. 在 Xcode 中选择 'development' 配置"
    echo "  2. 或者手动设置 APIConfig.current = .development"
    echo "  3. iOS 会自动连接到 localhost:8080"
    echo ""
    echo "🛑 停止所有 port-forward:"
    echo "  pkill -f 'kubectl port-forward.*nova-staging'"
    echo ""
    echo "📋 查看日志:"
    echo "  tail -f /tmp/pf-*.log"
    echo ""
}

# 执行
main

# 保持运行
echo "⌛ Port Forward 运行中... (按 Ctrl+C 停止)"
echo ""
wait
