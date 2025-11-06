#!/bin/bash
# Xcode Build Phase Script - Figma Design System Sync
# 在 Xcode 构建前自动同步 Figma 设计系统
#
# 用法：在 Xcode 项目的 Build Phases 中添加新的 Run Script Phase，
# 并设置脚本为：
# ${SRCROOT}/scripts/xcode-figma-build-phase.sh

set -euo pipefail

# 配置
SCRIPTS_DIR="${SRCROOT}/scripts"
FIGMA_TOKEN="${FIGMA_TOKEN:-}"
DESIGN_SYSTEM_DIR="${SRCROOT}/NovaSocial/DesignSystem"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# 检查环境
if [ -z "$FIGMA_TOKEN" ]; then
    log_warning "FIGMA_TOKEN not set, skipping Figma sync"
    log_info "To enable: export FIGMA_TOKEN=<your-token>"
    exit 0
fi

log_info "Starting Figma Design System Sync"

# 检查 Python 脚本
if [ ! -f "$SCRIPTS_DIR/design-system-sync.py" ]; then
    log_error "design-system-sync.py not found in $SCRIPTS_DIR"
    exit 1
fi

# 运行 Python 同步脚本
log_info "Running design-system-sync.py..."

if python3 "$SCRIPTS_DIR/design-system-sync.py"; then
    log_success "Design system synchronized"
else
    log_error "Failed to synchronize design system"
    exit 1
fi

# 验证生成的文件
required_files=(
    "Colors.swift"
    "Typography.swift"
    "Spacing.swift"
)

missing_files=0
for file in "${required_files[@]}"; do
    if [ ! -f "$DESIGN_SYSTEM_DIR/$file" ]; then
        log_error "Missing: $file"
        missing_files=$((missing_files + 1))
    fi
done

if [ $missing_files -gt 0 ]; then
    log_error "$missing_files required files are missing"
    exit 1
fi

log_success "All design system files verified"

# 可选：检查代码格式
if command -v swiftformat &> /dev/null; then
    log_info "Running swiftformat on design system files..."
    swiftformat "$DESIGN_SYSTEM_DIR" || true
    log_success "Code formatted"
fi

log_info "Figma Design System Sync Complete"
