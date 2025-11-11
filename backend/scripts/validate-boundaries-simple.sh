#!/bin/bash
#
# Simplified Service Boundary Validation (macOS compatible)
#

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VIOLATIONS=0
WARNINGS=0

echo "🔍 Nova Service Boundary Validation"
echo "===================================="
echo ""

# Check 1: messaging-service 写 users 表 (BLOCKER)
echo "🔴 Check 1: messaging-service writing to users table"
echo "-----------------------------------------------------"

msg_writes=$(grep -r "INSERT INTO users\|UPDATE users SET" messaging-service/src --include="*.rs" 2>/dev/null | grep -v test | wc -l | xargs)

if [ "$msg_writes" != "0" ]; then
    echo -e "${RED}❌ BLOCKER: messaging-service writes to users table: $msg_writes times${NC}"
    grep -rn "INSERT INTO users\|UPDATE users SET" messaging-service/src --include="*.rs" 2>/dev/null | grep -v test | head -3
    ((VIOLATIONS++))
else
    echo -e "${GREEN}✅ No violations${NC}"
fi
echo ""

# Check 2: feed-service 读 posts 表
echo "🟡 Check 2: feed-service reading posts table"
echo "---------------------------------------------"

feed_reads=$(grep -r "FROM posts" feed-service/src --include="*.rs" 2>/dev/null | grep -v test | wc -l | xargs)

if [ "$feed_reads" != "0" ]; then
    echo -e "${YELLOW}⚠️  feed-service reads posts table: $feed_reads times${NC}"
    echo "   → Should use events + local projection"
    ((WARNINGS++))
else
    echo -e "${GREEN}✅ No direct DB access${NC}"
fi
echo ""

# Check 3: GraphQL Gateway sqlx 依赖
echo "🟡 Check 3: GraphQL Gateway database dependency"
echo "------------------------------------------------"

if grep -q "sqlx" graphql-gateway/Cargo.toml 2>/dev/null; then
    echo -e "${YELLOW}⚠️  GraphQL Gateway has sqlx dependency${NC}"
    echo "   → Should only use gRPC clients"
    ((WARNINGS++))
else
    echo -e "${GREEN}✅ No sqlx dependency${NC}"
fi
echo ""

# Check 4: users 表跨服务访问统计
echo "📊 Check 4: users table access statistics"
echo "------------------------------------------"

for svc in auth-service user-service messaging-service search-service streaming-service graphql-gateway; do
    if [ -d "$svc" ]; then
        count=$(grep -r "FROM users\|INTO users\|UPDATE users" $svc/src --include="*.rs" 2>/dev/null | grep -v test | wc -l | xargs)
        if [ "$count" != "0" ]; then
            echo "  $svc: $count queries"
        fi
    fi
done
echo ""

# Check 5: posts 表跨服务访问统计
echo "📊 Check 5: posts table access statistics"
echo "------------------------------------------"

for svc in content-service feed-service search-service user-service; do
    if [ -d "$svc" ]; then
        count=$(grep -r "FROM posts\|INTO posts\|UPDATE posts" $svc/src --include="*.rs" 2>/dev/null | grep -v test | wc -l | xargs)
        if [ "$count" != "0" ]; then
            echo "  $svc: $count queries"
        fi
    fi
done
echo ""

# Summary
echo "======================================"
echo "📊 SUMMARY"
echo "======================================"
echo ""

if [ $VIOLATIONS -gt 0 ]; then
    echo -e "${RED}❌ FAILED: $VIOLATIONS blocker(s) found${NC}"
    echo ""
    echo "Blocking issues MUST be fixed before production."
    echo ""
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  PASSED with $WARNINGS warning(s)${NC}"
    echo ""
    echo "Warnings should be addressed in refactoring."
    echo ""
    exit 0
else
    echo -e "${GREEN}✅ ALL CHECKS PASSED${NC}"
    echo ""
    exit 0
fi
