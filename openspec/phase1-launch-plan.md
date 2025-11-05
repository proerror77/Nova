# Phase 1 啟動計劃：應用層解耦 (gRPC 遷移)

**開始日期**: 2025-11-12（下週）
**預計工期**: 12-16 週
**團隊規模**: 2-3 名工程師
**優先級**: 🔴 高（架構基礎）

---

## 📌 Phase 1 概述

### 目標

將 Nova 從"分布式單體"（所有服務共享單數據庫）遷移至"邏輯微服務"（通過 gRPC 通信）。

### 為什麼是 gRPC？

```
直接 SQL（當前）          gRPC（Phase 1）         分離數據庫（Phase 3）
┌──────────────┐        ┌─────────────┐        ┌─────────────┐
│  Auth        │        │Auth Service │        │ nova_auth   │
│  User        │        │             │        │  users, ... │
│  Content     │ ──────>│ User Svc    │ ──────>│ nova_user   │
│  Feed        │ SQL    │             │ gRPC   │  profiles   │
│  Messaging   │        │Content Svc  │        │ nova_content│
│  ...         │        │             │        │  posts, ... │
│ 1 database   │        │ Feed Svc    │        │ nova_stream │
└──────────────┘        │  (only read)│        │  streams    │
                        │             │        └─────────────┘
                        │Messaging Svc│
                        └─────────────┘
                         1 database
```

**關鍵優勢**:
1. 服務邊界清晰（類型安全的 Proto API）
2. 無表模式耦合（API 更改不影響其他服務）
3. 為數據庫分離做準備（未來容易拆分）
4. 性能可預測（已知延遲的 RPC 調用）

---

## 🎯 Phase 1 的 4 個階段

### Stage 1.1：信任建設和基礎設施 (Week 1-2)

**目標**: 證明 gRPC 適合生產環境

#### Task 1.1.1：設置 gRPC 客戶端代碼生成
- [ ] 創建 `backend/proto/build.rs` 腳本
- [ ] 集成 `prost-build` 和 `tonic-build`
- [ ] 為所有服務生成 Rust 客戶端代碼
- [ ] 測試客戶端編譯無誤

**文件**:
```rust
// backend/proto/build.rs
fn main() -> std::io::Result<()> {
    tonic_build::compile_protos("proto/services/auth_service.proto")?;
    tonic_build::compile_protos("proto/services/user_service.proto")?;
    // ... 其他 7 個服務
    Ok(())
}
```

#### Task 1.1.2：實現 gRPC 客戶端包裝器
- [ ] 創建 `backend/libs/grpc-clients/src/lib.rs`
- [ ] 為每個服務實現客戶端包裝器
- [ ] 添加連接池和重試邏輯
- [ ] 添加指標收集

**文件結構**:
```rust
// backend/libs/grpc-clients/src/
├── auth_client.rs       // AuthService 客戶端
├── user_client.rs       // UserService 客戶端
├── content_client.rs    // ContentService 客戶端
├── feed_client.rs       // FeedService 客戶端
├── media_client.rs      // MediaService 客戶端
├── messaging_client.rs  // MessagingService 客戶端
├── search_client.rs     // SearchService 客戶端
├── streaming_client.rs  // StreamingService 客戶端
├── pool.rs              // 連接池管理
└── lib.rs
```

#### Task 1.1.3：設置 gRPC 服務器集成
- [ ] 為每個服務添加 gRPC 伺服器
- [ ] 實現服務 trait（Tonic 生成）
- [ ] 添加健康檢查和反射
- [ ] 測試服務間通信

**代碼示例**:
```rust
// auth-service/src/grpc/server.rs
use tonic::{transport::Server, Request, Response};
use nova_proto::auth_service_server::{AuthService, AuthServiceServer};

#[derive(Clone)]
pub struct AuthServiceImpl {
    db: Arc<Database>,
}

#[tonic::async_trait]
impl AuthService for AuthServiceImpl {
    async fn get_user(
        &self,
        request: Request<GetUserRequest>,
    ) -> Result<Response<GetUserResponse>, Status> {
        // 實現邏輯
    }
}
```

**預期結果**:
- ✅ 所有服務都可以作為 gRPC 伺服器啟動
- ✅ gRPC 調用在本地集群中完成（<10ms）

---

### Stage 1.2：前 3 個服務遷移 (Week 3-8)

**目標**: 通過 3 個關鍵服務驗證遷移模式

#### Task 1.2.1：Auth Service - 遷移 GetUser 查詢 (Week 3)

**影響**:
- User Service（讀取 users）
- Content Service（讀取 users）
- Messaging Service（讀取 users）
- Search Service（讀取 users）

**步驟**:
1. 在 auth-service 中實現 `GetUser()` gRPC 方法
2. 更新 user-service 使用 `auth_client.get_user()` 而不是 SQL
3. 測試遷移（單元測試和集成測試）
4. 部署到 Staging
5. 監控 P99 延遲、錯誤率、緩存命中率

**代碼差異**:
```rust
// 舊方式（SQL 查詢）
let user = sqlx::query_as::<_, User>(
    "SELECT * FROM users WHERE id = $1"
)
.bind(user_id)
.fetch_one(&db)
.await?;

// 新方式（gRPC 調用）
let user = auth_client
    .get_user(GetUserRequest {
        user_id: user_id.to_string(),
    })
    .await?
    .into_inner()
    .user
    .ok_or(Status::not_found("User not found"))?;
```

**驗證清單**:
- [ ] gRPC 調用返回與 SQL 相同的數據
- [ ] 性能無回歸（P99 < 50ms）
- [ ] 錯誤處理正確（超時、不存在等）
- [ ] 指標記錄完整

#### Task 1.2.2：User Service - 遷移 Follow/Unfollow (Week 4-5)

**影響**:
- Feed Service（讀取 follows）
- Content Service（讀取 follows）
- Search Service（讀取 follows）

**新 RPC 方法**:
```protobuf
// 在 user_service.proto 中
service UserService {
  rpc FollowUser(FollowUserRequest) returns (FollowUserResponse);
  rpc UnfollowUser(UnfollowUserRequest) returns (UnfollowUserResponse);
  rpc GetUserFollowers(GetUserFollowersRequest) returns (GetUserFollowersResponse);
  rpc GetUserFollowing(GetUserFollowingRequest) returns (GetUserFollowingResponse);
}
```

**步驟**:
1. 在 user-service 中實現 Follow 相關的 RPC
2. 更新 content-service 使用 gRPC 而不是直接查詢 follows
3. 更新 feed-service 使用 gRPC 獲取用戶關係
4. 測試和部署

#### Task 1.2.3：Content Service - 遷移 Post/Comment/Like (Week 6-8)

**影響**:
- Feed Service（讀取 posts、comments、likes）
- Search Service（讀取內容）
- Streaming Service（讀取 post_images）

**新 RPC 方法**:
```protobuf
// 在 content_service.proto 中
service ContentService {
  rpc CreatePost(CreatePostRequest) returns (CreatePostResponse);
  rpc GetPost(GetPostRequest) returns (GetPostResponse);
  rpc GetPostsByIds(GetPostsByIdsRequest) returns (GetPostsByIdsResponse);
  rpc LikePost(LikePostRequest) returns (LikePostResponse);
  rpc GetComments(GetCommentsRequest) returns (GetCommentsResponse);
  rpc CreateComment(CreateCommentRequest) returns (CreateCommentResponse);
}
```

**步驟**:
1. 實現 ContentService gRPC
2. 遷移 Feed Service 使用 gRPC 獲取帖子（而不是 SQL）
3. 實現批量操作（GetPostsByIds）以優化性能
4. 部署和監控

**預期結果**:
- ✅ 3 個服務已通過 gRPC 通信
- ✅ 性能基準建立（P99、P95）
- ✅ 遷移模式驗證成功

---

### Stage 1.3：剩餘 5 個服務遷移 (Week 9-14)

**概述**: 使用 Stage 1.2 中驗證的模式遷移剩餘服務

#### Task 1.3.1：Messaging Service (Week 9-10)
- [ ] 實現 Message/Conversation RPC
- [ ] E2EE 密鑰交換 gRPC
- [ ] 遷移 Messaging 客戶端

#### Task 1.3.2：Media Service (Week 10-11)
- [ ] 實現 Video gRPC
- [ ] 實現 Upload Session 管理
- [ ] 遷移 Content/Feed 使用 gRPC 獲取視頻信息

#### Task 1.3.3：Search Service (Week 11-12)
- [ ] 實現 Search RPC（基於 PostgreSQL 全文搜索）
- [ ] 準備 Elasticsearch 集成（Phase 2）
- [ ] 遷移客戶端

#### Task 1.3.4：Streaming Service (Week 12-13)
- [ ] 實現 Stream/Viewer RPC
- [ ] 遷移指標收集

#### Task 1.3.5：Feed Service 優化 (Week 13-14)
- [ ] 完全遷移到 gRPC 讀取
- [ ] 優化批量 RPC 調用
- [ ] 實現客戶端緩存

**預期結果**:
- ✅ 所有 8 個服務都通過 gRPC 通信
- ✅ 無服務間的直接 SQL 查詢

---

### Stage 1.4：測試和驗收 (Week 15-16)

#### Task 1.4.1：集成測試
- [ ] 編寫跨服務集成測試
- [ ] 測試故障場景（超時、服務不可用）
- [ ] 測試消息順序和一致性

#### Task 1.4.2：性能測試
- [ ] 負載測試（1000 RPS）
- [ ] 延遲測試（P99、P95、P50）
- [ ] 記憶體使用測試

#### Task 1.4.3：用戶驗收測試
- [ ] 在 Staging 環境中驗證
- [ ] 檢查沒有用戶面向的更改
- [ ] 驗證監控和告警正常工作

#### Task 1.4.4：發布準備
- [ ] 編寫遷移指南
- [ ] 準備回滾計劃
- [ ] 進行 Stage 環境的最終測試

**預期結果**:
- ✅ Phase 1 準備進入生產環境
- ✅ 所有性能指標符合目標
- ✅ 零數據丟失、零停機遷移

---

## 📊 每週詳細里程碑

| 週 | 任務 | 可交付 | 驗收標準 |
|----|------|--------|---------|
| 1-2 | gRPC 基礎設施 | 客戶端代碼生成、連接池 | 編譯成功，本地測試通過 |
| 3 | Auth GetUser | auth-service gRPC | 4 個服務成功遷移 |
| 4-5 | User Follow | user-service gRPC | Feed/Content 使用 gRPC |
| 6-8 | Content P/C/L | content-service gRPC | 批量操作優化 |
| 9-10 | Messaging | messaging-service gRPC | E2EE 密鑰交換工作 |
| 10-11 | Media | media-service gRPC | 視頻信息 gRPC 可用 |
| 11-12 | Search | search-service gRPC | 全文搜索可用 |
| 12-13 | Streaming | streaming-service gRPC | 直播指標通過 gRPC |
| 13-14 | Feed 優化 | 批量優化、緩存 | 調用數減少 50% |
| 15-16 | 測試/發布 | 集成測試、性能報告 | 進入 Staging |

---

## 🔍 風險評估

| 風險 | 可能性 | 影響 | 緩解措施 |
|------|--------|------|---------|
| gRPC 序列化開銷 | 中 | 性能回歸 | 提前性能測試、使用消息優化 |
| 網絡分區故障 | 低 | 服務中斷 | 實施重試邏輯、斷路器 |
| 向後兼容性 | 低 | 數據不一致 | 漸進式遷移、側邊驗證 |
| 開發週期風險 | 中 | 超期 | 每週審查進度、並行工作 |

---

## 📋 依賴和前置條件

### Phase 0 交付物（已完成 ✅）
- [x] Protobuf 文件定義（8 個服務）
- [x] 數據所有權矩陣
- [x] Proto vs Rust 驗證
- [x] gRPC 架構計劃

### Phase 1 前置條件
- [ ] Rust 1.75+ 編譯器可用
- [ ] Tonic 和 Prost 依賴添加到 Cargo.toml
- [ ] gRPC 連接池庫實現
- [ ] 監控和日誌系統就位

### 資源需求
- **團隊**: 2-3 名高級 Rust 工程師
- **時間**: 16 週（約 4 個月）
- **基礎設施**:
  - Kubernetes 集群（Staging 和 Prod）
  - Prometheus 監控（gRPC 指標）
  - 分布式追踪（Jaeger 可選）

---

## 🚀 成功指標

### 技術指標
- [ ] 100% 的服務間通信使用 gRPC（零 SQL 依賴）
- [ ] gRPC P99 延遲 < 50ms（本地集群）
- [ ] 錯誤率 < 0.1%
- [ ] 無性能回歸（vs Phase 0 基線）

### 業務指標
- [ ] 零停機遷移（用戶無感知）
- [ ] 零數據丟失
- [ ] 支持獨立服務部署
- [ ] 為 Phase 2 Outbox/Kafka 做準備

---

## 📝 下一步行動（本週）

1. **確認資源分配**
   - 分配 2-3 名工程師
   - 安排每日站會（10:00 UTC）

2. **環境準備**
   - 設置 Staging Kubernetes 集群
   - 配置 Prometheus 監控
   - 準備 CI/CD 管道

3. **知識轉移**
   - 團隊學習 Tonic/Prost
   - 審查 Protobuf 文件
   - 計劃第一次 sprint

4. **創建 Jira/GitHub 問題**
   - 為每個 Task 創建 Issue
   - 估算工作量
   - 設置 Sprint 計劃

---

## 📚 參考資料

- **Protobuf 定義**: `/backend/proto/services/*.proto`
- **數據所有權矩陣**: `openspec/data-ownership-matrix.md`
- **架構策略**: `ARCHITECTURE_REVISED_STRATEGY.md`
- **Tonic 文檔**: https://github.com/hyperium/tonic
- **Prost 文檔**: https://github.com/tokio-rs/prost

---

## 簽核和批准

| 角色 | 名字 | 日期 | 簽名 |
|------|------|------|------|
| 產品負責人 | — | — | — |
| 技術負責人 | — | — | — |
| 項目經理 | — | — | — |

**狀態**: 📋 待批准
**預計啟動**: 2025-11-12
**預計完成**: 2026-01-20
