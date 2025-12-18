#!/bin/bash
#
# Nova iOS 自动构建运行脚本
# 用法: ./run-ios.sh [simulator_name]
# 示例: ./run-ios.sh "iPhone 17 Pro"
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目配置
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
IOS_DIR="$PROJECT_DIR/ios/NovaSocial"
XCODEPROJ="$IOS_DIR/ICERED.xcodeproj"
SCHEME="ICERED"
CONFIGURATION="Debug"

# 默认模拟器 (可通过参数覆盖)
DEFAULT_SIMULATOR="iPhone 17 Pro"
SIMULATOR_NAME="${1:-$DEFAULT_SIMULATOR}"

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}       Nova iOS 自动构建 & 运行脚本${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""

# 检查 Xcode 项目是否存在
if [ ! -d "$XCODEPROJ" ]; then
    echo -e "${RED}错误: 找不到 Xcode 项目: $XCODEPROJ${NC}"
    exit 1
fi

# 获取模拟器 UDID
echo -e "${YELLOW}[1/5] 查找模拟器: $SIMULATOR_NAME${NC}"
SIMULATOR_UDID=$(xcrun simctl list devices available | grep "$SIMULATOR_NAME" | head -1 | grep -oE '\([A-F0-9-]{36}\)' | tr -d '()')

if [ -z "$SIMULATOR_UDID" ]; then
    echo -e "${RED}错误: 找不到模拟器 '$SIMULATOR_NAME'${NC}"
    echo -e "${YELLOW}可用的模拟器:${NC}"
    xcrun simctl list devices available | grep -E "iPhone|iPad" | head -10
    exit 1
fi

echo -e "${GREEN}  ✓ 找到模拟器 UDID: $SIMULATOR_UDID${NC}"

# 启动模拟器
echo -e "${YELLOW}[2/5] 启动模拟器...${NC}"
xcrun simctl boot "$SIMULATOR_UDID" 2>/dev/null || true
open -a Simulator

# 等待模拟器启动
sleep 2
echo -e "${GREEN}  ✓ 模拟器已启动${NC}"

# 构建项目
echo -e "${YELLOW}[3/5] 构建 iOS 项目...${NC}"
xcodebuild \
    -project "$XCODEPROJ" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "platform=iOS Simulator,id=$SIMULATOR_UDID" \
    -derivedDataPath "$PROJECT_DIR/build" \
    build \
    2>&1 | grep -E "(Building|Compiling|Linking|error:|warning:|Build Succeeded|BUILD SUCCEEDED|BUILD FAILED)" || true

# 检查构建结果
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}构建失败!${NC}"
    exit 1
fi

echo -e "${GREEN}  ✓ 构建成功${NC}"

# 查找 .app 文件
echo -e "${YELLOW}[4/5] 安装应用到模拟器...${NC}"
APP_PATH=$(find "$PROJECT_DIR/build" -name "*.app" -type d | grep -v "\.dSYM" | head -1)

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}错误: 找不到构建的 .app 文件${NC}"
    exit 1
fi

xcrun simctl install "$SIMULATOR_UDID" "$APP_PATH"
echo -e "${GREEN}  ✓ 应用已安装${NC}"

# 获取 Bundle ID 并启动应用
echo -e "${YELLOW}[5/5] 启动应用...${NC}"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP_PATH/Info.plist" 2>/dev/null)

if [ -z "$BUNDLE_ID" ]; then
    # 尝试从项目中获取
    BUNDLE_ID="com.icered.NovaSocial"
fi

xcrun simctl launch "$SIMULATOR_UDID" "$BUNDLE_ID"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓ 应用已在 $SIMULATOR_NAME 上运行!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}提示: 使用 Cmd+Shift+H 返回主屏幕${NC}"
