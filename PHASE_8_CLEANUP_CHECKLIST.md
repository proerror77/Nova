# Phase 8: User-Service 深度清理清單

**目標**：將 user-service 從完整 monolith 縮減為輕量的「帳號 + 聚合層」
**策略**：逐個 domain 分析→刪除→編譯驗證→測試通過

---

## 1️⃣ 認證域 (Auth Domain) - 3,157 行

### 待刪檔案
- [ ] `handlers/auth.rs` (988 行) - 註冊、登入、郵件驗證、2FA
- [ ] `handlers/oauth.rs` (561 行) - OAuth 集成
- [ ] `handlers/password_reset.rs` (311 行) - 密碼重設
- [ ] `services/email_service.rs` (352 行) - 郵件發送
- [ ] `services/email_verification.rs` (189 行) - 郵件驗證 token 管理
- [ ] `services/jwt_key_rotation.rs` (300 行) - JWT 密鑰輪換
- [ ] `services/two_fa.rs` (149 行) - 2FA 管理
- [ ] `services/backup_codes.rs` (307 行) - 備份碼管理
- [ ] `services/oauth/` 目錄 - OAuth providers

### 待修改檔案
- [ ] `handlers/mod.rs` - 移除 auth/oauth/password_reset 導入和 pub use
- [ ] `main.rs` - 移除 /auth /oauth 路由、email_service 初始化
- [ ] `openapi.rs` - 移除所有 auth/* endpoint 定義
- [ ] `lib.rs` - 移除相關模組的 pub use
- [ ] 資料庫：移除 email_verification、2fa 相關 table
  - [ ] `migrations/` - 確認 password_reset_tokens, email_verification_tokens, totp_secrets, backup_codes 等

### 驗證步驟
1. 確保 auth-service 已有等效實現
2. API Gateway 配置 /auth → auth-service:8080 路由
3. cargo build 通過（預期會有編譯錯誤，逐項修復）
4. cargo test 通過

---

## 2️⃣ 社交/Feed 域 - TBD

### 待刪檔案
- [ ] `handlers/feed.rs` - 飼料生成（可能只是 proxy）
- [ ] `handlers/experiments.rs` - 實驗配置
- [ ] `handlers/discover.rs` - 發現頁面
- [ ] `services/ranking_engine.rs` - 排名引擎
- [ ] `services/experiments/` - 實驗邏輯
- [ ] `services/clickhouse_feature_extractor.rs` - 特徵提取
- [ ] `db/experiment_repo.rs` - 實驗資料存儲

### 待修改檔案
- [ ] `handlers/mod.rs`
- [ ] `services/mod.rs`
- [ ] `main.rs` - 移除相關初始化
- [ ] `openapi.rs`
- [ ] migrations

### 驗證步驟
- feed-service 是否已提供 ranking/experiments？

---

## 3️⃣ 媒體/S3 域 - TBD

### 待刪檔案
- [ ] `services/s3_service.rs` - S3 上傳/下載
- [ ] `services/image_processing.rs` - 圖片處理
- [ ] `services/origin_shield.rs` - CDN origin protection

### 待修改檔案
- [ ] `services/mod.rs`
- [ ] `main.rs` - S3 健康檢查、客戶端初始化
- [ ] migrations - 刪除 video/image/upload 相關 schema

### 驗證步驟
- media-service 是否已提供完整 S3/image 功能？

---

## 4️⃣ 推播/Kafka 域 - 特別處理

### 現狀
- `services/notifications/` 已刪除 ✅
- `services/kafka_producer.rs` - 仍需評估（被其他模組使用）
- `services/redis_job.rs` - 仍需評估（用於 cache 刷新）

### 行動
- [ ] 檢查誰在使用 kafka_producer（cdc, events, social_graph_sync）
  - 這些應該維持，用於事件發佈
- [ ] 檢查誰在使用 redis_job（cache_warmer, suggested_users）
  - 這些應該維持，用於後台任務
- [ ] **不刪除**，但移到合適的模組層級（可能改成 lib 或單獨的 crate）

---

## 5️⃣ OpenAPI 更新 - 必做

### 檢查項目
- [ ] 審視 `openapi.rs` 中所有 endpoint 定義
- [ ] 移除已遷移服務的 endpoint：
  - `POST /auth/*` → auth-service
  - `POST /posts` → content-service
  - `POST /videos/upload` → media-service
  - `POST /messages` → messaging-service
  - `GET /trending` → feed-service
  - 等等...
- [ ] 保留現在仍在 user-service 的：
  - GET /users/{id}
  - GET /users/me
  - PATCH /users/me
  - POST /users/{id}/follow
  - 等

---

## 6️⃣ 資料庫遷移清理 - 重要

### 須檢查的 migration 檔案
- [ ] `001_users_table.sql` - 保留（核心用戶表）
- [ ] `*_posts_table.sql` - 刪除或遷移標記（已在 content-service）
- [ ] `*_videos_table.sql` - 刪除或遷移標記（已在 media-service）
- [ ] `*_comments_table.sql` - 刪除或遷移標記
- [ ] `*_likes_table.sql` - 刪除或遷移標記
- [ ] `*_email_verification.sql` - 刪除（移到 auth-service）
- [ ] `*_totp_secrets.sql` - 刪除（移到 auth-service）
- [ ] `*_backup_codes.sql` - 刪除（移到 auth-service）

---

## 7️⃣ CI/CD 調整 - 最後一步

### Cargo 設定
- [ ] `backend/user-service/Cargo.toml` - 移除已不需要的依賴：
  - lettre (郵件 - auth-service 使用)
  - uuid (主要用於 2FA - auth-service 使用)
  - 等

### 測試
- [ ] user-service 的 test 數量應該顯著降低
- [ ] 應該只剩下用戶資料、社交圖、聚合相關的測試

### Pipeline
- [ ] `.github/workflows/` - 移除不需要的 user-service 測試步驟
- [ ] 部署配置 - 只保留必要的 resources

---

## 執行順序

推薦按以下順序進行（每個完成後 `cargo check` + `cargo test`）：

1. **Phase 8.1**: 刪除 Auth Domain → 編譯 ✅
2. **Phase 8.2**: 刪除 Social/Feed Domain → 編譯 ✅
3. **Phase 8.3**: 刪除 Media/S3 Domain → 編譯 ✅
4. **Phase 8.4**: 評估 Kafka/Redis → 決策 ✅
5. **Phase 8.5**: 清理 OpenAPI 定義 → 編譯 ✅
6. **Phase 8.6**: 清理 Migrations → 編譯 ✅
7. **Phase 8.7**: 調整 CI/CD → 測試通過 ✅
8. **Phase 8.Final**: Git commit 並驗證最終狀態

---

## 預期結果

**清理前**:
- user-service: ~15,000+ 行代碼 (完整 monolith)
- 60+ 個 handler/service/repo 檔案
- 50+ 個 migrations (含已遷移服務的 schema)

**清理後**:
- user-service: ~5,000-6,000 行代碼 (輕量服務)
- 15-20 個檔案 (只有帳號 + 聚合 + 社交圖)
- 10-15 個 migrations (只有用戶、設定、社交相關)

---

## 備註

- 每個階段完成後必須運行 `cargo build -p user-service && cargo test -p user-service`
- 如有編譯錯誤，需找出所有依賴並逐一修復
- 不要一次刪太多檔案 - 逐步進行以便於回溯
- 更新相應文檔，告知客戶端新的 API 路由

---

**開始日期**: [TBD]
**預計完成**: [TBD]
**當前進度**: 清單建立
