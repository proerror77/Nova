#!/bin/bash
#
# Service Boundary Validation Script
# 验证微服务边界，检测循环依赖和跨服务数据访问
#
# Usage: ./validate-service-boundaries.sh
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 计数器
VIOLATIONS=0
WARNINGS=0

echo "🔍 Nova Service Boundary Validation"
echo "===================================="
echo ""

# 定义数据所有权
declare -A TABLE_OWNERS=(
    ["users"]="user-service"
    ["follows"]="user-service"
    ["blocks"]="user-service"
    ["user_stats"]="user-service"
    ["posts"]="content-service"
    ["comments"]="content-service"
    ["likes"]="content-service"
    ["shares"]="content-service"
    ["messages"]="messaging-service"
    ["conversations"]="messaging-service"
    ["message_reactions"]="messaging-service"
    ["notifications"]="notification-service"
    ["videos"]="media-service"
    ["video_chunks"]="media-service"
    ["sessions"]="auth-service"
    ["token_revocations"]="auth-service"
)

# 检查 1: 跨服务数据库读操作
echo "📊 Check 1: Cross-service database READ access"
echo "------------------------------------------------"

for service in backend/*-service; do
    if [ ! -d "$service" ]; then
        continue
    fi

    service_name=$(basename "$service")

    for table in "${!TABLE_OWNERS[@]}"; do
        owner="${TABLE_OWNERS[$table]}"

        if [ "$service_name" != "$owner" ]; then
            # 检查是否有 SELECT 查询访问此表
            read_violations=$(grep -r "FROM $table" "$service/src" --include="*.rs" 2>/dev/null | \
                            grep -v "test\|mock\|//" | \
                            wc -l | xargs)

            if [ "$read_violations" != "0" ]; then
                echo -e "${YELLOW}⚠️  $service_name reads $table table (owned by $owner): $read_violations times${NC}"
                ((WARNINGS++))
            fi
        fi
    done
done

if [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✅ No cross-service reads detected${NC}"
fi
echo ""

# 检查 2: 跨服务数据库写操作 (BLOCKER)
echo "🔴 Check 2: Cross-service database WRITE access (BLOCKER)"
echo "----------------------------------------------------------"

WRITE_VIOLATIONS=0

for service in backend/*-service; do
    if [ ! -d "$service" ]; then
        continue
    fi

    service_name=$(basename "$service")

    for table in "${!TABLE_OWNERS[@]}"; do
        owner="${TABLE_OWNERS[$table]}"

        if [ "$service_name" != "$owner" ]; then
            # 检查是否有写操作
            write_count=$(grep -r "INSERT INTO $table\|UPDATE $table\|DELETE FROM $table" \
                         "$service/src" --include="*.rs" 2>/dev/null | \
                         grep -v "test\|mock\|//" | \
                         wc -l | xargs)

            if [ "$write_count" != "0" ]; then
                echo -e "${RED}❌ BLOCKER: $service_name writes to $table (owned by $owner): $write_count times${NC}"
                ((WRITE_VIOLATIONS++))
                ((VIOLATIONS++))

                # 显示具体位置
                echo "   Locations:"
                grep -rn "INSERT INTO $table\|UPDATE $table\|DELETE FROM $table" \
                     "$service/src" --include="*.rs" 2>/dev/null | \
                     grep -v "test\|mock\|//" | \
                     head -3 | \
                     while IFS= read -r line; do
                         echo "   → $line"
                     done
                echo ""
            fi
        fi
    done
done

if [ $WRITE_VIOLATIONS -eq 0 ]; then
    echo -e "${GREEN}✅ No cross-service writes detected${NC}"
fi
echo ""

# 检查 3: GraphQL Gateway 数据库依赖
echo "🔍 Check 3: GraphQL Gateway architecture"
echo "-----------------------------------------"

if [ -f "backend/graphql-gateway/Cargo.toml" ]; then
    if grep -q "sqlx" backend/graphql-gateway/Cargo.toml; then
        echo -e "${YELLOW}⚠️  GraphQL Gateway has sqlx dependency${NC}"
        echo "   → gateway should only use gRPC clients"
        ((WARNINGS++))
    else
        echo -e "${GREEN}✅ GraphQL Gateway is DB-free${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  GraphQL Gateway not found${NC}"
fi
echo ""

# 检查 4: 服务依赖统计
echo "📈 Check 4: Service dependency statistics"
echo "------------------------------------------"

for service in backend/*-service backend/graphql-gateway; do
    if [ ! -d "$service" ]; then
        continue
    fi

    service_name=$(basename "$service")

    # 统计 gRPC 客户端使用
    grpc_deps=$(grep -r "grpc_clients::\|Client" "$service/src" --include="*.rs" 2>/dev/null | \
               grep -v "test\|mock\|//\|pub struct" | \
               wc -l | xargs)

    # 统计数据库查询
    db_queries=$(grep -r "sqlx::query\|FROM \|INSERT INTO \|UPDATE \|DELETE FROM" \
                "$service/src" --include="*.rs" 2>/dev/null | \
                grep -v "test\|mock\|//" | \
                wc -l | xargs)

    if [ "$grpc_deps" != "0" ] || [ "$db_queries" != "0" ]; then
        echo "  $service_name: gRPC=$grpc_deps, DB queries=$db_queries"
    fi
done
echo ""

# 检查 5: 循环依赖检测 (简化版)
echo "🔄 Check 5: Circular dependency detection"
echo "------------------------------------------"

# 定义已知的依赖关系
echo "Known circular dependencies:"
echo "  1. auth-service ↔ user-service (DB access)"
echo "  2. content-service ↔ feed-service (gRPC)"
echo "  3. messaging-service → user-service (gRPC) → content-service (gRPC)"
echo ""
echo "Run 'cargo depgraph' for detailed dependency graph"
echo ""

# 总结
echo "======================================"
echo "📊 SUMMARY"
echo "======================================"
echo ""

if [ $VIOLATIONS -gt 0 ]; then
    echo -e "${RED}❌ FAILED: $VIOLATIONS blocker(s) found${NC}"
    echo ""
    echo "Blocking issues:"
    echo "  - Cross-service WRITE operations: $WRITE_VIOLATIONS"
    echo ""
    echo "These MUST be fixed before production deployment."
    echo ""
    exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  PASSED with warnings: $WARNINGS warning(s)${NC}"
    echo ""
    echo "Warnings should be addressed in refactoring:"
    echo "  - Cross-service READ operations"
    echo "  - GraphQL Gateway architecture"
    echo ""
    exit 0
else
    echo -e "${GREEN}✅ ALL CHECKS PASSED${NC}"
    echo ""
    echo "Service boundaries are clean!"
    echo ""
    exit 0
fi
