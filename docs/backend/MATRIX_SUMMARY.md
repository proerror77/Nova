# Matrix E2EE 整合總結

**日期**: 2025-12-09
**狀態**: ✅ 基礎架構完成，準備好進行業務邏輯整合

---

## 🎯 完成的工作

### 1. Matrix Synapse 部署 (GKE nova-staging)

| 項目 | 狀態 | 詳情 |
|------|------|------|
| Synapse Pod | ✅ Running | `matrix-synapse-6d9f45b4c9-pzq4x` |
| PostgreSQL DB | ✅ 已建立 | database: `synapse` |
| Service Account | ✅ 已註冊 | `@nova-service:staging.nova.internal` |
| Access Token | ✅ 已產生 | 儲存在 `nova-matrix-service-token` Secret |
| Health Check | ✅ 通過 | `http://matrix-synapse:8008/health` → OK |

**連線資訊** (已配置在 ConfigMap):
```bash
MATRIX_ENABLED=false (預設關閉，啟用時改為 true)
# IMPORTANT: MATRIX_HOMESERVER_URL 必須與 MATRIX_PUBLIC_URL 指向同一套 Synapse，
# 否則 sync 會看不到 client 建的 room / event。
MATRIX_HOMESERVER_URL=https://matrix.staging.gcp.icered.com
MATRIX_SERVICE_USER=@nova-service:staging.gcp.icered.com
MATRIX_SERVER_NAME=staging.gcp.icered.com
MATRIX_DEVICE_NAME=nova-realtime-chat-service
```

**Access Token** (在 Secret 中):
```
MATRIX_ACCESS_TOKEN=syt_bm92YS1zZXJ2aWNl_fvxysrZSJjIkuqsZtmiL_2lTBn4
```

### 2. 程式碼整合 (realtime-chat-service)

#### 已建立/修改的檔案

| 檔案 | 狀態 | 用途 |
|------|------|------|
| `Cargo.toml` | ✅ 已更新 | 添加 `matrix-sdk` 和 `ruma` 依賴 |
| `src/services/matrix_client.rs` | ✅ 新建 | Matrix 客戶端封裝（355 行） |
| `src/services/mod.rs` | ✅ 已更新 | 匯出 `matrix_client` 模組 |
| `src/state.rs` | ✅ 已更新 | 添加 `matrix_client: Option<Arc<MatrixClient>>` |
| `src/main.rs` | ✅ 已更新 | 初始化 Matrix 客戶端 |
| `src/config.rs` | ✅ 已存在 | `MatrixConfig` 結構體 |
| `migrations/0012_matrix_room_mapping.sql` | ✅ 新建 | DB schema 更新 |

#### 核心功能 (已實現)

**`MatrixClient` 提供的 API**:
- ✅ `new(config)` - 初始化並登入
- ✅ `get_or_create_room(conversation_id, participants)` - 建立/取得 room
- ✅ `send_message(conversation_id, room_id, text)` - 發送文字訊息
- ✅ `send_media(conversation_id, room_id, url, type, filename)` - 發送附件
- ✅ `delete_message(room_id, event_id, reason)` - 刪除訊息 (redaction)
- ✅ `edit_message(room_id, event_id, new_text)` - 編輯訊息 (replacement)
- ✅ `start_sync(event_handler)` - 啟動 sync loop
- ✅ `cache_room_mapping()` / `get_cached_room_id()` - 記憶體快取

**資料庫 Schema**:
```sql
-- 對話 <-> Matrix room 映射
CREATE TABLE matrix_room_mapping (
    conversation_id UUID PRIMARY KEY,
    matrix_room_id TEXT UNIQUE,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
);

-- messages 表新增欄位
ALTER TABLE messages ADD COLUMN matrix_event_id TEXT;
```

### 3. 文檔

| 文檔 | 位置 | 內容 |
|------|------|------|
| 部署資訊 | `backend/MATRIX_DEPLOYMENT_INFO.md` | Synapse 連線資訊、驗證步驟、故障排除 |
| 整合指南 | `backend/MATRIX_INTEGRATION_GUIDE.md` | 完整的實現指南（待完成工作、範例程式碼） |
| 總結文檔 | `backend/MATRIX_SUMMARY.md` | 本文檔 |

---

## 📋 下一步工作

### Phase 1: 訊息發送整合 (優先)

**目標**: 發送訊息時同時寫入 DB 和 Matrix

**需要修改的檔案**:
1. `src/routes/messages.rs` 或 `src/services/message_service.rs`
2. 新增 `src/services/matrix_db.rs` (資料庫輔助函數)

**工作項目**:
- [ ] 實現 `get_conversation_participants()`
- [ ] 實現 `save_room_mapping()` / `load_room_mapping()`
- [ ] 更新 `send_message` 端點整合 Matrix
- [ ] 更新 `send_audio_message` 端點整合 Matrix
- [ ] 錯誤處理：Matrix 失敗不應阻塞訊息發送

**預估時間**: 4-6 小時

### Phase 2: 訊息接收 (Matrix Sync Loop)

**目標**: 接收其他用戶在 Matrix 發送的訊息，推送給 WebSocket

**需要新增的檔案**:
1. `src/services/matrix_event_handler.rs`

**工作項目**:
- [ ] 在 `main.rs` 啟動 Matrix sync loop
- [ ] 實現 `handle_matrix_message()` 處理 sync events
- [ ] 實現 `lookup_conversation_by_room_id()`
- [ ] 實現 `extract_user_id_from_matrix()`
- [ ] 透過 `registry.broadcast_to_conversation()` 推送

**預估時間**: 3-4 小時

### Phase 3: 編輯/刪除訊息

**工作項目**:
- [ ] 更新刪除訊息端點整合 Matrix redaction
- [ ] 實現編輯訊息端點 (新增 PATCH)
- [ ] 實現 `get_matrix_info()` 輔助函數

**預估時間**: 2-3 小時

### Phase 4: Room 管理

**工作項目**:
- [ ] 建立對話時自動建立 Matrix room
- [ ] 添加成員時邀請加入 Matrix room
- [ ] 實現 `invite_user_to_room()`

**預估時間**: 2-3 小時

### Phase 5: 測試與優化

**工作項目**:
- [ ] 單元測試 (matrix_client, matrix_db)
- [ ] 整合測試 (端對端流程)
- [ ] 效能測試 (大量訊息)
- [ ] 錯誤場景測試 (Matrix 不可用)
- [ ] 添加 Prometheus metrics

**預估時間**: 4-6 小時

---

## 🚀 啟用 Matrix 的步驟

### Staging 環境

```bash
# 1. 確認 Synapse 運行中
kubectl get pods -n nova-staging -l app=matrix-synapse
# 應該顯示 Running

# 2. 執行 DB migration (如果還沒執行)
kubectl exec -n nova-staging deploy/realtime-chat-service -- \
  sqlx migrate run

# 3. 啟用 Matrix
kubectl patch configmap realtime-chat-service-config -n nova-staging \
  --type merge -p '{"data":{"MATRIX_ENABLED":"true"}}'

# 4. 重啟服務
kubectl rollout restart deployment/realtime-chat-service -n nova-staging

# 5. 檢查日誌確認初始化成功
kubectl logs -n nova-staging -l app=realtime-chat-service --tail=100 | grep -i matrix

# 預期輸出：
# ✅ Matrix client initialized for homeserver: http://matrix-synapse:8008
```

### 驗證測試

```bash
# 1. 健康檢查
kubectl exec -n nova-staging deploy/matrix-synapse -- \
  curl -s http://localhost:8008/health
# 預期: OK

# 2. 驗證 access token
kubectl exec -n nova-staging deploy/matrix-synapse -- sh -c "
  curl -s -H 'Authorization: Bearer syt_bm92YS1zZXJ2aWNl_fvxysrZSJjIkuqsZtmiL_2lTBn4' \
    http://localhost:8008/_matrix/client/v3/account/whoami
"
# 預期: {"user_id":"@nova-service:staging.nova.internal","is_guest":false}

# 3. 檢查 realtime-chat-service 環境變數
kubectl exec -n nova-staging deploy/realtime-chat-service -- env | grep MATRIX
```

---

## ⚠️ 注意事項

### 1. 雙寫策略

當前設計採用 **雙寫模式**:
- 訊息同時寫入 Nova DB 和 Matrix
- Nova DB 作為主要儲存
- Matrix 提供 E2EE 和跨平台互通

**優點**:
- 漸進式遷移，不破壞現有功能
- Nova 保留完整資料控制權
- 可隨時關閉 Matrix (fallback)

**缺點**:
- 雙倍寫入開銷
- 需要維護一致性

### 2. 錯誤處理原則

**關鍵**: Matrix 失敗不應阻塞訊息發送

```rust
// ✅ 正確做法
if let Some(matrix_client) = &state.matrix_client {
    if let Err(e) = matrix_client.send_message(...).await {
        tracing::error!(error = %e, "Matrix send failed, continuing");
        // 記錄失敗，但不返回錯誤
    }
}

// ❌ 錯誤做法
matrix_client.send_message(...).await?; // 失敗會中斷整個流程
```

### 3. Room Mapping 快取

`MatrixClient` 內部使用記憶體快取，但重啟後會丟失。

**解決方案**:
- 啟動時從 DB 載入所有 room mapping
- 或使用 Redis 作為分散式快取

### 4. 效能考量

- Matrix sync loop 是長連接，不會產生額外 CPU 負擔
- 發送訊息需要額外的 HTTP 請求（可接受）
- 建議監控 Matrix homeserver 負載

---

## 📊 架構圖

```
┌─────────────┐
│   Frontend  │
│  (WebSocket)│
└──────┬──────┘
       │
       ▼
┌──────────────────────────────────┐
│   realtime-chat-service          │
│                                  │
│  ┌────────────┐  ┌────────────┐ │
│  │ AppState   │  │ MatrixClient│ │
│  │            │  └─────┬───────┘ │
│  │ - db       │        │         │
│  │ - matrix ──┼────────┘         │
│  │ - registry │                  │
│  └────┬───────┘                  │
│       │                          │
│  ┌────▼────────┐                 │
│  │ MessageService                │
│  │                               │
│  │ send_message() {              │
│  │   1. 寫入 DB                  │
│  │   2. 發送到 Matrix            │
│  │   3. WS 推播                  │
│  │ }                             │
│  └────┬──────────────────────────┘
│       │                     │
└───────┼─────────────────────┼─────┘
        │                     │
        ▼                     ▼
  ┌──────────┐     ┌─────────────────┐
  │ Postgres │     │ Matrix Synapse  │
  │          │     │                 │
  │ - messages     │ - rooms         │
  │ - matrix_      │ - events        │
  │   room_        │ - E2EE keys     │
  │   mapping      │                 │
  └──────────┘     └─────────────────┘
```

---

## 🔗 快速連結

- [Matrix 部署資訊](./MATRIX_DEPLOYMENT_INFO.md) - 連線參數、驗證步驟
- [整合指南](./MATRIX_INTEGRATION_GUIDE.md) - 詳細實現指南、範例程式碼
- [Matrix SDK 文檔](https://docs.rs/matrix-sdk) - 官方 API 文檔

---

## ✅ 總結

**已完成**:
- ✅ Matrix Synapse 成功部署在 GKE nova-staging
- ✅ 基礎架構程式碼完成（Matrix 客戶端、DB schema、初始化）
- ✅ 詳細文檔編寫完成

**待完成** (預估總時間: 15-22 小時):
1. 訊息發送整合 (4-6 小時)
2. 訊息接收 Sync Loop (3-4 小時)
3. 編輯/刪除訊息 (2-3 小時)
4. Room 管理 (2-3 小時)
5. 測試與優化 (4-6 小時)

**下一步**: 開始實現 Phase 1 - 訊息發送整合

參考 `MATRIX_INTEGRATION_GUIDE.md` 的 Phase 1.1 範例程式碼。

---

**部署完成！基礎架構已就緒，準備好進行業務邏輯整合。** 🎉
