#!/bin/bash

# Track progress on unwrap() removal
# Usage: ./scripts/unwrap-progress.sh

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Unwrap() Removal Progress ===${NC}"
echo ""

# Total unwraps
total=$(grep -rn "\.unwrap()" --include="*.rs" . 2>/dev/null | \
        grep -v "test" | \
        grep -v "target" | \
        grep -v "build.rs" | \
        wc -l | xargs)

echo -e "${YELLOW}Total unwrap() in production code: $total${NC}"
echo ""

# P0: Critical
p0_files="main\.rs\|lib\.rs\|error\.rs"
p0=$(grep -rn "\.unwrap()" --include="*.rs" . 2>/dev/null | \
     grep -v "test" | \
     grep -v "target" | \
     grep -v "build.rs" | \
     grep -E "$p0_files" | \
     wc -l | xargs)

if [ "$p0" -eq 0 ]; then
    echo -e "${GREEN}✅ P0 (Critical): $p0 unwraps${NC}"
else
    echo -e "${RED}❌ P0 (Critical): $p0 unwraps - MUST FIX${NC}"
fi

# P1: High priority
p1_patterns="redis\|postgres\|http\|grpc\|kafka\|auth\|jwt"
p1=$(grep -rn "\.unwrap()" --include="*.rs" . 2>/dev/null | \
     grep -v "test" | \
     grep -v "target" | \
     grep -v "build.rs" | \
     grep -E "$p1_patterns" | \
     wc -l | xargs)

if [ "$p1" -lt 10 ]; then
    echo -e "${GREEN}✅ P1 (High): $p1 unwraps${NC}"
elif [ "$p1" -lt 50 ]; then
    echo -e "${YELLOW}⚠️  P1 (High): $p1 unwraps${NC}"
else
    echo -e "${RED}❌ P1 (High): $p1 unwraps${NC}"
fi

# Calculate P2+P3
p2_p3=$((total - p0 - p1))
echo -e "${BLUE}📊 P2+P3 (Medium/Low): $p2_p3 unwraps${NC}"

echo ""
echo -e "${BLUE}=== Progress by Component ===${NC}"
echo ""

# Progress by major components
for service in auth-service user-service feed-service messaging-service streaming-service graphql-gateway; do
    if [ -d "$service" ]; then
        count=$(grep -rn "\.unwrap()" "$service/src" 2>/dev/null | \
                grep -v "test" | \
                wc -l | xargs || echo "0")

        if [ "$count" -eq 0 ]; then
            echo -e "${GREEN}✅ $service: $count${NC}"
        elif [ "$count" -lt 20 ]; then
            echo -e "${YELLOW}⚠️  $service: $count${NC}"
        else
            echo -e "${RED}❌ $service: $count${NC}"
        fi
    fi
done

echo ""
echo -e "${BLUE}=== Weekly Goal Tracking ===${NC}"
echo ""

# Calculate target reduction (assuming 6-week plan)
baseline=450  # Initial count
weeks_passed=0  # Update this manually or track in file

target_week_1=$((baseline - 20))  # P0 critical fixes
target_week_3=$((baseline - 100)) # P0 + P1 fixes
target_week_5=$((baseline - 250)) # P0 + P1 + P2 fixes
target_week_6=0                   # All fixed

echo "Week 1 Target: <$target_week_1 unwraps (Fix P0)"
echo "Week 3 Target: <$target_week_3 unwraps (Fix P0+P1)"
echo "Week 5 Target: <$target_week_5 unwraps (Fix P0+P1+P2)"
echo "Week 6 Target: $target_week_6 unwraps (Complete)"
echo ""

if [ "$total" -le "$target_week_6" ]; then
    echo -e "${GREEN}🎉 GOAL ACHIEVED! All unwraps removed!${NC}"
elif [ "$total" -le "$target_week_5" ]; then
    echo -e "${GREEN}✅ On track for Week 6 completion${NC}"
elif [ "$total" -le "$target_week_3" ]; then
    echo -e "${YELLOW}⚠️  Slightly behind - need to accelerate P2 fixes${NC}"
elif [ "$total" -le "$target_week_1" ]; then
    echo -e "${YELLOW}⚠️  Behind schedule - focus on P1 fixes${NC}"
else
    echo -e "${RED}❌ Significantly behind - need immediate action${NC}"
fi

echo ""
echo -e "${BLUE}=== Recent Changes ===${NC}"
echo ""

# Show recently modified files with unwraps
recent_unwraps=$(find . -name "*.rs" -type f -mtime -7 ! -path "*/target/*" -exec grep -l "\.unwrap()" {} \; 2>/dev/null | grep -v "test" || true)

if [ -n "$recent_unwraps" ]; then
    echo "Files modified in last 7 days with unwraps:"
    echo "$recent_unwraps" | while read -r file; do
        count=$(grep -c "\.unwrap()" "$file" 2>/dev/null || echo "0")
        echo "  - $file: $count unwraps"
    done
else
    echo -e "${GREEN}✅ No new files with unwraps in last 7 days${NC}"
fi

echo ""
echo -e "${BLUE}=== Next Actions ===${NC}"
echo ""

if [ "$p0" -gt 0 ]; then
    echo "1. 🚨 URGENT: Fix $p0 P0 critical unwraps"
    echo "   Run: grep -rn '\.unwrap()' --include='*.rs' . | grep -E 'main\.rs|lib\.rs'"
elif [ "$p1" -gt 50 ]; then
    echo "1. Fix high-priority P1 unwraps (currently: $p1)"
    echo "   Focus on: network operations, authentication paths"
elif [ "$p2_p3" -gt 100 ]; then
    echo "1. Continue with P2 business logic fixes"
    echo "   Use: ./scripts/fix-service-unwraps.sh [service-name]"
else
    echo "1. Final cleanup of remaining unwraps"
    echo "   Enable strict Clippy: cargo clippy -- -D clippy::unwrap_used"
fi

echo "2. Review: cat unwrap-analysis.md"
echo "3. Create issues: ./scripts/create-github-issues.sh"
echo "4. Track progress: ./scripts/unwrap-progress.sh (weekly)"

# Save progress to file for historical tracking
CSV_FILE="unwrap-progress.csv"
if touch "$CSV_FILE" 2>/dev/null; then
    echo "$(date +%Y-%m-%d),$total,$p0,$p1,$p2_p3" >> "$CSV_FILE"
    echo ""
    echo "Progress saved to $CSV_FILE"
else
    echo ""
    echo "⚠️  Could not save progress to CSV (check write permissions)"
fi