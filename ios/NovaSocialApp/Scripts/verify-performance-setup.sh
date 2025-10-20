#!/bin/bash

# 性能优化系统集成验证脚本
# 检查所有必要文件是否存在，并运行基础测试

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}   Performance Optimization Setup Verification${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 1. 检查核心文件
echo -e "${YELLOW}[1/5] Checking core files...${NC}"

FILES=(
    "Network/Services/CacheManager.swift"
    "Network/Services/RequestDeduplicator.swift"
    "Network/Services/NetworkMonitor.swift"
    "Network/Services/PerformanceMetrics.swift"
    "Network/Services/URLCacheConfig.swift"
    "Network/Services/PerformanceKit.swift"
)

MISSING_FILES=0

for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "  ${GREEN}✓${NC} $file"
    else
        echo -e "  ${RED}✗${NC} $file ${RED}(MISSING)${NC}"
        MISSING_FILES=$((MISSING_FILES + 1))
    fi
done

if [ $MISSING_FILES -gt 0 ]; then
    echo -e "${RED}✗ Missing $MISSING_FILES core files!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All core files present${NC}"
echo ""

# 2. 检查文档
echo -e "${YELLOW}[2/5] Checking documentation...${NC}"

DOCS=(
    "Network/Services/README.md"
    "PERFORMANCE_SETUP_GUIDE.md"
    "PERFORMANCE_CHECKLIST.md"
    "PERFORMANCE_IMPLEMENTATION_SUMMARY.md"
)

for doc in "${DOCS[@]}"; do
    if [ -f "$doc" ]; then
        echo -e "  ${GREEN}✓${NC} $doc"
    else
        echo -e "  ${YELLOW}⚠${NC} $doc ${YELLOW}(missing)${NC}"
    fi
done

echo ""

# 3. 检查示例代码
echo -e "${YELLOW}[3/5] Checking example code...${NC}"

EXAMPLES=(
    "Examples/PerformanceOptimizationExamples.swift"
    "Examples/PerformanceDemoApp.swift"
)

for example in "${EXAMPLES[@]}"; do
    if [ -f "$example" ]; then
        echo -e "  ${GREEN}✓${NC} $example"
    else
        echo -e "  ${YELLOW}⚠${NC} $example ${YELLOW}(missing)${NC}"
    fi
done

echo ""

# 4. 检查测试文件
echo -e "${YELLOW}[4/5] Checking test files...${NC}"

TESTS=(
    "Tests/PerformanceTests.swift"
)

for test in "${TESTS[@]}"; do
    if [ -f "$test" ]; then
        echo -e "  ${GREEN}✓${NC} $test"
    else
        echo -e "  ${RED}✗${NC} $test ${RED}(MISSING)${NC}"
    fi
done

echo ""

# 5. 统计代码行数
echo -e "${YELLOW}[5/5] Code statistics...${NC}"

if command -v cloc &> /dev/null; then
    echo ""
    cloc --quiet Network/Services/*.swift Tests/PerformanceTests.swift 2>/dev/null || true
    echo ""
else
    # 简单统计
    TOTAL_LINES=0
    for file in Network/Services/*.swift Tests/PerformanceTests.swift; do
        if [ -f "$file" ]; then
            LINES=$(wc -l < "$file" | tr -d ' ')
            TOTAL_LINES=$((TOTAL_LINES + LINES))
        fi
    done
    echo -e "  Total Swift code: ${GREEN}~$TOTAL_LINES lines${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Verification Complete!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo -e "  1. Read the setup guide: ${BLUE}PERFORMANCE_SETUP_GUIDE.md${NC}"
echo -e "  2. Follow the checklist: ${BLUE}PERFORMANCE_CHECKLIST.md${NC}"
echo -e "  3. Run tests: ${BLUE}xcodebuild test -only-testing:PerformanceTests${NC}"
echo ""
echo -e "${YELLOW}Quick Integration:${NC}"
echo -e "  Add to AppDelegate:"
echo -e "    ${BLUE}PerformanceKit.configure(enableDebug: true)${NC}"
echo ""
