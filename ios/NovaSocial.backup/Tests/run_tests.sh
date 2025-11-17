#!/bin/bash

# iOS 测试运行脚本
# 功能：运行所有测试，生成覆盖率报告

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting iOS Test Suite${NC}"
echo "=================================="

# 配置
SCHEME="NovaSocial"
DERIVED_DATA_PATH="./DerivedData"
COVERAGE_REPORT_DIR="./TestReports"

# 清理旧数据
echo -e "${YELLOW}🧹 Cleaning old test data...${NC}"
rm -rf "$DERIVED_DATA_PATH"
rm -rf "$COVERAGE_REPORT_DIR"
mkdir -p "$COVERAGE_REPORT_DIR"

# 检查是否有测试设备
echo -e "${BLUE}📱 Detecting test device...${NC}"
DEVICE=$(xcrun xctrace list devices 2>&1 | grep "iPhone" | grep "Simulator" | head -1 | awk -F'[()]' '{print $2}')

if [ -z "$DEVICE" ]; then
    echo -e "${RED}❌ No simulator found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Using device: $DEVICE${NC}"

# 运行单元测试
echo ""
echo -e "${BLUE}🧪 Running Unit Tests...${NC}"
echo "=================================="

xcodebuild test \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$DEVICE" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -enableCodeCoverage YES \
    -only-testing:NovaSocialTests/ConcurrencyTests \
    -only-testing:NovaSocialTests/AuthRepositoryTests \
    -only-testing:NovaSocialTests/FeedRepositoryTests \
    -only-testing:NovaSocialTests/ErrorHandlingTests \
    -only-testing:NovaSocialTests/CacheTests \
    | xcpretty && exit ${PIPESTATUS[0]}

UNIT_TEST_RESULT=$?

# 运行性能测试（可选）
echo ""
echo -e "${BLUE}⚡ Running Performance Tests...${NC}"
echo "=================================="

xcodebuild test \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$DEVICE" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -enableCodeCoverage YES \
    -only-testing:NovaSocialTests/NetworkPerformanceTests \
    | xcpretty && exit ${PIPESTATUS[0]}

PERF_TEST_RESULT=$?

# 生成覆盖率报告
echo ""
echo -e "${BLUE}📊 Generating Coverage Report...${NC}"
echo "=================================="

# 查找覆盖率文件
COVERAGE_FILE=$(find "$DERIVED_DATA_PATH" -name "*.xcresult" | head -1)

if [ -z "$COVERAGE_FILE" ]; then
    echo -e "${YELLOW}⚠️  Coverage file not found${NC}"
else
    echo -e "${GREEN}✓ Coverage file: $COVERAGE_FILE${NC}"

    # 导出覆盖率数据
    xcrun xccov view --report "$COVERAGE_FILE" > "$COVERAGE_REPORT_DIR/coverage_summary.txt"
    xcrun xccov view --report --json "$COVERAGE_FILE" > "$COVERAGE_REPORT_DIR/coverage.json"

    # 解析覆盖率百分比
    COVERAGE=$(xcrun xccov view --report "$COVERAGE_FILE" | grep -E "^\s*[0-9]+\.[0-9]+%" | head -1 | awk '{print $1}')

    echo ""
    echo -e "${GREEN}📈 Overall Coverage: $COVERAGE${NC}"

    # 显示详细覆盖率
    echo ""
    echo -e "${BLUE}Detailed Coverage by File:${NC}"
    xcrun xccov view --report "$COVERAGE_FILE" | head -30
fi

# 总结
echo ""
echo "=================================="
echo -e "${BLUE}📝 Test Summary${NC}"
echo "=================================="

if [ $UNIT_TEST_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Unit Tests: PASSED${NC}"
else
    echo -e "${RED}✗ Unit Tests: FAILED${NC}"
fi

if [ $PERF_TEST_RESULT -eq 0 ]; then
    echo -e "${GREEN}✓ Performance Tests: PASSED${NC}"
else
    echo -e "${RED}✗ Performance Tests: FAILED${NC}"
fi

# 输出报告位置
echo ""
echo -e "${BLUE}📂 Reports saved to: $COVERAGE_REPORT_DIR${NC}"

# 退出码
if [ $UNIT_TEST_RESULT -ne 0 ] || [ $PERF_TEST_RESULT -ne 0 ]; then
    exit 1
fi

echo ""
echo -e "${GREEN}✅ All tests passed!${NC}"
exit 0
