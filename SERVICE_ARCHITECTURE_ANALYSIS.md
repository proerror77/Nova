# Nova 後端服務架構分析報告

## 服務概覽

### 已部署服務 (8個)
✅ 已在 K8s 中配置並部署

1. **auth-service** - 用戶認證與授權
2. **user-service** - 用戶資料管理
3. **content-service** - 內容發布與管理
4. **feed-service** - 信息流聚合
5. **media-service** - 媒體文件處理
6. **messaging-service** - 即時通訊
7. **search-service** - 搜索服務
8. **streaming-service** - 直播串流

### 未部署服務 (4個)
❌ 代碼存在但未在 K8s 中配置

1. **video-service** - 視頻處理服務
2. **cdn-service** - CDN 服務
3. **notification-service** - 推送通知服務
4. **events-service** - 事件處理服務

---

## 核心服務分析

### 1. 認證流程 (auth-service)

**職責**：
- ✅ 用戶註冊、登錄、登出
- ✅ JWT Token 生成與驗證
- ✅ OAuth 第三方登錄（Google, Apple, Facebook, WeChat）
- ✅ 密碼重置流程

**已集成**：
- ✅ PostgreSQL - 用戶資料存儲
- ✅ Redis - Session 管理
- ✅ Kafka - 發送認證事件（可選）
- ✅ JWT - 生成 access/refresh tokens

**配置需求**：
- `DATABASE_URL` - ✅ 已配置
- `REDIS_URL` - ✅ 已配置
- `JWT_PRIVATE_KEY_PEM` - ✅ 已配置
- `JWT_PUBLIC_KEY_PEM` - ✅ 已配置
- `OAUTH_*` - ⚠️ 可選（已設為 default）
- `KAFKA_BROKERS` - ⚠️ 可選

**當前狀態**：
- ✅ 代碼已修復（OAuth 配置改為可選）
- 🔄 等待新鏡像構建

---

### 2. 媒體上傳 (media-service)

**職責**：
- ✅ 處理圖片/視頻上傳
- ✅ 生成 S3 預簽名 URL
- ✅ 媒體元數據管理
- ✅ 圖片壓縮與優化

**S3 集成**：
```rust
pub struct S3Config {
    pub bucket: String,                    // S3_BUCKET
    pub region: String,                    // AWS_REGION
    pub access_key_id: Option<String>,     // AWS_ACCESS_KEY_ID
    pub secret_access_key: Option<String>, // AWS_SECRET_ACCESS_KEY
    pub endpoint: Option<String>,          // S3_ENDPOINT (for MinIO)
}
```

**已集成**：
- ✅ S3 - 文件存儲（支持 AWS S3 和 MinIO）
- ✅ PostgreSQL - 媒體元數據
- ✅ Redis - 緩存
- ✅ Kafka - 媒體處理事件

**配置需求**：
- `DATABASE_URL` - ✅ 已配置
- `REDIS_URL` - ✅ 已配置
- `S3_BUCKET` - ⚠️ **需要配置**
- `AWS_REGION` - ⚠️ **需要配置**
- `AWS_ACCESS_KEY_ID` - ⚠️ **需要配置**（或使用 IAM Role）
- `AWS_SECRET_ACCESS_KEY` - ⚠️ **需要配置**（或使用 IAM Role）

**當前狀態**：
- ❌ S3 憑證未在 K8s Secret 中配置
- ❌ media-service Deployment 未引用 S3 環境變量

---

### 3. 內容服務 (content-service)

**職責**：
- ✅ 發布貼文/視頻
- ✅ 內容審核
- ✅ 評論管理
- ✅ 點贊/收藏

**S3 集成**：
- ✅ 存儲 `s3_key` 在 `post_images` 表中
- ⚠️ 依賴 media-service 生成的 S3 keys
- ⚠️ 不直接上傳到 S3，只存儲引用

**已集成**：
- ✅ PostgreSQL - 內容數據
- ✅ Redis - 緩存
- ✅ JWT - 用戶認證
- ⚠️ Kafka - 內容事件（可選）

**配置需求**：
- `DATABASE_URL` - ✅ 已配置
- `REDIS_URL` - ✅ 已配置
- `JWT_PUBLIC_KEY_PEM` - ⚠️ **需要配置**

---

### 4. 消息服務 (messaging-service)

**職責**：
- ✅ 即時通訊（WebSocket）
- ✅ 端到端加密
- ✅ 離線消息存儲
- ✅ 推送通知集成

**已集成**：
- ✅ PostgreSQL - 消息存儲
- ✅ Redis - 在線狀態、消息隊列
- ✅ WebSocket - 實時通信
- ✅ JWT - 用戶認證
- ✅ APNs - iOS 推送（需配置）
- ⚠️ FCM - Android 推送（需配置）

**配置需求**：
- `DATABASE_URL` - ✅ 已配置
- `REDIS_URL` - ✅ 已配置
- `JWT_PUBLIC_KEY_PEM` - ⚠️ **需要配置**
- `APNS_*` - ⚠️ 可選（iOS 推送）
- `FCM_*` - ⚠️ 可選（Android 推送）

---

### 5. 信息流服務 (feed-service)

**職責**：
- ✅ 聚合用戶信息流
- ✅ 推薦算法
- ✅ 個性化排序
- ✅ 緩存優化

**已集成**：
- ✅ PostgreSQL - Feed 數據
- ✅ Redis - Feed 緩存
- ⚠️ Kafka - 監聽內容事件

**配置需求**：
- `DATABASE_URL` - ✅ 已配置
- `REDIS_URL` - ✅ 已配置

---

### 6. 搜索服務 (search-service)

**職責**：
- ✅ 全文搜索
- ✅ 用戶/內容搜索
- ✅ 搜索建議
- ✅ 熱門搜索

**已集成**：
- ✅ PostgreSQL - 搜索數據
- ✅ Elasticsearch - 全文搜索引擎
- ⚠️ Redis - 搜索緩存

**配置需求**：
- `DATABASE_URL` - ✅ 已配置
- `ELASTICSEARCH_URL` - ✅ 已配置
- `REDIS_URL` - ⚠️ **需要配置**

---

### 7. 串流服務 (streaming-service)

**職責**：
- ✅ 直播管理
- ✅ WebRTC 信令
- ✅ 觀眾統計
- ✅ 直播聊天

**已集成**：
- ✅ PostgreSQL - 直播數據
- ✅ Redis - 實時數據
- ⚠️ WebRTC - 媒體串流

**配置需求**：
- `DATABASE_URL` - ✅ 已配置
- `REDIS_URL` - ⚠️ **需要配置**

---

### 8. 用戶服務 (user-service)

**職責**：
- ✅ 用戶資料管理
- ✅ 關注/粉絲關係
- ✅ 用戶設置
- ✅ 隱私控制

**已集成**：
- ✅ PostgreSQL - 用戶數據
- ✅ Redis - 緩存
- ✅ JWT - 用戶認證

**配置需求**：
- `DATABASE_URL` - ✅ 已配置
- `REDIS_URL` - ✅ 已配置
- `JWT_PUBLIC_KEY_PEM` - ⚠️ **需要配置**

---

## 未部署服務分析

### video-service

**為何未部署**：
- 可能與 media-service 功能重疊
- 或計劃將視頻處理分離出來

**建議**：
- 如果需要專門的視頻處理（轉碼、HLS 切片），應該部署
- 否則可以整合到 media-service

### notification-service

**為何未部署**：
- 推送通知功能目前整合在 messaging-service 中

**建議**：
- 如果需要獨立的通知管理（email、SMS、推送），應該部署
- 可以從 messaging-service 中分離出來

### cdn-service

**為何未部署**：
- 可能使用外部 CDN（CloudFront, Cloudflare）

**建議**：
- 如果需要自建 CDN 或 CDN 管理服務，應該部署

### events-service

**為何未部署**：
- 事件處理可能整合在各個服務中

**建議**：
- 如果需要集中的事件處理和分析，應該部署

---

## 關鍵問題總結

### ❌ 嚴重問題

1. **S3 憑證未配置**
   - `media-service` 需要 S3 配置才能處理上傳
   - `video-service` 也需要 S3（如果部署）
   - **影響**：無法上傳圖片/視頻

2. **JWT Public Key 未注入到需要驗證的服務**
   - `content-service`, `user-service`, `messaging-service` 等需要驗證 JWT
   - **影響**：無法驗證用戶請求，所有 API 調用失敗

3. **Kafka 未部署**
   - 多個服務使用 Kafka 進行事件通信
   - **影響**：服務間事件無法傳遞（但標記為可選）

### ⚠️ 警告問題

1. **Elasticsearch Pending**
   - `search-service` 依賴 Elasticsearch
   - **影響**：搜索功能無法使用

2. **缺少推送通知配置**
   - APNs (iOS) 和 FCM (Android) 未配置
   - **影響**：無法發送推送通知

---

## 推薦修復順序

### 階段 1：核心功能（必需）

1. ✅ **已完成**：部署 Postgres, Redis
2. ✅ **已完成**：配置基本 Secret（DB URLs, Redis URL）
3. 🔄 **進行中**：修復 auth-service 配置問題
4. ⚠️ **待處理**：添加 S3 憑證到所有服務的 Deployment
5. ⚠️ **待處理**：添加 JWT Public Key 到需要驗證的服務

### 階段 2：進階功能

1. 部署 Kafka（用於事件驅動架構）
2. 部署 Elasticsearch（用於搜索）
3. 配置 APNs/FCM（用於推送通知）

### 階段 3：優化

1. 考慮是否部署 video-service
2. 考慮是否部署 notification-service
3. 優化資源配置

---

## 服務依賴關係圖

```
用戶請求
   |
   v
[auth-service] -----> PostgreSQL
   |                  Redis
   | (生成 JWT)
   v
[其他服務] ---------> PostgreSQL
   |                  Redis
   | (驗證 JWT)       S3 (media-service)
   |                  Elasticsearch (search-service)
   v
返回響應
```

---

## 結論

### ✅ 已正確串接

- **認證流程**：auth-service -> JWT -> 其他服務
- **數據存儲**：所有服務 -> PostgreSQL（各自的專用 DB）
- **緩存**：所有服務 -> Redis
- **事件通信**：部分服務 -> Kafka（可選）

### ❌ 未完成集成

- **S3 存儲**：media-service/video-service 的 S3 憑證未配置
- **JWT 驗證**：JWT Public Key 未注入到需要的服務
- **搜索功能**：Elasticsearch 未運行
- **推送通知**：APNs/FCM 未配置

### 🎯 立即行動項

1. **更新所有服務 Deployment，添加環境變量**：
   - `JWT_PUBLIC_KEY_PEM`（從 nova-secrets 讀取）
   - S3 憑證（從 nova-s3-credentials 讀取）

2. **解決資源限制**：
   - Elasticsearch 無法啟動（Pending）
   - 集群需要更多內存

3. **驗證服務間調用**：
   - 確保 JWT 驗證正常工作
   - 測試 S3 上傳流程
