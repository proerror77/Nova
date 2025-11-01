#!/bin/bash

# Nova 後端系統集成測試框架
# 目的: 驗證所有服務的整合狀況

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 測試結果統計
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# 測試報告文件
REPORT_FILE="/tmp/nova_integration_test_report_$(date +%Y%m%d_%H%M%S).md"

# 函數: 打印測試標題
print_test_header() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

# 函數: 測試通過
test_pass() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo -e "${GREEN}✅ PASS${NC}: $1"
    echo "- ✅ PASS: $1" >> "$REPORT_FILE"
}

# 函數: 測試失敗
test_fail() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo -e "${RED}❌ FAIL${NC}: $1"
    echo "  原因: $2"
    echo "- ❌ FAIL: $1" >> "$REPORT_FILE"
    echo "  - 原因: $2" >> "$REPORT_FILE"
}

# 函數: 測試跳過
test_skip() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
    echo -e "${YELLOW}⚠️  SKIP${NC}: $1"
    echo "  原因: $2"
    echo "- ⚠️ SKIP: $1" >> "$REPORT_FILE"
    echo "  - 原因: $2" >> "$REPORT_FILE"
}

# 初始化報告
init_report() {
    cat > "$REPORT_FILE" << 'HEADER'
# Nova 後端系統集成測試報告

**測試日期**: $(date)
**測試環境**: Kubernetes (nova-eks)

---

## 測試結果摘要

HEADER
}

# 完成報告
finalize_report() {
    local pass_rate=$(awk "BEGIN {printf \"%.1f\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")
    
    cat >> "$REPORT_FILE" << SUMMARY

| 指標 | 數值 |
|------|------|
| 總測試數 | $TOTAL_TESTS |
| 通過 | $PASSED_TESTS |
| 失敗 | $FAILED_TESTS |
| 跳過 | $SKIPPED_TESTS |
| 通過率 | ${pass_rate}% |

---

## 詳細測試結果

SUMMARY

    echo ""
    echo -e "${BLUE}測試報告已保存到: ${NC}$REPORT_FILE"
}

#=============================================================================
# 測試 1: 環境變量配置測試
#=============================================================================
test_env_vars() {
    print_test_header "環境變量配置測試"
    
    echo "## 1. 環境變量配置測試" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    for service in auth user content feed media messaging search streaming; do
        yaml_file="k8s/infrastructure/base/${service}-service.yaml"
        
        if [ ! -f "$yaml_file" ]; then
            test_skip "$service-service" "YAML 文件不存在"
            continue
        fi
        
        # 檢查必需的環境變量
        local has_db=$(grep -q "name: DATABASE_URL" "$yaml_file" && echo "yes" || echo "no")
        local has_redis=$(grep -q "name: REDIS_URL" "$yaml_file" && echo "yes" || echo "no")
        
        if [ "$has_db" = "yes" ] && [ "$has_redis" = "yes" ]; then
            test_pass "$service-service 環境變量配置"
        else
            test_fail "$service-service 環境變量配置" "缺少 DATABASE_URL 或 REDIS_URL"
        fi
    done
}

#=============================================================================
# 測試 2: 資料庫 Schema 測試
#=============================================================================
test_database_schemas() {
    print_test_header "資料庫 Schema 測試"
    
    echo "" >> "$REPORT_FILE"
    echo "## 2. 資料庫 Schema 測試" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    for service in auth user content feed media messaging search streaming; do
        migrations_dir="backend/${service}-service/migrations"
        
        if [ -d "$migrations_dir" ]; then
            local count=$(find "$migrations_dir" -name "*.sql" 2>/dev/null | wc -l | tr -d ' ')
            test_pass "$service-service 有 migrations 目錄 ($count 個文件)"
        else
            test_fail "$service-service Schema" "缺少 migrations 目錄"
        fi
    done
}

#=============================================================================
# 測試 3: JWT 整合測試
#=============================================================================
test_jwt_integration() {
    print_test_header "JWT 整合測試"
    
    echo "" >> "$REPORT_FILE"
    echo "## 3. JWT 整合測試" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 檢查 auth-service 有私鑰
    if grep -q "JWT_PRIVATE_KEY_PEM" "k8s/infrastructure/base/auth-service.yaml"; then
        test_pass "auth-service 配置 JWT 私鑰"
    else
        test_fail "auth-service JWT 配置" "缺少 JWT_PRIVATE_KEY_PEM"
    fi
    
    # 檢查需要驗證的服務有公鑰
    for service in user content messaging media; do
        if grep -q "JWT_PUBLIC_KEY_PEM" "k8s/infrastructure/base/${service}-service.yaml"; then
            test_pass "$service-service 配置 JWT 公鑰"
        else
            test_fail "$service-service JWT 配置" "缺少 JWT_PUBLIC_KEY_PEM"
        fi
    done
}

#=============================================================================
# 測試 4: S3 整合測試
#=============================================================================
test_s3_integration() {
    print_test_header "S3 整合測試"
    
    echo "" >> "$REPORT_FILE"
    echo "## 4. S3 整合測試" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    yaml_file="k8s/infrastructure/base/media-service.yaml"
    
    local has_bucket=$(grep -q "name: S3_BUCKET" "$yaml_file" && echo "yes" || echo "no")
    local has_region=$(grep -q "name: AWS_REGION" "$yaml_file" && echo "yes" || echo "no")
    local has_key=$(grep -q "name: AWS_ACCESS_KEY_ID" "$yaml_file" && echo "yes" || echo "no")
    local has_secret=$(grep -q "name: AWS_SECRET_ACCESS_KEY" "$yaml_file" && echo "yes" || echo "no")
    
    if [ "$has_bucket" = "yes" ] && [ "$has_region" = "yes" ] && [ "$has_key" = "yes" ] && [ "$has_secret" = "yes" ]; then
        test_pass "media-service S3 整合配置"
    else
        test_fail "media-service S3 配置" "缺少 S3 環境變量"
    fi
}

#=============================================================================
# 測試 5: K8s 資源檢查
#=============================================================================
test_k8s_resources() {
    print_test_header "Kubernetes 資源檢查"
    
    echo "" >> "$REPORT_FILE"
    echo "## 5. Kubernetes 資源檢查" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # 檢查 kubectl 是否可用
    if ! command -v kubectl &> /dev/null; then
        test_skip "Kubernetes 資源檢查" "kubectl 未安裝"
        return
    fi
    
    # 檢查各個服務的 Deployment
    for service in auth user content feed media messaging search streaming; do
        if kubectl get deployment "${service}-service" -n nova &> /dev/null; then
            test_pass "$service-service Deployment 存在"
        else
            test_fail "$service-service Deployment" "Deployment 不存在"
        fi
    done
    
    # 檢查基礎設施
    for infra in postgres redis elasticsearch; do
        if kubectl get deployment "$infra" -n nova &> /dev/null; then
            test_pass "$infra Deployment 存在"
        else
            test_fail "$infra Deployment" "Deployment 不存在"
        fi
    done
}

#=============================================================================
# 測試 6: Secrets 配置檢查
#=============================================================================
test_secrets() {
    print_test_header "Kubernetes Secrets 檢查"
    
    echo "" >> "$REPORT_FILE"
    echo "## 6. Kubernetes Secrets 檢查" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    if ! command -v kubectl &> /dev/null; then
        test_skip "Secrets 檢查" "kubectl 未安裝"
        return
    fi
    
    # 檢查關鍵 Secrets
    for secret in nova-db-credentials nova-jwt-keys nova-s3-credentials; do
        if kubectl get secret "$secret" -n nova &> /dev/null; then
            test_pass "Secret $secret 存在"
        else
            test_fail "Secret $secret" "Secret 不存在"
        fi
    done
}

#=============================================================================
# 主測試流程
#=============================================================================
main() {
    echo -e "${GREEN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║       Nova 後端系統集成測試框架                               ║"
    echo "║                                                              ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    init_report
    
    # 執行所有測試
    test_env_vars
    test_database_schemas
    test_jwt_integration
    test_s3_integration
    test_k8s_resources
    test_secrets
    
    # 生成最終報告
    finalize_report
    
    # 打印測試總結
    echo ""
    echo -e "${BLUE}===================================================${NC}"
    echo -e "${BLUE}  測試總結${NC}"
    echo -e "${BLUE}===================================================${NC}"
    echo -e "總測試數: ${TOTAL_TESTS}"
    echo -e "${GREEN}通過: ${PASSED_TESTS}${NC}"
    echo -e "${RED}失敗: ${FAILED_TESTS}${NC}"
    echo -e "${YELLOW}跳過: ${SKIPPED_TESTS}${NC}"
    
    local pass_rate=$(awk "BEGIN {printf \"%.1f\", ($PASSED_TESTS/$TOTAL_TESTS)*100}")
    echo -e "通過率: ${pass_rate}%"
    echo ""
    
    # 根據通過率返回適當的退出碼
    if [ "$FAILED_TESTS" -eq 0 ]; then
        echo -e "${GREEN}🎉 所有測試通過!${NC}"
        exit 0
    else
        echo -e "${RED}⚠️  有 $FAILED_TESTS 個測試失敗${NC}"
        exit 1
    fi
}

# 執行主函數
main
