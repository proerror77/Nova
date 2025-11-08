#!/bin/bash
# 監控 GitHub Actions 部署並發送本地通知

set -e

REPO="proerror77/Nova"
WORKFLOW_RUN_ID="${1:-19186430682}"
POLL_INTERVAL=30  # 每 30 秒檢查一次

echo "🚀 開始監控部署: Workflow #${WORKFLOW_RUN_ID}"
echo "=================================="

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 發送系統通知
send_notification() {
    local title="$1"
    local message="$2"
    local status="$3"

    # macOS 通知
    if command -v osascript &> /dev/null; then
        osascript -e "display notification \"$message\" with title \"$title\""
    fi

    # Linux 通知
    if command -v notify-send &> /dev/null; then
        notify-send "$title" "$message"
    fi

    # 播放聲音
    if [ "$status" = "success" ]; then
        if command -v afplay &> /dev/null; then
            afplay /System/Library/Sounds/Glass.aiff &
        elif command -v paplay &> /dev/null; then
            paplay /usr/share/sounds/freedesktop/stereo/complete.oga &
        fi
    elif [ "$status" = "failure" ]; then
        if command -v afplay &> /dev/null; then
            afplay /System/Library/Sounds/Basso.aiff &
        elif command -v paplay &> /dev/null; then
            paplay /usr/share/sounds/freedesktop/stereo/dialog-error.oga &
        fi
    fi
}

# 連續監控
while true; do
    # 取得最新 workflow 狀態
    RESULT=$(gh run view "$WORKFLOW_RUN_ID" --repo "$REPO" --json status,conclusion,displayTitle 2>/dev/null || echo "")

    if [ -z "$RESULT" ]; then
        echo -e "${YELLOW}⏳ 等待 workflow 數據...${NC}"
        sleep $POLL_INTERVAL
        continue
    fi

    STATUS=$(echo "$RESULT" | jq -r '.status' 2>/dev/null || echo "unknown")
    CONCLUSION=$(echo "$RESULT" | jq -r '.conclusion' 2>/dev/null || echo "unknown")
    TITLE=$(echo "$RESULT" | jq -r '.displayTitle' 2>/dev/null || echo "Workflow")

    case "$STATUS" in
        "in_progress")
            echo -e "${BLUE}🔄 進行中...${NC} ($POLL_INTERVAL 秒後重新檢查)"
            sleep $POLL_INTERVAL
            ;;
        "completed")
            echo ""
            echo "=================================="
            echo -e "${GREEN}✅ Workflow 已完成！${NC}"
            echo "=================================="
            echo ""

            # 取得詳細信息
            DETAILED=$(gh run view "$WORKFLOW_RUN_ID" --repo "$REPO" 2>/dev/null)
            echo "$DETAILED"
            echo ""

            # 根據結果發送通知
            if [ "$CONCLUSION" = "success" ]; then
                echo -e "${GREEN}✅ 部署成功！${NC}"
                send_notification "🎉 部署完成" "Nova 所有服務已成功推送到 ECR" "success"

                # 檢查 Kubernetes 部署
                echo ""
                echo "檢查 Kubernetes 部署狀態..."
                kubectl get pods -A 2>/dev/null | grep -E "NAMESPACE|nova" || true

            elif [ "$CONCLUSION" = "failure" ]; then
                echo -e "${RED}❌ 部署失敗！${NC}"
                send_notification "❌ 部署失敗" "請檢查 GitHub Actions 日誌" "failure"

                # 顯示失敗的 jobs
                echo ""
                echo "失敗的任務："
                gh run view "$WORKFLOW_RUN_ID" --log-failed --repo "$REPO" 2>/dev/null | tail -50 || true

            else
                echo -e "${YELLOW}⚠️  狀態: $CONCLUSION${NC}"
                send_notification "⚠️ 部署狀態變更" "Workflow 已完成，狀態: $CONCLUSION" "warning"
            fi

            # 完成
            echo ""
            echo "=================================="
            echo "監控結束。按 Ctrl+C 退出。"
            echo "=================================="
            break
            ;;
        *)
            echo -e "${YELLOW}⏳ 狀態: $STATUS${NC}"
            sleep $POLL_INTERVAL
            ;;
    esac
done
