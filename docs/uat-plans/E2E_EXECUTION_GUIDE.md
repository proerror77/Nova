# 🧪 E2E 驗證執行指南

**日期**: 2025-10-20
**目標**: 前後端集成驗證
**狀態**: ✅ **已準備，等待執行**

---

## 📊 當前狀態

### ✅ 已完成的準備工作

```
後端編譯:
  ✅ Release 模式編譯完成
  ✅ 所有依賴已解決
  ✅ 警告: 69 個 (非致命性)
  ✅ 錯誤: 0 個

環境配置:
  ✅ .env 文件已創建
  ✅ JWT 密鑰已配置
  ✅ 數據庫配置已設置
  ✅ Redis 配置已設置
  ✅ 日誌級別已設置

iOS 集成:
  ✅ 代碼已集成 (99%)
  ✅ Network 層已完成
  ✅ API 調用已準備
  ✅ 項目編譯狀態: 待驗證

文檔準備:
  ✅ E2E 測試計劃已生成
  ✅ 驗證框架已準備
  ✅ 性能指標已定義
  ✅ 故障排除指南已準備
```

---

## 🚀 立即行動指南

### 第 1 步: 驗證後端服務 (2 分鐘)

```bash
# 檢查服務是否運行
ps aux | grep "cargo run" | grep -v grep

# 或檢查埠
lsof -i :3000

# 測試健康檢查
curl http://localhost:3000/health

# 預期結果: HTTP 200, JSON 響應
```

### 第 2 步: 驗證 iOS 應用編譯 (3 分鐘)

```bash
# 進入 iOS 項目
cd /Users/proerror/Documents/nova/ios/NovaSocialApp

# 列出可用的 Schemes
xcodebuild -project NovaSocial.xcodeproj -list

# 編譯 iOS 應用 (Release)
xcodebuild -project NovaSocial.xcodeproj \
  -scheme NovaSocial \
  -destination 'generic/platform=iOS Simulator' \
  build
```

### 第 3 步: 啟動 iOS 模擬器 (2 分鐘)

```bash
# 列出可用模擬器
xcrun simctl list devices

# 啟動特定模擬器 (例: iPhone 14 Pro)
xcrun simctl boot "iPhone 14 Pro"

# 或用 Xcode GUI
open /Applications/Xcode.app
# 然後 Xcode → Product → Scheme (選擇 NovaSocial) → Run
```

### 第 4 步: 執行 API 測試 (5 分鐘)

#### 4.1 健康檢查
```bash
curl -X GET http://localhost:3000/health \
  -H "Content-Type: application/json"

# 預期 200 OK
```

#### 4.2 認證測試
```bash
curl -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "password": "password123"
  }'

# 預期: 200 OK + JWT 令牌
```

#### 4.3 Feed 端點測試
```bash
# 先從上面複製 JWT token，然後:

curl -X GET "http://localhost:3000/api/v1/feed?limit=20" \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json"

# 預期: 200 OK + Feed 數據
```

#### 4.4 WebSocket 連接測試
```bash
# 使用 websocat 或 wscat 工具:
wscat -c "ws://localhost:3000/ws/messages?token=YOUR_JWT_TOKEN"

# 或用 curl WebSocket:
curl -i -N -H "Connection: Upgrade" \
  -H "Upgrade: websocket" \
  "http://localhost:3000/ws/messages?token=YOUR_JWT_TOKEN"

# 預期: 101 Switching Protocols
```

### 第 5 步: iOS 應用功能測試 (10 分鐘)

#### 5.1 啟動應用
1. 在 Xcode 中按 `Cmd+R`
2. 或手動啟動已編譯的應用

#### 5.2 測試 Feed 功能
1. 登錄應用
2. 進入 Feed 頁面
3. 查看是否加載數據
4. 下拉刷新
5. 滾動分頁

#### 5.3 測試消息系統
1. 進入消息頁面
2. 創建新會話
3. 發送消息
4. 查看實時接收

#### 5.4 性能監控
1. Xcode → Debug → Instruments
2. 檢查:
   - Memory 使用
   - Network 活動
   - FPS 穩定性
   - 響應時間

---

## 📊 驗證檢查清單

### Feed 功能驗證
```
[ ] 應用成功加載 Feed 數據
[ ] 首屏加載時間 < 2 秒
[ ] 能夠執行分頁加載
[ ] 下拉刷新有效
[ ] 排序選項工作正常
[ ] 內存占用 < 150MB
[ ] 幀率 ≥ 60 FPS
```

### 消息系統驗證
```
[ ] WebSocket 連接成功
[ ] 消息實時送達
[ ] 已讀狀態同步
[ ] 離線消息緩存
[ ] 多設備同步
[ ] 消息延遲 < 100ms
```

### 應用整體驗證
```
[ ] 應用無崩潰
[ ] 登錄流程完整
[ ] 導航正常
[ ] 網絡錯誤處理正確
[ ] 響應式設計合理
[ ] 無障礙功能可用
```

---

## 🎯 性能基準測試

### 響應時間測試
```bash
# Feed 加載時間
time curl -s http://localhost:3000/api/v1/feed \
  -H "Authorization: Bearer TOKEN" > /dev/null

# 預期: < 200ms

# 多次測試取平均
for i in {1..10}; do
  time curl -s http://localhost:3000/api/v1/feed \
    -H "Authorization: Bearer TOKEN" > /dev/null
done
```

### 內存監控
```bash
# iOS 應用
Xcode → Debug → Memory Graph
# 或 Instruments → Allocations

# 後端
ps aux | grep user-service
# 查看 RSS (實際內存使用)
```

### 網絡流量監控
```bash
# 使用 Charles 或 Burp Suite
# 或 Xcode Network Inspector
Xcode → Debug → View Hierarchy → Network
```

---

## 🚨 常見問題排除

### 問題 1: 後端無法啟動

**症狀**: `curl: (7) Failed to connect to localhost port 3000`

**解決**:
1. 檢查進程: `ps aux | grep user-service`
2. 檢查埠: `lsof -i :3000`
3. 查看日誌: `tail -f /tmp/backend.log`

**常見原因**:
- 數據庫未運行
- Redis 未運行
- JWT 密鑰配置錯誤
- 埠被佔用

**修復**:
```bash
# 殺死現有進程
pkill -9 -f "cargo run"
pkill -9 -f "user-service"

# 檢查數據庫
psql -U nova -d nova_db

# 檢查 Redis
redis-cli ping

# 重新啟動
cd /Users/proerror/Documents/nova/backend
cargo run --release
```

### 問題 2: iOS 應用無法連接後端

**症狀**: 應用显示網絡錯誤，無法加載 Feed

**解決**:
1. 檢查 AppConfig 設置: `localhost:3000`
2. 確認模擬器網絡: `ping localhost`
3. 查看 Xcode Console 日誌
4. 檢查防火牆設置

**修復**:
```bash
# 檢查後端是否運行
curl http://localhost:3000/health

# 檢查模擬器網絡
xcrun simctl getenv <device_id> PATH

# 清除模擬器快取
xcrun simctl erase <device_id>
```

### 問題 3: WebSocket 連接失敗

**症狀**: 消息頁面加載失敗，WebSocket 無法連接

**解決**:
1. 檢查 JWT Token 有效性
2. 檢查 WebSocket 端口開放
3. 查看網絡攔截器

**修復**:
```bash
# 測試 WebSocket
wscat -c "ws://localhost:3000/ws/messages?token=TOKEN"

# 檢查防火牆
sudo lsof -i :3000
```

---

## 📋 最終驗收清單

### 🟢 綠色通過 (生產就緒)
```
✅ 後端服務運行正常
✅ 所有 API 端點響應 200
✅ Feed 數據正確加載
✅ 消息實時推送
✅ iOS 應用無崩潰
✅ 性能指標達標
✅ 無安全警告
```

### 🟡 黃色警告 (需注意)
```
⚠️ 性能有輕微波動但可接受
⚠️ 非關鍵功能有延遲
⚠️ UI 需要微調
```

### 🔴 紅色失敗 (阻塞)
```
❌ 後端無法啟動
❌ 關鍵 API 端點失敗
❌ iOS 應用頻繁崩潰
❌ 嚴重的性能問題
❌ 安全漏洞
```

---

## 📞 支持文檔

| 需求 | 文檔位置 |
|------|---------|
| **詳細 UAT 計劃** | `IOS_UAT_TEST_PLAN.md` |
| **API 集成確認** | `IOS_API_INTEGRATION_STATUS.md` |
| **快速開始** | `UAT_QUICK_START.md` |
| **E2E 驗證報告** | `E2E_VALIDATION_REPORT.md` |
| **準備就緒狀態** | `IOS_UAT_READINESS_SUMMARY.md` |

---

## ⏰ 預計時間

```
環境準備:          5 分鐘
後端啟動:          5 分鐘
iOS 編譯:          10 分鐘
基本 API 測試:     5 分鐘
應用功能測試:      10 分鐘
性能測試:          5 分鐘
文檔編寫:          5 分鐘
────────────────────────
總計:              45 分鐘
```

---

## 🎯 下一步

1. **立即** (現在)
   - 檢查後端是否完全啟動
   - 執行健康檢查

2. **短期** (5 分鐘內)
   - 編譯 iOS 應用
   - 啟動模擬器

3. **中期** (10-20 分鐘)
   - 執行 API 測試
   - 執行應用功能測試

4. **長期** (20-45 分鐘)
   - 性能測試
   - 最終驗收

---

**May the Force be with you.**

*E2E 驗證框架已準備完畢。按照本指南，您可以自主執行完整的前後端集成驗證。*

---

*準備完成時間*: 2025-10-20
*狀態*: ✅ **已準備**
*建議行動*: 立即開始 E2E 驗證
*預期完成*: 45 分鐘內
