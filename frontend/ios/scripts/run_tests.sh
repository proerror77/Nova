#!/bin/bash

# Nova Instagram iOS 测试运行脚本
# 运行所有测试并生成覆盖率报告

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
SCHEME="NovaApp"
DESTINATION="platform=iOS Simulator,name=iPhone 13 Pro"
RESULTS_DIR="TestResults"
COVERAGE_THRESHOLD=80

# 显示标题
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Nova Instagram iOS Test Suite${NC}"
echo -e "${BLUE}========================================${NC}\n"

# 解析参数
TEST_TYPE="all"
VERBOSE=false
COVERAGE_ONLY=false
SNAPSHOT_RECORD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --unit)
            TEST_TYPE="unit"
            shift
            ;;
        --integration)
            TEST_TYPE="integration"
            shift
            ;;
        --ui)
            TEST_TYPE="ui"
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --coverage-only)
            COVERAGE_ONLY=true
            shift
            ;;
        --record-snapshots)
            SNAPSHOT_RECORD=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --unit              Run only unit tests"
            echo "  --integration       Run only integration tests"
            echo "  --ui                Run only UI tests"
            echo "  --verbose, -v       Show detailed output"
            echo "  --coverage-only     Only generate coverage report"
            echo "  --record-snapshots  Record new snapshots (for UI tests)"
            echo "  --help, -h          Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# 清理旧结果
echo -e "${YELLOW}Cleaning up old test results...${NC}"
rm -rf "$RESULTS_DIR"
rm -rf DerivedData

# 如果只生成覆盖率报告
if [ "$COVERAGE_ONLY" = true ]; then
    if [ ! -f "$RESULTS_DIR.xcresult" ]; then
        echo -e "${RED}No test results found. Run tests first.${NC}"
        exit 1
    fi
    echo -e "${BLUE}Generating coverage report...${NC}"
    xcrun xccov view --report "$RESULTS_DIR.xcresult"
    exit 0
fi

# 构建测试目标参数
TEST_TARGET=""
case $TEST_TYPE in
    unit)
        echo -e "${BLUE}Running Unit Tests...${NC}"
        TEST_TARGET="-only-testing:NovaAppTests"
        ;;
    integration)
        echo -e "${BLUE}Running Integration Tests...${NC}"
        TEST_TARGET="-only-testing:NovaAppIntegrationTests"
        ;;
    ui)
        echo -e "${BLUE}Running UI Tests...${NC}"
        TEST_TARGET="-only-testing:NovaAppUITests"
        if [ "$SNAPSHOT_RECORD" = true ]; then
            echo -e "${YELLOW}Snapshot recording mode enabled${NC}"
            # 设置环境变量以启用快照录制
            export SNAPSHOT_RECORDING=1
        fi
        ;;
    all)
        echo -e "${BLUE}Running All Tests...${NC}"
        ;;
esac

# 构建 xcodebuild 命令
XCODEBUILD_CMD=(
    xcodebuild test
    -scheme "$SCHEME"
    -destination "$DESTINATION"
    -enableCodeCoverage YES
    -resultBundlePath "$RESULTS_DIR.xcresult"
)

if [ -n "$TEST_TARGET" ]; then
    XCODEBUILD_CMD+=("$TEST_TARGET")
fi

if [ "$VERBOSE" = false ]; then
    XCODEBUILD_CMD+=(-quiet)
fi

# 运行测试
echo -e "\n${BLUE}Starting tests...${NC}\n"

START_TIME=$(date +%s)

if "${XCODEBUILD_CMD[@]}"; then
    TEST_RESULT="PASSED"
    RESULT_COLOR=$GREEN
else
    TEST_RESULT="FAILED"
    RESULT_COLOR=$RED
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# 显示测试结果
echo -e "\n${BLUE}========================================${NC}"
echo -e "${RESULT_COLOR}  Test Result: $TEST_RESULT${NC}"
echo -e "${BLUE}  Duration: ${DURATION}s${NC}"
echo -e "${BLUE}========================================${NC}\n"

# 生成覆盖率报告
if [ "$TEST_RESULT" = "PASSED" ]; then
    echo -e "${BLUE}Generating coverage report...${NC}\n"

    # 生成 JSON 格式的覆盖率报告
    xcrun xccov view --report --json "$RESULTS_DIR.xcresult" > coverage.json

    # 提取覆盖率数据
    COVERAGE=$(jq -r '.lineCoverage * 100' coverage.json)
    COVERAGE_INT=${COVERAGE%.*}

    echo -e "${BLUE}Coverage Report:${NC}"
    echo -e "${BLUE}========================================${NC}"

    # 显示整体覆盖率
    if (( COVERAGE_INT >= COVERAGE_THRESHOLD )); then
        echo -e "${GREEN}✓ Overall Coverage: ${COVERAGE}%${NC}"
    else
        echo -e "${YELLOW}⚠ Overall Coverage: ${COVERAGE}% (Target: ${COVERAGE_THRESHOLD}%)${NC}"
    fi

    # 显示详细覆盖率（按文件）
    echo -e "\n${BLUE}Coverage by File:${NC}"
    xcrun xccov view --report --files-for-target NovaApp.app "$RESULTS_DIR.xcresult" | head -20

    # 生成 HTML 报告
    echo -e "\n${BLUE}Generating HTML coverage report...${NC}"
    xcrun xccov view --report "$RESULTS_DIR.xcresult" > coverage.txt

    # 检查覆盖率是否达标
    if (( COVERAGE_INT < COVERAGE_THRESHOLD )); then
        echo -e "\n${YELLOW}⚠ Warning: Coverage is below ${COVERAGE_THRESHOLD}% threshold${NC}"
        echo -e "${YELLOW}Please add more tests to improve coverage.${NC}\n"
    else
        echo -e "\n${GREEN}✓ Coverage meets the ${COVERAGE_THRESHOLD}% threshold${NC}\n"
    fi

    # 未覆盖的文件
    echo -e "${BLUE}Files with lowest coverage:${NC}"
    jq -r '.targets[] | select(.name == "NovaApp.app") | .files[] | "\(.lineCoverage * 100)% - \(.path)"' coverage.json | \
        sort -n | head -10

    echo -e "\n${BLUE}========================================${NC}\n"

    # 生成徽章（可选）
    if command -v coverage-badge &> /dev/null; then
        coverage-badge -o coverage-badge.svg -f coverage.json
        echo -e "${GREEN}Coverage badge generated: coverage-badge.svg${NC}"
    fi
fi

# 测试失败时显示失败详情
if [ "$TEST_RESULT" = "FAILED" ]; then
    echo -e "${RED}Test failures detected. Details:${NC}\n"

    # 提取失败的测试
    xcrun xcresulttool get --path "$RESULTS_DIR.xcresult" --format json | \
        jq -r '.issues.testFailureSummaries[]? | "❌ \(.testCaseName): \(.message)"' 2>/dev/null || \
        echo "Unable to extract failure details"

    echo -e "\n${YELLOW}Run with --verbose flag for detailed output${NC}\n"
    exit 1
fi

# 清理
if [ "$VERBOSE" = false ]; then
    echo -e "${YELLOW}Cleaning up temporary files...${NC}"
    # 保留结果但清理构建产物
fi

echo -e "${GREEN}✓ Testing complete!${NC}\n"

# 显示快速摘要
echo -e "${BLUE}Quick Summary:${NC}"
echo -e "  Test Suite: ${TEST_TYPE}"
echo -e "  Duration: ${DURATION}s"
echo -e "  Coverage: ${COVERAGE}%"
echo -e "  Result: ${TEST_RESULT}\n"

# 退出码
if [ "$TEST_RESULT" = "PASSED" ]; then
    exit 0
else
    exit 1
fi
