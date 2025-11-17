# Nova 微服務架構 v2 (權威文檔)

> **⚠️ 本文檔為 Nova v2 架構的唯一真相來源 (Single Source of Truth)**
>
> 最後更新: 2025-11-17
> 狀態: **CURRENT** (v2 現役架構)

## 快速參考

| 服務名稱 | 職責範圍 | 主要存儲 | gRPC Package | 狀態 |
|---------|---------|---------|--------------|------|
| **identity-service** | 身份認證、授權、JWT、基礎 profile | PostgreSQL | `nova.identity_service.v2` | ✅ ACTIVE |
| **content-service** | Post/Comment CRUD、內容主資料 | PostgreSQL | `nova.content_service.v2` | ✅ ACTIVE |
| **media-service** | 影片/Reel 上傳、轉碼、存儲 | PostgreSQL + S3 | `nova.media_service.v2` | ✅ ACTIVE |
| **feed-service** | Feed 聚合、推薦入口 | PostgreSQL | `nova.feed_service.v2` | ✅ ACTIVE |
| **search-service** | 全文搜尋、用戶/內容檢索 | Elasticsearch | `nova.search_service.v2` | ✅ ACTIVE |
| **analytics-service** | Outbox 模式、事件管道到 Kafka/ClickHouse | PostgreSQL + Kafka | `nova.events_service.v2` | ✅ ACTIVE |
| **graph-service** | Follow/Mute/Block 關係圖 | Neo4j | `nova.graph_service.v2` | ✅ ACTIVE |
| **social-service** | Like/Comment/Share 統計聚合 | PostgreSQL | `nova.social_service.v2` | ✅ ACTIVE |
| **notification-service** | Push/Email/In-app 通知 | PostgreSQL | `nova.notification_service.v2` | ✅ ACTIVE |
| **realtime-chat-service** | **完整 Messaging Domain** (DM 持久化 + WebSocket + E2EE) | PostgreSQL + Redis | `nova.realtime_chat.v1` | ✅ ACTIVE |
| **trust-safety-service** | 內容審核、Ban/Report 處理 | PostgreSQL | `nova.trust_safety.v2` | ✅ ACTIVE |
| **ranking-service** | 排序演算法、推薦引擎 | PostgreSQL | `nova.ranking_service.v2` | ✅ ACTIVE |
| **graphql-gateway** | 對外唯一 GraphQL 入口 | N/A (無狀態) | N/A | ✅ ACTIVE |

## 已淘汰服務 (v1)

| 服務名稱 | 原職責 | 淘汰原因 | 替代方案 | 狀態 |
|---------|-------|---------|---------|------|
| **messaging-service** | DM 訊息持久化 | 功能整合 | → **realtime-chat-service** | ❌ DEPRECATED |
| **user-service** | 用戶資料管理 | 職責拆分 | → **identity-service** | ❌ DEPRECATED |
| **auth-service** | 身份認證 | 職責整合 | → **identity-service** | ❌ DEPRECATED |
| **streaming-service** | 影片流媒體 | 功能整合 | → **media-service** | ❌ DEPRECATED |
| **video-service** | 影片處理 | 功能整合 | → **media-service** | ❌ DEPRECATED |
| **cdn-service** | CDN 管理 | 改用 CloudFront | 基礎設施層 | ❌ DEPRECATED |
| **events-service** | 事件處理 | 重新命名 | → **analytics-service** | ❌ DEPRECATED |
| **communication-service** | 通訊服務 | 功能整合 | → **realtime-chat-service** | ❌ DEPRECATED |

## 服務詳細說明

### 1. identity-service (身份與授權核心)

**職責範圍**:
- 用戶註冊、登入、登出
- JWT token 簽發與驗證
- 基礎 profile (username, email, avatar_url)
- OAuth/SSO 整合 (未來)

**依賴**:
- PostgreSQL: `identity_db`
- Redis: Session 管理
- gRPC Outbox: 發布 `UserCreated`, `UserUpdated` 事件

**gRPC 介面**:
```proto
package nova.identity_service.v2;

service IdentityService {
  rpc CheckUserExists(CheckUserExistsRequest) returns (CheckUserExistsResponse);
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
  rpc GetUsersByIds(GetUsersByIdsRequest) returns (GetUsersByIdsResponse);
}
```

**部署**:
- Namespace: `nova-staging`, `nova-dev`
- Replicas: 3 (staging), 1 (dev)
- Resources: CPU 100m-500m, Memory 256Mi-512Mi

---

### 2. realtime-chat-service (完整 Messaging Domain)

> **⚠️ 重要**: 這是唯一處理 DM 訊息的服務，**messaging-service 已完全淘汰**

**職責範圍**:
- DM 訊息持久化 (messages 表)
- 訊息歷史查詢 (分頁、搜尋)
- WebSocket 連接管理 (實時推送)
- E2EE 金鑰交換 (X25519 + Kyber)
- 會話管理 (conversations 表)
- 群組聊天 (group_conversations, group_members)
- 訊息回收、編輯、刪除
- 已讀/未讀狀態

**技術棧**:
- REST API: `/api/v1/chat/*`
- WebSocket: `/ws` (Actix-web)
- gRPC: `nova.realtime_chat.v1.RealtimeChatService`
- 存儲: PostgreSQL + Redis Streams (跨 pod fanout)

**關鍵重構**:
- **移除 GrpcClientPool 依賴** (2025-11-17)
  - 之前: 啟動時連接 14 個服務，阻塞 130+ 秒
  - 現在: 只連接 `identity-service` (lazy connection)，啟動時間 < 1 秒

**部署**:
- Namespace: `nova-staging`
- Replicas: 1-3 (視負載調整)
- Resources: CPU 250m-1, Memory 256Mi-512Mi

**依賴**:
- identity-service: 用戶驗證 (`CheckUserExists`)
- PostgreSQL: `realtime_chat_db`
- Redis: Streams + PubSub

---

### 3. graphql-gateway (統一入口)

**職責範圍**:
- 唯一對外 GraphQL API
- Schema stitching (整合所有服務)
- 請求路由與負載均衡
- Rate limiting + Authentication middleware

**依賴** (透過 `libs/grpc-clients`):
```rust
- identity-service (user profile)
- content-service (posts, comments)
- feed-service (feed aggregation)
- social-service (likes, shares)
- graph-service (follows, relationships)
- search-service (搜尋)
- notification-service (通知)
- media-service (影片)
- realtime-chat-service (訊息)
- analytics-service (事件)
- trust-safety-service (審核)
- ranking-service (排序)
```

**部署**:
- Namespace: `nova-staging`
- Replicas: 2-5 (auto-scaling)
- Resources: CPU 250m-1, Memory 256Mi-512Mi

---

## 部署環境

### Dev 環境 (nova-dev)
- **用途**: 快速迭代、功能驗證
- **Image Tag**: `dev-{SHA}`
- **Resource Quota**: CPU 4/8 cores, Memory 8Gi/16Gi
- **Replicas**: 1 per service
- **部署時間**: 5-8 分鐘 (只建構變更的服務)

### Staging 環境 (nova-staging)
- **用途**: 集成測試、Pre-production 驗證
- **Image Tag**: `{SHA}` (Git commit SHA)
- **Resource Quota**: CPU 10/25 cores, Memory 8Gi/20Gi
- **Replicas**: 1-3 per service
- **部署時間**: 10-15 分鐘 (建構所有服務)

### Production 環境 (未來)
- **用途**: 線上服務
- **Image Tag**: `v{version}` (semantic versioning)
- **Resource Quota**: 按需調整
- **Replicas**: Auto-scaling (HPA)

---

## CI/CD 流程

```
Dev (快速迭代):
  push dev/** → 檢測變更 → 只建構變更服務 → kubectl set image → nova-dev

Staging (集成測試):
  merge to main → 建構所有服務 → 運行測試 → kubectl set image → nova-staging

Production (未來):
  手動 release → 從 staging 拉取已驗證鏡像 → 藍綠部署 → production
```

### 關鍵改進 (2025-11-17)
1. **移除 :latest tag**: 只使用 Git SHA 標籤，確保可追溯性
2. **Dev 快速部署**: 自動檢測變更服務，5-8 分鐘完成部署
3. **Staging 直接部署**: 使用 `kubectl set image`，移除 ArgoCD 同步延遲
4. **Resource Quotas**: 防止 CrashLoopBackOff 消耗所有 CPU

---

## 架構決策記錄 (ADR)

### ADR-001: messaging-service → realtime-chat-service 整合
- **日期**: 2025-11-15
- **決策**: 將 messaging-service 完全整合到 realtime-chat-service
- **原因**:
  1. 避免 DM 訊息 domain 分裂到兩個服務
  2. WebSocket 連接與訊息持久化應該在同一服務內
  3. 簡化部署與運維複雜度
- **影響**:
  - messaging-service 所有代碼、proto、manifest 已移除
  - realtime-chat-service 承擔完整 messaging domain
  - K8s 殭屍資源已清理 (2025-11-17)

### ADR-002: GrpcClientPool 移除 (realtime-chat-service)
- **日期**: 2025-11-17
- **決策**: realtime-chat-service 只連接 identity-service
- **原因**:
  1. 啟動時連接 14 個服務導致 130+ 秒阻塞
  2. 只有 identity-service 是必需依賴
  3. 其他服務不需要在啟動時連接
- **實作**:
  ```rust
  // 之前: GrpcClientPool::new().await (阻塞 130s)
  // 現在: Endpoint::connect_lazy() (< 1s)
  let auth_client = AuthClient::new(identity_channel);
  ```
- **影響**:
  - 啟動時間從 130s → < 1s
  - 避免 CrashLoopBackOff 消耗 CPU
  - 服務真正獨立運行

---

## 監控與告警

### 關鍵指標
- **realtime-chat-service**:
  - WebSocket 連接數
  - 訊息發送成功率
  - E2EE 金鑰交換延遲
  - Redis Streams lag

- **identity-service**:
  - JWT 驗證錯誤率
  - CheckUserExists RPC 延遲 (P99 < 100ms)

- **graphql-gateway**:
  - GraphQL query 錯誤率
  - 請求延遲 (P95 < 500ms)

### 告警規則
```yaml
- alert: RealtimeChatServiceDown
  expr: up{job="realtime-chat-service"} == 0
  for: 2m
  severity: critical

- alert: IdentityServiceHighLatency
  expr: histogram_quantile(0.99, grpc_server_handling_seconds{service="identity"}) > 0.5
  for: 5m
  severity: warning
```

---

## 相關文檔

- [API 文檔](./docs/api/) - GraphQL schema + REST API spec
- [部署指南](./docs/deployment/) - K8s manifests + Helm charts
- [開發指南](./docs/development/) - 本地開發環境設置
- [架構決策](./docs/adr/) - ADR 詳細記錄

---

## 變更歷史

| 日期 | 變更內容 | 負責人 |
|------|---------|-------|
| 2025-11-17 | 創建 SERVICES.md，定義 v2 架構唯一真相來源 | Claude Code |
| 2025-11-17 | 清理 messaging-service 殭屍資源 | Claude Code |
| 2025-11-17 | CI/CD 重構：dev 快速部署 + staging 優化 | Claude Code |
| 2025-11-15 | realtime-chat-service 移除 GrpcClientPool 依賴 | proerror + Claude Code |
| 2025-11-15 | messaging-service 完全淘汰，功能整合到 realtime-chat-service | proerror + Claude Code |

---

**最後確認**: 本文檔為 Nova v2 架構的權威參考，任何服務清單、依賴關係、部署配置變更必須同步更新此文檔。
