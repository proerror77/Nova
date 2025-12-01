# Nova 好友系統與訊息授權設計方案

## 1. 現狀分析

### 已有基礎設施
| 組件 | 狀態 | 位置 |
|------|------|------|
| `follows` 表 | ✅ 已實現 | `migrations/004_social_graph_schema.sql` |
| `user_settings.allow_messages` | ✅ 已實現 | `migrations/130_create_user_settings.sql` |
| `user_settings.privacy_level` | ✅ 已實現 | public/friends/private |
| `ConversationService` | ✅ 已實現 | 但缺少授權檢查 |
| 封鎖系統 | ⚠️ 只在 Neo4j | 需要同步到 Postgres |

### 當前問題
```
任何人都可以直接創建對話 → 發送訊息
沒有好友請求流程
沒有 DM 權限檢查
封鎖用戶仍可發訊息
```

---

## 2. 設計目標

### 用戶流程
```
1. 用戶 A 關注用戶 B
2. 用戶 B 關注用戶 A（互相關注 = 好友）
3. 用戶 A 可以發送 DM 給 B（如果 B 的隱私設定允許）
4. 封鎖後，對方無法發訊息
```

### 隱私設定對照
| 設定 | 允許 DM 的人 |
|------|-------------|
| `anyone` | 所有人（除了被封鎖的） |
| `followers` | 關注我的人 |
| `mutuals` | 互相關注的人（好友） |
| `nobody` | 沒有人 |

---

## 3. 數據庫設計

### 3.1 新增 `blocks` 表（Postgres 主表）
```sql
-- 封鎖關係表（從 Neo4j 同步或完全在 Postgres）
CREATE TABLE blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason VARCHAR(255),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE(blocker_id, blocked_id),
    CHECK (blocker_id != blocked_id)
);

CREATE INDEX idx_blocks_blocker ON blocks(blocker_id);
CREATE INDEX idx_blocks_blocked ON blocks(blocked_id);
-- 快速查詢：A 是否被 B 封鎖
CREATE INDEX idx_blocks_pair ON blocks(blocked_id, blocker_id);
```

### 3.2 擴展 `user_settings` 表
```sql
-- 添加 DM 隱私設定
ALTER TABLE user_settings
ADD COLUMN dm_permission VARCHAR(20) NOT NULL DEFAULT 'mutuals'
CHECK (dm_permission IN ('anyone', 'followers', 'mutuals', 'nobody'));

COMMENT ON COLUMN user_settings.dm_permission IS
  'Who can send DMs: anyone, followers (people who follow me), mutuals (mutual follows), nobody';
```

### 3.3 對話請求表（可選，用於非好友訊息請求）
```sql
-- 訊息請求（當陌生人嘗試發訊息時）
CREATE TABLE message_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    recipient_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    message_preview TEXT,  -- 預覽訊息
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    responded_at TIMESTAMPTZ,

    UNIQUE(requester_id, recipient_id),
    CHECK (status IN ('pending', 'accepted', 'rejected', 'ignored')),
    CHECK (requester_id != recipient_id)
);

CREATE INDEX idx_message_requests_recipient ON message_requests(recipient_id, status);
CREATE INDEX idx_message_requests_requester ON message_requests(requester_id);
```

---

## 4. 服務層設計

### 4.1 RelationshipService（新服務）

```rust
// backend/realtime-chat-service/src/services/relationship_service.rs

pub struct RelationshipService;

impl RelationshipService {
    /// 檢查 user_a 是否可以發訊息給 user_b
    pub async fn can_message(
        db: &Pool<Postgres>,
        sender_id: Uuid,
        recipient_id: Uuid,
    ) -> Result<CanMessageResult, AppError> {
        // 1. 檢查是否被封鎖
        if Self::is_blocked(db, sender_id, recipient_id).await? {
            return Ok(CanMessageResult::Blocked);
        }

        // 2. 獲取收件人的 DM 設定
        let settings = Self::get_dm_settings(db, recipient_id).await?;

        match settings.dm_permission.as_str() {
            "anyone" => Ok(CanMessageResult::Allowed),
            "nobody" => Ok(CanMessageResult::NotAllowed),
            "followers" => {
                // sender 必須關注 recipient
                if Self::is_following(db, sender_id, recipient_id).await? {
                    Ok(CanMessageResult::Allowed)
                } else {
                    Ok(CanMessageResult::NeedToFollow)
                }
            }
            "mutuals" => {
                // 必須互相關注
                if Self::are_mutuals(db, sender_id, recipient_id).await? {
                    Ok(CanMessageResult::Allowed)
                } else {
                    Ok(CanMessageResult::NeedMutualFollow)
                }
            }
            _ => Ok(CanMessageResult::NotAllowed),
        }
    }

    /// 檢查是否互相關注（好友）
    pub async fn are_mutuals(
        db: &Pool<Postgres>,
        user_a: Uuid,
        user_b: Uuid,
    ) -> Result<bool, AppError> {
        let count: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) FROM follows
            WHERE (follower_id = $1 AND following_id = $2)
               OR (follower_id = $2 AND following_id = $1)
            "#
        )
        .bind(user_a)
        .bind(user_b)
        .fetch_one(db)
        .await?;

        Ok(count == 2)  // 兩條記錄 = 互相關注
    }

    /// 檢查 A 是否被 B 封鎖
    pub async fn is_blocked(
        db: &Pool<Postgres>,
        user_a: Uuid,
        user_b: Uuid,
    ) -> Result<bool, AppError> {
        let exists = sqlx::query_scalar::<_, bool>(
            "SELECT EXISTS(SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2)"
        )
        .bind(user_b)  // B 封鎖了 A
        .bind(user_a)
        .fetch_one(db)
        .await?;

        Ok(exists)
    }

    /// 封鎖用戶
    pub async fn block_user(
        db: &Pool<Postgres>,
        blocker_id: Uuid,
        blocked_id: Uuid,
        reason: Option<String>,
    ) -> Result<(), AppError> {
        sqlx::query(
            r#"
            INSERT INTO blocks (blocker_id, blocked_id, reason)
            VALUES ($1, $2, $3)
            ON CONFLICT (blocker_id, blocked_id) DO NOTHING
            "#
        )
        .bind(blocker_id)
        .bind(blocked_id)
        .bind(reason)
        .execute(db)
        .await?;

        // 同時取消關注關係
        sqlx::query(
            "DELETE FROM follows WHERE
             (follower_id = $1 AND following_id = $2) OR
             (follower_id = $2 AND following_id = $1)"
        )
        .bind(blocker_id)
        .bind(blocked_id)
        .execute(db)
        .await?;

        Ok(())
    }

    /// 解除封鎖
    pub async fn unblock_user(
        db: &Pool<Postgres>,
        blocker_id: Uuid,
        blocked_id: Uuid,
    ) -> Result<bool, AppError> {
        let result = sqlx::query(
            "DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2"
        )
        .bind(blocker_id)
        .bind(blocked_id)
        .execute(db)
        .await?;

        Ok(result.rows_affected() > 0)
    }
}

pub enum CanMessageResult {
    Allowed,
    Blocked,
    NotAllowed,
    NeedToFollow,
    NeedMutualFollow,
    NeedMessageRequest,
}
```

### 4.2 修改 ConversationService

```rust
// 修改 create_direct_conversation 添加授權檢查
pub async fn create_direct_conversation(
    db: &Pool<Postgres>,
    initiator: Uuid,
    recipient: Uuid,
) -> Result<Uuid, AppError> {
    // 🔴 新增：授權檢查
    let can_message = RelationshipService::can_message(db, initiator, recipient).await?;

    match can_message {
        CanMessageResult::Allowed => {
            // 繼續創建對話
        }
        CanMessageResult::Blocked => {
            return Err(AppError::Forbidden);  // 不透露封鎖狀態
        }
        CanMessageResult::NeedMutualFollow => {
            return Err(AppError::BadRequest(
                "You must be mutual followers to send messages".into()
            ));
        }
        CanMessageResult::NeedToFollow => {
            return Err(AppError::BadRequest(
                "You must follow this user to send messages".into()
            ));
        }
        CanMessageResult::NotAllowed => {
            return Err(AppError::BadRequest(
                "This user doesn't accept direct messages".into()
            ));
        }
        CanMessageResult::NeedMessageRequest => {
            // 創建訊息請求而不是對話
            return Self::create_message_request(db, initiator, recipient).await;
        }
    }

    // ... 原有的創建邏輯
}
```

---

## 5. API 設計

### 5.1 關係 API（social-service 或 realtime-chat-service）

```
# 好友/關係查詢
GET  /api/v1/relationships/{user_id}
     → { is_following: bool, is_followed_by: bool, is_mutual: bool, is_blocked: bool }

# 封鎖管理
POST   /api/v1/blocks         { user_id: UUID }
DELETE /api/v1/blocks/{user_id}
GET    /api/v1/blocks         → [{ user_id, blocked_at }]

# DM 權限設定
GET    /api/v1/settings/privacy
PUT    /api/v1/settings/privacy  { dm_permission: "mutuals" | "followers" | "anyone" | "nobody" }

# 訊息請求（如果啟用）
GET    /api/v1/message-requests           → [{ id, requester, preview, created_at }]
POST   /api/v1/message-requests/{id}/accept
POST   /api/v1/message-requests/{id}/reject
```

### 5.2 修改現有 API 的錯誤響應

```json
// POST /api/v1/conversations (創建對話失敗時)
{
  "error": "dm_not_allowed",
  "code": "DM_PERMISSION_DENIED",
  "message": "You must be mutual followers to send messages",
  "details": {
    "required": "mutual_follow",
    "current": "not_following"
  }
}
```

---

## 6. 實現步驟

### Phase 1: 基礎設施（1-2 天）
1. [ ] 創建 `blocks` 表遷移
2. [ ] 擴展 `user_settings` 添加 `dm_permission`
3. [ ] 實現 `RelationshipService`

### Phase 2: 授權整合（1-2 天）
4. [ ] 修改 `ConversationService::create_direct_conversation`
5. [ ] 添加封鎖 API 端點
6. [ ] 添加隱私設定 API 端點

### Phase 3: 進階功能（可選）
7. [ ] 訊息請求系統
8. [ ] Neo4j → Postgres 封鎖同步
9. [ ] GraphQL schema 更新

---

## 7. 遷移策略

### 現有對話處理
- 已存在的對話不受影響
- 新的權限檢查只在**創建新對話**時執行
- 用戶可以繼續在已存在的對話中發訊息

### 封鎖同步
- 如果 Neo4j 有封鎖數據，需要一次性同步到 Postgres
- 之後以 Postgres 為主（單一數據源）

---

## 8. 安全考量

### 不透露封鎖狀態
```rust
// 被封鎖時返回通用錯誤，不暴露封鎖狀態
CanMessageResult::Blocked => {
    Err(AppError::Forbidden)  // 不說 "you are blocked"
}
```

### 防止枚舉攻擊
- Rate limit 對話創建 API
- 不透露具體失敗原因給惡意用戶

### 數據一致性
- 封鎖時自動取消雙向關注
- 使用數據庫事務保證原子性

---

## 9. 測試計劃

### 單元測試
- `RelationshipService::can_message` 各種場景
- `are_mutuals` 邊界情況
- 封鎖/解封邏輯

### 整合測試
- 創建對話 + 權限檢查
- 封鎖後無法發訊息
- 隱私設定變更後的行為

### E2E 測試
- 完整的好友流程（關注 → 互關 → 發訊息）
- 封鎖流程
- 隱私設定流程
