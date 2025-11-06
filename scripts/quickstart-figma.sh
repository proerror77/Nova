#!/bin/bash
# Figma Integration Quick Start
# 快速启动 Figma 与 SwiftUI 的集成

set -euo pipefail

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║      Figma + SwiftUI Integration Quick Start             ║"
    echo "║              Nova Social iOS App                          ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_step() {
    echo -e "${YELLOW}▶ $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

banner

# Step 1: 检查环境
log_step "检查环境..."

if ! command -v python3 &> /dev/null; then
    log_error "Python 3 未安装"
    exit 1
fi
log_success "Python 3 已安装"

if [ -z "${FIGMA_TOKEN:-}" ]; then
    log_error "FIGMA_TOKEN 环境变量未设置"
    echo "设置方法:"
    echo "  export FIGMA_TOKEN='your_token_here'"
    exit 1
fi
log_success "FIGMA_TOKEN 已设置"

# Step 2: 检查脚本
log_step "检查脚本文件..."

scripts_needed=(
    "scripts/figma-export.sh"
    "scripts/figma-to-swiftui.py"
    "scripts/design-system-sync.py"
    "scripts/xcode-figma-build-phase.sh"
)

for script in "${scripts_needed[@]}"; do
    if [ ! -f "$script" ]; then
        log_error "缺少文件: $script"
        exit 1
    fi
done
log_success "所有脚本文件已准备"

# Step 3: 检查 Python 依赖
log_step "检查 Python 依赖..."

if ! python3 -c "import requests" 2>/dev/null; then
    log_step "安装 requests..."
    pip3 install requests
    log_success "requests 已安装"
else
    log_success "requests 已安装"
fi

# Step 4: 设置脚本权限
log_step "设置脚本权限..."

for script in scripts/*.sh; do
    chmod +x "$script"
done
log_success "脚本权限已设置"

# Step 5: 生成设计系统
log_step "生成设计系统文件..."

output_dir="ios/NovaSocial/DesignSystem"
mkdir -p "$output_dir"

if python3 scripts/design-system-sync.py; then
    log_success "设计系统已生成"
else
    log_error "设计系统生成失败"
    exit 1
fi

# Step 6: 生成组件
log_step "生成 SwiftUI 组件..."

if python3 scripts/figma-to-swiftui.py; then
    log_success "组件已生成"
else
    log_error "组件生成失败"
    exit 1
fi

# Step 7: 验证
log_step "验证生成的文件..."

required_files=(
    "$output_dir/Colors.swift"
    "$output_dir/Typography.swift"
    "$output_dir/Spacing.swift"
)

for file in "${required_files[@]}"; do
    if [ -f "$file" ]; then
        log_success "✓ $file"
    else
        log_error "✗ $file 缺失"
        exit 1
    fi
done

# 完成
echo ""
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                  🎉 安装完成！                            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo "
下一步：

1. 在 Xcode 中配置构建阶段：
   • Build Phases → + New Run Script Phase
   • 添加脚本: ${SRCROOT}/scripts/xcode-figma-build-phase.sh

2. 在你的代码中使用设计系统：
   • @import BrandColors
   • @import BrandTypography
   • @import BrandSpacing

3. 查看完整文档：
   • cat FIGMA_INTEGRATION_GUIDE.md

4. 更新 Figma 后同步：
   • python3 scripts/design-system-sync.py
   • 或让 Xcode 自动同步

文档：
  📄 FIGMA_INTEGRATION_GUIDE.md
  📄 ios/NovaSocial/DesignSystem/README.md

需要帮助？查看故障排除部分：
  $ cat FIGMA_INTEGRATION_GUIDE.md | grep -A 20 \"故障排除\"
"

echo -e "${BLUE}Happy coding! 🚀${NC}"
