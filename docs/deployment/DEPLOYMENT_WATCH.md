# 🚀 自動部署監控指南

## 快速使用

### 方式 1: 監控最新的 workflow
```bash
cd /Users/proerror/Documents/nova
./scripts/watch-deployment.sh
```

### 方式 2: 使用別名 (需要重新開啟 Terminal)
```bash
watch-nova 19186430682        # 監控指定 workflow
watch-nova-latest             # 監控最新的 workflow
```

## 監控腳本功能

✅ **每 30 秒檢查一次** workflow 狀態  
✅ **完成時自動通知**:
   - 🔔 macOS 系統通知
   - 🔊 成功時播放 Glass.aiff
   - 🔊 失敗時播放 Basso.aiff

✅ **自動顯示**:
   - Workflow 完成狀態
   - 失敗任務的日誌
   - Kubernetes pods 部署狀態

## 工作流程

### 步驟 1: 推送代碼
```bash
git push origin main
```

### 步驟 2: 啟動監控
```bash
./scripts/watch-deployment.sh  # 會自動用最新 workflow ID
```

### 步驟 3: 等待通知
當 workflow 完成時，你會收到：
- 🔔 系統通知
- 🔊 聲音提醒
- 📊 詳細的部署摘要

## 範例

```
🚀 開始監控部署: Workflow #19186430682
==================================

🔄 進行中...
🔄 進行中...

==================================
✅ Workflow 已完成！
==================================

* main CI/CD Pipeline - Kubernetes/EKS · 19186430682

JOBS
✓ Test and Lint
✓ Build and Push Docker Images (all 11 services)
✓ Deploy to EKS Staging
✓ Smoke Tests
```

## 自訂設定

編輯 `scripts/watch-deployment.sh`:
- `POLL_INTERVAL=30` - 改為檢查間隔秒數
- 修改聲音檔案路徑以更換提醒音

## 故障排除

### 未收到通知
- macOS: 檢查系統偏好設定 > 通知 > Terminal
- Linux: 確保 notify-send 已安裝 (`apt install libnotify-bin`)

### 別名無法使用
```bash
source ~/.zshrc
# 或重新開啟 Terminal
```

