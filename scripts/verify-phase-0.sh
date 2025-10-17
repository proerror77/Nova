#!/bin/bash

# ============================================
# Phase 0 验证脚本
# 用途: 验证所有 Phase 0 组件正常工作
# ============================================

set -e

echo "🚀 Phase 0 验证开始..."
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查函数
check_passed() {
    echo -e "${GREEN}✓${NC} $1"
}

check_failed() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

check_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# ============================================
# 1. 检查 Rust 工具链
# ============================================
echo "📦 检查 Rust 工具链..."
if command -v rustc &> /dev/null; then
    RUST_VERSION=$(rustc --version | awk '{print $2}')
    check_passed "Rust 已安装: $RUST_VERSION"
else
    check_failed "Rust 未安装,请访问 https://rustup.rs/"
fi

if command -v cargo &> /dev/null; then
    CARGO_VERSION=$(cargo --version | awk '{print $2}')
    check_passed "Cargo 已安装: $CARGO_VERSION"
else
    check_failed "Cargo 未安装"
fi
echo ""

# ============================================
# 2. 检查 Docker
# ============================================
echo "🐳 检查 Docker..."
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    check_passed "Docker 已安装: $DOCKER_VERSION"
else
    check_failed "Docker 未安装"
fi

if command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version | awk '{print $4}' | sed 's/,//')
    check_passed "Docker Compose 已安装: $COMPOSE_VERSION"
else
    check_warning "Docker Compose 未安装(可选)"
fi
echo ""

# ============================================
# 3. 检查项目文件
# ============================================
echo "📁 检查项目文件..."

FILES=(
    "backend/Cargo.toml"
    "backend/user-service/Cargo.toml"
    "backend/Dockerfile"
    "docker-compose.yml"
    "backend/migrations/001_initial_schema.sql"
    "backend/migrations/002_add_auth_logs.sql"
    "backend/user-service/src/main.rs"
    "backend/user-service/src/config.rs"
    ".env.example"
    ".github/workflows/ci.yml"
    "Makefile"
)

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        check_passed "文件存在: $file"
    else
        check_failed "文件缺失: $file"
    fi
done
echo ""

# ============================================
# 4. 检查 Rust 项目
# ============================================
echo "🦀 检查 Rust 项目编译..."
cd backend

if cargo check --quiet; then
    check_passed "Rust 项目编译通过"
else
    check_failed "Rust 项目编译失败"
fi

if cargo fmt --all -- --check 2>/dev/null; then
    check_passed "代码格式检查通过"
else
    check_warning "代码格式检查失败(运行 'cargo fmt' 修复)"
fi

if cargo clippy --all-targets --all-features -- -D warnings 2>/dev/null; then
    check_passed "Clippy 检查通过"
else
    check_warning "Clippy 检查有警告"
fi

cd ..
echo ""

# ============================================
# 5. 检查环境变量
# ============================================
echo "🔑 检查环境变量..."
if [ -f ".env" ]; then
    check_passed ".env 文件存在"

    # 检查关键变量
    if grep -q "DATABASE_URL" .env; then
        check_passed "DATABASE_URL 已配置"
    else
        check_warning "DATABASE_URL 未配置"
    fi

    if grep -q "REDIS_URL" .env; then
        check_passed "REDIS_URL 已配置"
    else
        check_warning "REDIS_URL 未配置"
    fi

    if grep -q "JWT_SECRET" .env; then
        JWT_SECRET=$(grep "JWT_SECRET" .env | cut -d'=' -f2)
        if [ ${#JWT_SECRET} -ge 32 ]; then
            check_passed "JWT_SECRET 长度足够(${#JWT_SECRET} 字符)"
        else
            check_warning "JWT_SECRET 太短(建议至少 32 字符)"
        fi
    else
        check_warning "JWT_SECRET 未配置"
    fi
else
    check_warning ".env 文件不存在(复制 .env.example 创建)"
fi
echo ""

# ============================================
# 6. 检查 Docker Compose
# ============================================
echo "🐋 验证 Docker Compose 配置..."
if docker-compose config &> /dev/null; then
    check_passed "docker-compose.yml 配置有效"
else
    check_failed "docker-compose.yml 配置无效"
fi
echo ""

# ============================================
# 7. 可选: 测试服务启动
# ============================================
echo "🧪 测试服务(可选)..."
read -p "是否启动 Docker 服务进行测试? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "启动服务..."
    docker-compose up -d

    echo "等待服务就绪(10 秒)..."
    sleep 10

    if curl -sf http://localhost:8080/api/v1/health &> /dev/null; then
        check_passed "服务健康检查通过"

        # 显示健康检查响应
        echo ""
        echo "健康检查响应:"
        curl -s http://localhost:8080/api/v1/health | jq '.' || curl -s http://localhost:8080/api/v1/health
        echo ""
    else
        check_warning "服务健康检查失败(检查日志: docker-compose logs)"
    fi

    read -p "是否停止服务? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker-compose down
        check_passed "服务已停止"
    fi
else
    check_warning "跳过服务测试"
fi
echo ""

# ============================================
# 总结
# ============================================
echo "════════════════════════════════════════"
echo "✅ Phase 0 验证完成!"
echo "════════════════════════════════════════"
echo ""
echo "下一步:"
echo "  1. 确保 .env 文件已正确配置"
echo "  2. 启动服务: make dev 或 docker-compose up -d"
echo "  3. 测试健康检查: make health 或 curl http://localhost:8080/api/v1/health"
echo "  4. 查看文档: backend/README.md"
echo ""
echo "开始 Phase 1 开发:"
echo "  - 实现用户注册功能"
echo "  - 实现邮箱验证功能"
echo "  - 详见 PHASE_0_SUMMARY.md"
echo ""
