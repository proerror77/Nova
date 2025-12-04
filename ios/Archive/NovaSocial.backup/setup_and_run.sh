#!/bin/bash

# 📱 Nova Social iOS 模拟器快速启动脚本

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="NovaSocial"

echo "🚀 启动 Nova Social iOS 应用..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 第一步：检查 Xcode 命令行工具
echo "✅ 检查 Xcode 版本..."
xcodebuild -version

# 第二步：选择模拟器
echo ""
echo "📱 可用的模拟器："
xcrun simctl list devices available | grep "iPhone"

echo ""
echo "🔍 选择默认 iPhone 模拟器..."
SIMULATOR=$(xcrun simctl list devices available | grep "iPhone 15" | head -1 | sed 's/.*(\([^)]*\)).*/\1/' || echo "Not found")

if [ "$SIMULATOR" = "Not found" ]; then
    SIMULATOR=$(xcrun simctl list devices available | grep "iPhone" | tail -1 | sed 's/.*(\([^)]*\)).*/\1/')
fi

echo "使用模拟器: $SIMULATOR"

# 第三步：启动模拟器
echo ""
echo "⏳ 启动模拟器..."
open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR" &

sleep 3

# 第四步：创建临时 Xcode 项目
echo ""
echo "📦 创建临时 Xcode 项目..."

# 创建临时目录
TEMP_PROJECT_DIR="/tmp/NovaSocialTemp"
rm -rf "$TEMP_PROJECT_DIR"
mkdir -p "$TEMP_PROJECT_DIR"

# 复制源文件
cp "$PROJECT_DIR"/*.swift "$TEMP_PROJECT_DIR/" 2>/dev/null || true
cp -r "$PROJECT_DIR"/Views "$TEMP_PROJECT_DIR/" 2>/dev/null || true
cp -r "$PROJECT_DIR"/ViewModels "$TEMP_PROJECT_DIR/" 2>/dev/null || true
cp -r "$PROJECT_DIR"/Network "$TEMP_PROJECT_DIR/" 2>/dev/null || true

# 创建 Package.swift
cat > "$TEMP_PROJECT_DIR/Package.swift" << 'EOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NovaSocial",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "NovaSocial",
            targets: ["NovaSocial"]
        ),
    ],
    targets: [
        .target(
            name: "NovaSocial",
            dependencies: []
        ),
    ]
)
EOF

echo "✅ 项目创建完成"

# 第五步：打开 Xcode
echo ""
echo "🎨 打开 Xcode..."
echo ""
echo "📋 操作步骤："
echo "  1. 在 Xcode 中选择模拟器: $SIMULATOR"
echo "  2. 按 ⌘R 运行应用"
echo "  3. 享受 UI 预览！"
echo ""

# 尝试打开 Xcode
if [ -f "$PROJECT_DIR/NovaSocialApp.swift" ]; then
    open -a Xcode "$PROJECT_DIR"
else
    echo "❌ 找不到项目文件"
    exit 1
fi

echo "✅ 完成！请在 Xcode 中按 ⌘R 运行"
