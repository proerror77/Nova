# Matrix Integration Guide - realtime-chat-service

**Status**: 🚧 基礎架構已完成，待實現業務邏輯整合
**Last Updated**: 2025-12-09

---

## ✅ 已完成的工作

### 1. 部署 Matrix Synapse (nova-staging)

- ✅ Synapse homeserver 運行中
- ✅ PostgreSQL database `synapse` 已建立
- ✅ Service account `@nova-service:staging.nova.internal` 已註冊
- ✅ Access token 已產生並儲存在 K8s Secret
- ✅ 詳細資訊: `backend/MATRIX_DEPLOYMENT_INFO.md`

### 2. 程式碼基礎架構

#### 已添加的依賴 (`Cargo.toml`)
```toml
matrix-sdk = { version = "0.7", features = ["e2e-encryption", "sso-login"] }
ruma = { version = "0.9", features = ["client-api"] }
```

#### 已建立的檔案

1. **`src/services/matrix_client.rs`** - Matrix 客戶端封裝
   - `MatrixClient::new()` - 初始化並登入
   - `get_or_create_room()` - 建立/取得 Matrix room
   - `send_message()` - 發送文字訊息
   - `send_media()` - 發送附件（待完善）
   - `delete_message()` - 刪除訊息 (redaction)
   - `edit_message()` - 編輯訊息 (replacement)
   - `start_sync()` - 啟動 sync loop

2. **`migrations/0012_matrix_room_mapping.sql`** - 資料庫 schema
   ```sql
   CREATE TABLE matrix_room_mapping (
       conversation_id UUID PRIMARY KEY,
       matrix_room_id TEXT UNIQUE,
       ...
   );
   ALTER TABLE messages ADD COLUMN matrix_event_id TEXT;
   ```

3. **`src/state.rs`** - 已添加 `matrix_client: Option<Arc<MatrixClient>>`

4. **`src/main.rs`** - 已添加 Matrix 客戶端初始化邏輯

---

## 🚧 待完成的整合工作

### Phase 1: 訊息發送整合

#### 1.1 更新 `send_message` 端點

**檔案**: `src/routes/messages.rs` 或 `src/services/message_service.rs`

**目標**: 發送訊息時同時寫入 DB 和 Matrix

```rust
// 偽代碼示例
pub async fn send_message(
    state: &AppState,
    conversation_id: Uuid,
    sender_id: Uuid,
    content: &str,
) -> Result<MessageRow, AppError> {
    // 1. 寫入本地 DB（現有邏輯）
    let msg = MessageService::send_message_db(
        &state.db,
        &state.encryption,
        conversation_id,
        sender_id,
        content.as_bytes(),
        None,
    ).await?;

    // 2. 如果啟用 Matrix，同步發送到 Matrix
    if let Some(matrix_client) = &state.matrix_client {
        // 2a. 獲取參與者列表
        let participant_ids = get_conversation_participants(&state.db, conversation_id).await?;

        // 2b. 取得或建立 Matrix room
        let room_id = matrix_client
            .get_or_create_room(conversation_id, &participant_ids)
            .await?;

        // 2c. 發送到 Matrix
        let event_id = matrix_client
            .send_message(conversation_id, &room_id, content)
            .await?;

        // 2d. 更新 DB 儲存 matrix_event_id
        sqlx::query("UPDATE messages SET matrix_event_id = $1 WHERE id = $2")
            .bind(&event_id)
            .bind(msg.id)
            .execute(&state.db)
            .await?;

        // 2e. 快取 room mapping
        save_room_mapping(&state.db, conversation_id, room_id).await?;
    }

    Ok(msg)
}
```

**需要實現的輔助函數**:
- `get_conversation_participants(db, conversation_id) -> Vec<Uuid>`
- `save_room_mapping(db, conversation_id, room_id) -> Result<()>`
- `load_room_mapping(db, conversation_id) -> Option<OwnedRoomId>`

---

#### 1.2 更新 `send_audio_message`

**檔案**: `src/routes/messages.rs`

**邏輯**:
1. 上傳音訊到 S3（現有）
2. 如果 Matrix 啟用：
   - 選項 A: 上傳到 Matrix media API (`/_matrix/media/v3/upload`)
   - 選項 B: 在 Matrix 訊息中帶 S3 URL（臨時方案）

```rust
// 選項 B（臨時）
if let Some(matrix_client) = &state.matrix_client {
    let room_id = get_or_load_room_id(state, conversation_id).await?;
    matrix_client.send_media(
        conversation_id,
        &room_id,
        &s3_url,
        "audio/webm",
        &filename
    ).await?;
}
```

---

### Phase 2: 訊息接收 (Matrix Sync)

#### 2.1 啟動 Matrix Sync Loop

**檔案**: `src/main.rs` (在 `AppState` 初始化後)

```rust
// 在 main.rs 中，Matrix client 初始化後
if let Some(matrix_client) = &matrix_client {
    let matrix_sync_state = state.clone();
    let matrix_sync_client = matrix_client.clone();

    tokio::spawn(async move {
        let event_handler = move |ev: SyncRoomMessageEvent, room: Room| {
            let state = matrix_sync_state.clone();
            async move {
                handle_matrix_message(state, ev, room).await;
            }
        };

        if let Err(e) = matrix_sync_client.start_sync(event_handler).await {
            tracing::error!(error = %e, "Matrix sync loop failed");
        }
    });
}
```

#### 2.2 實現 `handle_matrix_message`

**新檔案**: `src/services/matrix_event_handler.rs`

```rust
pub async fn handle_matrix_message(
    state: AppState,
    event: SyncRoomMessageEvent,
    room: Room,
) {
    // 1. 解析 Matrix event
    let OriginalSyncRoomMessageEvent { content, sender, event_id, .. } = match event {
        SyncRoomMessageEvent::Original(ev) => ev,
        _ => return, // 忽略 redacted/其他
    };

    // 2. 查找對應的 conversation_id
    let room_id = room.room_id();
    let conversation_id = match lookup_conversation_by_room_id(&state.db, room_id).await {
        Ok(Some(id)) => id,
        _ => {
            tracing::warn!("Unknown Matrix room: {}", room_id);
            return;
        }
    };

    // 3. 轉換 Matrix sender 為 Nova user_id
    let sender_uuid = extract_user_id_from_matrix(&sender);

    // 4. 提取訊息內容
    let text = match content.msgtype {
        MessageType::Text(text_content) => text_content.body,
        _ => return, // 暫不處理其他類型
    };

    // 5. 透過 WebSocket 推送給前端
    state.registry.broadcast_to_conversation(
        conversation_id,
        &serde_json::json!({
            "type": "message.new",
            "conversation_id": conversation_id,
            "sender_id": sender_uuid,
            "content": text,
            "matrix_event_id": event_id.to_string(),
        })
    ).await;

    // 6. （可選）寫入本地 DB 作為備份
    // 注意：避免重複處理自己發送的訊息
}
```

**需要實現**:
- `lookup_conversation_by_room_id(db, room_id) -> Option<Uuid>`
- `extract_user_id_from_matrix(sender: &UserId) -> Uuid`

---

### Phase 3: 訊息編輯/刪除

#### 3.1 更新刪除訊息

**檔案**: `src/routes/messages.rs` - `delete_message` handler

```rust
// 在現有刪除邏輯後添加
if let Some(matrix_client) = &state.matrix_client {
    // 從 DB 取得 matrix_event_id 和 room_id
    let (event_id, room_id) = get_matrix_info(&state.db, message_id).await?;

    if let (Some(eid), Some(rid)) = (event_id, room_id) {
        matrix_client.delete_message(&rid, &eid, Some("User deleted")).await?;
    }
}
```

#### 3.2 實現編輯訊息

**新端點**: `PATCH /conversations/{id}/messages/{msg_id}`

```rust
pub async fn edit_message(
    state: web::Data<AppState>,
    path: web::Path<(Uuid, Uuid)>,
    body: web::Json<EditMessageRequest>,
) -> Result<HttpResponse, AppError> {
    let (conversation_id, message_id) = path.into_inner();

    // 1. 更新 DB
    update_message_content(&state.db, message_id, &body.new_content).await?;

    // 2. 如果有 Matrix，發送 replacement event
    if let Some(matrix_client) = &state.matrix_client {
        let (original_event_id, room_id) = get_matrix_info(&state.db, message_id).await?;

        if let (Some(eid), Some(rid)) = (original_event_id, room_id) {
            let new_event_id = matrix_client
                .edit_message(&rid, &eid, &body.new_content)
                .await?;

            // 更新 DB 記錄新的 event_id
            sqlx::query("UPDATE messages SET matrix_event_id = $1 WHERE id = $2")
                .bind(&new_event_id)
                .bind(message_id)
                .execute(&state.db)
                .await?;
        }
    }

    // 3. WS 推送編輯事件
    state.registry.broadcast_to_conversation(
        conversation_id,
        &json!({
            "type": "message.edited",
            "message_id": message_id,
            "new_content": body.new_content,
        })
    ).await;

    Ok(HttpResponse::Ok().finish())
}
```

---

### Phase 4: Room 管理

#### 4.1 建立對話時建立 Matrix Room

**檔案**: `src/services/conversation_service.rs` - `create_conversation`

```rust
// 在建立 conversation 後
if let Some(matrix_client) = &state.matrix_client {
    let room_id = matrix_client
        .get_or_create_room(conversation_id, &participant_ids)
        .await?;

    // 儲存 mapping
    save_room_mapping(&state.db, conversation_id, room_id).await?;
}
```

#### 4.2 邀請新成員加入 Room

**檔案**: 添加到 `src/services/matrix_client.rs`

```rust
impl MatrixClient {
    pub async fn invite_user_to_room(
        &self,
        room_id: &RoomId,
        user_id: Uuid,
    ) -> Result<(), AppError> {
        let room = self.client.get_room(room_id)
            .ok_or_else(|| AppError::NotFound)?;

        let matrix_user_id = self.convert_uuid_to_matrix_user(user_id)?;

        room.invite_user_by_id(&matrix_user_id).await
            .map_err(|e| AppError::StartServer(format!("Invite failed: {e}")))?;

        Ok(())
    }

    fn convert_uuid_to_matrix_user(&self, user_id: Uuid) -> Result<OwnedUserId, AppError> {
        let matrix_user_id = format!(
            "@{}:{}",
            user_id.to_string().replace("-", ""),
            self.extract_server_name()
        );
        UserId::parse(&matrix_user_id)
            .map_err(|e| AppError::Config(format!("Invalid user ID: {e}")))
    }
}
```

---

## 📋 資料庫輔助函數 (需實現)

建議新增檔案: `src/services/matrix_db.rs`

```rust
use sqlx::{Pool, Postgres};
use uuid::Uuid;
use matrix_sdk::ruma::OwnedRoomId;

/// 儲存 conversation -> Matrix room mapping
pub async fn save_room_mapping(
    db: &Pool<Postgres>,
    conversation_id: Uuid,
    room_id: OwnedRoomId,
) -> Result<(), sqlx::Error> {
    sqlx::query(
        "INSERT INTO matrix_room_mapping (conversation_id, matrix_room_id)
         VALUES ($1, $2)
         ON CONFLICT (conversation_id) DO UPDATE
         SET matrix_room_id = $2, updated_at = CURRENT_TIMESTAMP"
    )
    .bind(conversation_id)
    .bind(room_id.as_str())
    .execute(db)
    .await?;
    Ok(())
}

/// 查找 conversation 的 Matrix room
pub async fn load_room_mapping(
    db: &Pool<Postgres>,
    conversation_id: Uuid,
) -> Result<Option<OwnedRoomId>, sqlx::Error> {
    let room_id: Option<String> = sqlx::query_scalar(
        "SELECT matrix_room_id FROM matrix_room_mapping WHERE conversation_id = $1"
    )
    .bind(conversation_id)
    .fetch_optional(db)
    .await?;

    Ok(room_id.and_then(|s| OwnedRoomId::try_from(s).ok()))
}

/// 反向查找：Matrix room -> conversation
pub async fn lookup_conversation_by_room_id(
    db: &Pool<Postgres>,
    room_id: &str,
) -> Result<Option<Uuid>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT conversation_id FROM matrix_room_mapping WHERE matrix_room_id = $1"
    )
    .bind(room_id)
    .fetch_optional(db)
    .await
}

/// 取得訊息的 Matrix 資訊
pub async fn get_matrix_info(
    db: &Pool<Postgres>,
    message_id: Uuid,
) -> Result<(Option<String>, Option<OwnedRoomId>), sqlx::Error> {
    let row: Option<(Option<String>, Uuid)> = sqlx::query_as(
        "SELECT m.matrix_event_id, m.conversation_id
         FROM messages m
         WHERE m.id = $1"
    )
    .bind(message_id)
    .fetch_optional(db)
    .await?;

    if let Some((event_id, conversation_id)) = row {
        let room_id = load_room_mapping(db, conversation_id).await?;
        Ok((event_id, room_id))
    } else {
        Ok((None, None))
    }
}

/// 取得對話的所有參與者
pub async fn get_conversation_participants(
    db: &Pool<Postgres>,
    conversation_id: Uuid,
) -> Result<Vec<Uuid>, sqlx::Error> {
    sqlx::query_scalar(
        "SELECT user_id FROM conversation_members WHERE conversation_id = $1"
    )
    .bind(conversation_id)
    .fetch_all(db)
    .await
}
```

---

## 🧪 測試計劃

### 1. 單元測試

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_send_message_with_matrix() {
        // 建立測試 DB
        // 初始化 Matrix mock client
        // 測試訊息發送流程
    }

    #[tokio::test]
    async fn test_room_mapping() {
        // 測試 save/load room mapping
    }
}
```

### 2. 整合測試

```bash
# 1. 啟用 Matrix
kubectl patch configmap realtime-chat-service-config -n nova-staging \
  --type merge -p '{"data":{"MATRIX_ENABLED":"true"}}'

kubectl rollout restart deployment/realtime-chat-service -n nova-staging

# 2. 檢查日誌
kubectl logs -n nova-staging -l app=realtime-chat-service --tail=100 | grep -i matrix

# 應該看到：
# ✅ Matrix client initialized for homeserver: http://matrix-synapse:8008

# 3. 發送測試訊息（透過 API）
curl -X POST http://realtime-chat-service:8086/api/v1/conversations/{id}/messages \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"content": "Test message via Matrix"}'

# 4. 驗證 Matrix 有收到
kubectl exec -n nova-staging deploy/matrix-synapse -- \
  curl -s -H "Authorization: Bearer $MATRIX_TOKEN" \
  http://localhost:8008/_matrix/client/v3/sync?timeout=0
```

---

## 🔐 安全考量

1. **Access Token 管理**
   - ✅ 已儲存在 K8s Secret
   - ⚠️ 需要實現 token refresh 機制（如果 Matrix 支援）

2. **E2EE 驗證**
   - Matrix SDK 已啟用 `e2e-encryption` feature
   - 需要測試 E2EE 金鑰交換流程

3. **錯誤處理**
   - Matrix 不可用時不應阻塞訊息發送
   - 建議使用 graceful degradation

---

## 📊 監控指標

建議添加 Prometheus metrics:

```rust
// 在 src/services/matrix_client.rs
lazy_static::lazy_static! {
    static ref MATRIX_MESSAGES_SENT: prometheus::Counter =
        prometheus::register_counter!("matrix_messages_sent_total", "Total messages sent to Matrix").unwrap();

    static ref MATRIX_ERRORS: prometheus::Counter =
        prometheus::register_counter!("matrix_errors_total", "Total Matrix errors").unwrap();

    static ref MATRIX_SYNC_EVENTS: prometheus::Counter =
        prometheus::register_counter!("matrix_sync_events_total", "Total Matrix sync events received").unwrap();
}
```

---

## 🚀 部署步驟

### Staging

```bash
# 1. 執行 migration
kubectl exec -n nova-staging deploy/realtime-chat-service -- \
  sqlx migrate run

# 2. 啟用 Matrix（已在部署文檔說明）
kubectl patch configmap realtime-chat-service-config -n nova-staging \
  --type merge -p '{"data":{"MATRIX_ENABLED":"true"}}'

# 3. 重啟服務
kubectl rollout restart deployment/realtime-chat-service -n nova-staging

# 4. 驗證
kubectl logs -n nova-staging -l app=realtime-chat-service --tail=50
```

### Production

- [ ] 更新 `MATRIX_SERVER_NAME` 為正式 domain
- [ ] 配置 TLS/ingress
- [ ] 增加 Synapse 資源配額
- [ ] 設定備份策略

---

## 📚 相關文檔

- Matrix Synapse 部署資訊: `backend/MATRIX_DEPLOYMENT_INFO.md`
- Matrix SDK 文檔: https://docs.rs/matrix-sdk/latest/matrix_sdk/
- Ruma (Matrix types): https://docs.rs/ruma/latest/ruma/

---

## ✅ 檢查清單

**基礎架構**:
- [x] Matrix Synapse 部署
- [x] Matrix SDK 依賴添加
- [x] MatrixClient 模組建立
- [x] DB migration 建立
- [x] AppState 整合

**業務邏輯** (待完成):
- [ ] send_message 整合 Matrix
- [ ] send_audio_message 整合 Matrix
- [ ] Matrix sync loop 實現
- [ ] 訊息編輯功能
- [ ] 訊息刪除功能
- [ ] Room 管理（建立、邀請）
- [ ] 資料庫輔助函數 (`matrix_db.rs`)
- [ ] 單元測試
- [ ] 整合測試

**生產就緒**:
- [ ] 錯誤處理完善
- [ ] 監控指標
- [ ] 效能測試
- [ ] 文檔更新

---

**下一步**: 實現 `send_message` 的 Matrix 整合（Phase 1.1）
