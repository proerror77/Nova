#!/bin/bash
# 启动数据库迁移所需的基础设施
# 用法: ./start-databases.sh

set -e

echo "🚀 启动数据库基础设施..."

# 检查 Docker 是否运行
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker daemon 未运行"
    echo "请先启动 Docker Desktop，然后重新运行此脚本"
    exit 1
fi

echo "✅ Docker daemon 运行中"

# 启动 PostgreSQL 和 ClickHouse
echo "🐘 启动 PostgreSQL..."
docker-compose up -d postgres

echo "📊 启动 ClickHouse..."
docker-compose up -d clickhouse

# 等待服务就绪
echo "⏳ 等待数据库服务启动..."
sleep 5

# 验证 PostgreSQL
echo "🔍 验证 PostgreSQL..."
docker-compose exec -T postgres psql -U postgres -c "SELECT version();" | head -3

# 验证 ClickHouse
echo "🔍 验证 ClickHouse..."
curl -s "http://localhost:8123/ping" && echo "✅ ClickHouse 就绪"

echo ""
echo "✅ 所有数据库服务已启动"
echo ""
echo "下一步："
echo "  1. 检查数据库状态: docker-compose ps"
echo "  2. 执行迁移: cd backend && sqlx migrate run"
