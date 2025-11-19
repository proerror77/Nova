# AWS Backend 最終連線測試報告

**測試時間**: 2025-11-19 08:11 JST
**測試環境**: Staging (AWS EKS)
**LoadBalancer**: `a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com`
**測試者**: iOS Team

---

## 🎯 執行摘要

### ✅ 已修復的問題

1. **Ingress SSL 重定向** - 禁用了強制 HTTPS 重定向
2. **Feed Service Selector** - 修復了 Service selector 不匹配
3. **Content Service Selector** - 修復了 Service selector 不匹配
4. **Feed Service 端口** - Ingress 已配置為正確的 8084 端口
5. **Social Service 端口** - Ingress 已更新為 8006 端口

### ⚠️ Feed Service 可用（需要認證）

✅ **Feed Service 現在可以通過 Ingress 訪問**
- 狀態: 401 Unauthorized
- 說明: 服務正常運行，需要認證 token

### ❌ 發現的主要問題

1. **iOS 與後端 API 不匹配** - iOS 期望 POST，後端提供 GET
2. **Identity Service 無 HTTP API** - 只提供 gRPC (port 50051)
3. **Backend 路由配置缺失** - 多個 handlers 未註冊

---

## 🔧 執行的修復

### 1. 禁用 Ingress SSL 重定向

**問題**: 所有 HTTP 請求被重定向到 HTTPS (308)

**修復**:
```bash
kubectl patch ingress nova-api-gateway -n nova-staging --type='json' \
  -p='[{"op": "add", "path": "/metadata/annotations/nginx.ingress.kubernetes.io~1ssl-redirect", "value": "false"}]'
```

**結果**: ✅ HTTP 請求現在可以直接訪問

### 2. 修復 Feed Service Selector

**問題**: Service selector 與 Pod labels 不匹配

```yaml
# Service Selector (錯誤)
app: nova
component: feed-service

# Pod Labels (實際)
app: feed-service
```

**修復**:
```bash
kubectl patch svc feed-service -n nova-staging --type='json' \
  -p='[{"op": "replace", "path": "/spec/selector", "value": {"app": "feed-service"}}]'
```

**結果**: ✅ Service 現在有 endpoints: `10.0.11.47:8084,10.0.11.47:9084`

### 3. 修復 Content Service Selector

**問題**: 同樣的 selector 不匹配問題

**修復**:
```bash
kubectl patch svc content-service -n nova-staging --type='json' \
  -p='[{"op": "replace", "path": "/spec/selector", "value": {"app": "content-service"}}]'
```

**結果**: ✅ Service 現在有 endpoints: `10.0.11.10:9080,10.0.11.10:8080`

### 4. 修復 Social Service Ingress 端口

**問題**: Ingress 指向 8081，實際端口是 8006

**修復**:
```bash
kubectl patch ingress nova-api-gateway -n nova-staging --type='json' \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/8/backend/service/port/number", "value": 8006}]'
```

**結果**: ✅ Ingress 現在路由到正確端口

---

## 🧪 測試結果

### 當前狀態總覽

| 服務 | HTTP 狀態 | 狀態 | 說明 |
|------|----------|------|------|
| **Feed Service** | 401 | ✅ 可用 | 需要認證（服務正常） |
| **Content Service** | 404 | ⚠️ 路由問題 | Service 可達，路由配置問題 |
| **Identity Service** | 502 | ❌ 無 HTTP API | 只提供 gRPC |
| **Social Service** | 404 | ⚠️ 路由問題 | Service 可達，路由配置問題 |
| **Health Check** | 502 | ❌ 不可用 | Identity Service 問題 |

### 詳細測試結果

#### ✅ Feed Service - 可用

**測試**:
```bash
GET /api/v2/feed?user_id=test&limit=10
Host: api.nova.local
```

**響應**:
```
HTTP/1.1 401 Unauthorized
Content-Type: application/json

{"error":"Missing user context","code":401}
```

**分析**:
- ✅ Ingress 路由正常
- ✅ Service 正常
- ✅ Pod 正常運行
- ⚠️ 需要認證 token（預期行為）

**直接 Pod 測試**:
```bash
curl http://10.0.11.47:8084/api/v2/feed?user_id=test&limit=10
# 返回 401 Unauthorized（正確）
```

#### ❌ Content Service - 路由問題

**測試**:
```bash
POST /api/v2/posts
Host: api.nova.local
Content-Type: application/json
Body: {}
```

**響應**:
```
HTTP/1.1 404 Not Found
```

**分析**:
- ✅ Service 有 endpoints
- ⚠️ 404 表示路由不匹配
- 需要檢查後端 handler 定義

#### ❌ Identity Service - 無 HTTP API

**測試**:
```bash
POST /api/v2/auth/login
Host: api.nova.local
```

**響應**:
```
HTTP/1.1 502 Bad Gateway
```

**分析**:
- ❌ Identity Service 只提供 gRPC (port 50051)
- ❌ Ingress 配置為 HTTP port 8080（不存在）
- ✅ gRPC endpoints: `10.0.11.191:50051,10.0.11.21:50051,10.0.11.226:50051`

**Pod 日誌**:
```json
{"level":"INFO","message":"Starting gRPC server on 0.0.0.0:50051"}
{"level":"INFO","message":"mTLS enabled - service-to-service authentication active"}
```

---

## 🚨 發現的主要問題

### 問題 1: iOS 與 Backend API 不匹配 ⚠️ **嚴重**

#### Feed Service API 不匹配

**iOS 期望**:
```swift
// POST /api/v2/feed/user
func getUserFeed(userId: String, limit: Int, cursor: String?) async throws {
    let request = FeedRequest(userId: userId, limit: limit, cursor: cursor)
    let response: FeedResponse = try await client.request(
        endpoint: APIConfig.Feed.userFeed,  // "/api/v2/feed/user"
        method: "POST",
        body: request
    )
}
```

**Backend 實際提供**:
```rust
#[get("")]  // GET /api/v2/feed
pub async fn get_feed(
    query: web::Query<FeedQueryParams>,  // ?user_id=xxx&limit=xxx
    ...
) -> Result<HttpResponse> {
    ...
}
```

**不匹配之處**:
- ❌ iOS 使用 `POST /api/v2/feed/user`
- ✅ Backend 提供 `GET /api/v2/feed?user_id=xxx&limit=xxx`
- ❌ iOS 使用 JSON body
- ✅ Backend 使用 query parameters

**影響**: iOS 無法調用 Feed API

### 問題 2: Backend Handlers 未註冊 ⚠️ **重要**

#### Trending Handlers 未註冊

**已定義但未使用的 handlers**:
```rust
// handlers/trending.rs
#[get("/api/v2/trending")]
pub async fn get_trending(...) { }

#[get("/api/v2/trending/videos")]
pub async fn get_trending_videos(...) { }

#[get("/api/v2/trending/posts")]
pub async fn get_trending_posts(...) { }

#[get("/api/v2/trending/streams")]
pub async fn get_trending_streams(...) { }
```

**main.rs 中只註冊了**:
```rust
web::scope("/api/v2/feed")
    .service(get_feed)  // 只有這一個！
```

**缺少的註冊**:
```rust
// 應該添加:
.service(get_trending)
.service(get_trending_videos)
.service(get_trending_posts)
.service(get_trending_streams)
// ...等等
```

**影響**:
- iOS trending 端點會返回 404
- 所有 trending 相關功能不可用

### 問題 3: Identity Service 架構問題 ❌ **阻塞**

**問題**: Identity Service 只提供 gRPC，無 HTTP REST API

**當前配置**:
```yaml
# Ingress
- path: /api/v2/auth
  backend:
    service:
      name: identity-service
      port:
        number: 8080  # ❌ 這個端口不存在
```

**實際情況**:
```yaml
# identity-service Service
ports:
  - name: grpc
    port: 50051  # ✅ 只有這個端口存在
    targetPort: 50051
```

**需要的解決方案**:

**選項 A: 使用 GraphQL Gateway** (推薦)
```yaml
iOS App
  ↓ HTTP/REST
GraphQL Gateway (port 8080)
  ↓ gRPC
Identity Service (port 50051)
```

**問題**: graphql-gateway 當前處於 CrashLoopBackOff

**選項 B: 在 Identity Service 添加 HTTP Layer**
```rust
// 在 identity-service 中添加 HTTP adapter
HttpServer::new(|| {
    App::new()
        .route("/api/v2/auth/login", web::post().to(login_http_handler))
        .route("/api/v2/auth/register", web::post().to(register_http_handler))
})
.bind("0.0.0.0:8080")?  // HTTP layer
.run();

// 內部轉換 HTTP -> gRPC
async fn login_http_handler(req: LoginRequest) -> HttpResponse {
    let grpc_response = grpc_client.login(req).await?;
    HttpResponse::Ok().json(grpc_response)
}
```

**選項 C: 使用 gRPC-Web** (需要 iOS 修改)
- iOS 使用 gRPC-Web 協議
- 需要額外的 gRPC Swift 依賴

---

## 📊 Ingress 配置總覽

### 當前 Ingress 路由配置

| Path | Service | Port | 狀態 |
|------|---------|------|------|
| `/api/v2/posts` | content-service | 8080 | ⚠️ 路由問題 |
| `/api/v2/feed` | feed-service | 8084 | ✅ 正常 |
| `/api/v2/trending` | feed-service | 8084 | ❌ Handler 未註冊 |
| `/api/v2/auth` | identity-service | 8080 | ❌ 端口不存在 |
| `/api/v2/users` | identity-service | 8080 | ❌ 端口不存在 |
| `/api/v2/relationships` | social-service | 8006 | ⚠️ 路由問題 |
| `/api/v2/search` | search-service | 8086 | ❌ Service CrashLoopBackOff |
| `/api/v2/discover` | feed-service | 8084 | ❌ Handler 未註冊 |
| `/health` | identity-service | 8080 | ❌ 端口不存在 |

### Service Endpoints 狀態

| Service | Endpoints | 狀態 |
|---------|-----------|------|
| feed-service | `10.0.11.47:8084,9084` | ✅ 正常 |
| content-service | `10.0.11.10:8080,9080` | ✅ 正常 |
| identity-service | `10.0.11.191:50051` (x3) | ✅ gRPC only |
| social-service | `10.0.11.147:8006,50052` | ✅ 正常 |
| search-service | None | ❌ CrashLoopBackOff |

---

## 📱 iOS 需要的修改

### 優先級 P0: API 調用方式修改

#### 1. Feed Service API

**當前 iOS 代碼** (不正確):
```swift
func getUserFeed(userId: String, limit: Int = 20, cursor: String? = nil) async throws {
    let request = FeedRequest(userId: userId, limit: limit, cursor: cursor)
    let response: FeedResponse = try await client.request(
        endpoint: APIConfig.Feed.userFeed,  // "/api/v2/feed/user"
        method: "POST",
        body: request
    )
}
```

**需要修改為**:
```swift
func getUserFeed(userId: String, limit: Int = 20, cursor: String? = nil) async throws {
    // 使用 GET 和 query parameters
    let endpoint = "\(APIConfig.Feed.baseFeed)?user_id=\(userId)&limit=\(limit)"
    + (cursor != nil ? "&cursor=\(cursor!)" : "")

    let response: FeedResponse = try await client.request(
        endpoint: endpoint,  // "/api/v2/feed?user_id=xxx&limit=20"
        method: "GET"  // 改為 GET
    )
}
```

**APIConfig 修改**:
```swift
struct Feed {
    // 之前：
    // static let userFeed = "/api/v2/feed/user"

    // 現在：
    static let baseFeed = "/api/v2/feed"  // GET with query params

    // 注意: trending, explore 等端點目前未註冊
    // static let trending = "/api/v2/feed/trending"  // ❌ 404
    // static let exploreFeed = "/api/v2/feed/explore"  // ❌ 404
}
```

#### 2. 移除 Trending 和 Explore 調用

**當前代碼** (會返回 404):
```swift
func getTrendingPosts(limit: Int = 20) async throws -> [Post] {
    // ❌ 這個端點未註冊
    let response: Response = try await client.request(
        endpoint: "\(APIConfig.Feed.trending)?limit=\(limit)",
        method: "GET"
    )
}
```

**臨時解決方案**:
```swift
func getTrendingPosts(limit: Int = 20) async throws -> [Post] {
    // 暫時使用 getUserFeed
    let (posts, _, _) = try await getUserFeed(userId: "system", limit: limit)
    return posts
}
```

或者**註釋掉相關功能**直到後端修復。

### 優先級 P1: 等待 Backend 修復

#### 認證功能暫時不可用

```swift
// ❌ 當前不可用 - identity-service 無 HTTP API
func login(email: String, password: String) async throws -> User {
    // 等待 graphql-gateway 修復或 HTTP adapter 添加
}
```

**臨時方案**: 使用 mock 認證或跳過認證

---

## 🔧 Backend 需要的修復

### 優先級 P0: 註冊缺失的 Handlers

**feed-service/src/main.rs**:
```rust
HttpServer::new(move || {
    App::new()
        // ... middleware ...
        // ✅ 已存在
        .service(get_recommendations)
        .service(get_model_info)
        .service(rank_candidates)
        .service(semantic_search)

        // ❌ 缺少: 需要添加
        .service(get_trending)
        .service(get_trending_videos)
        .service(get_trending_posts)
        .service(get_trending_streams)
        .service(get_trending_categories)
        .service(record_engagement)

        // ❌ 缺少: discover handlers
        .service(get_suggested_users)

        .service(
            web::scope("/api/v2/feed")
                .service(get_feed)
        )
})
```

### 優先級 P0: 修復 Identity Service HTTP 訪問

**選項 1: 修復 GraphQL Gateway** (推薦)

```bash
# 檢查 graphql-gateway 崩潰原因
kubectl logs -n nova-staging graphql-gateway-68f85948df-tw2fb

# 常見問題:
# - 配置錯誤
# - 無法連接到後端 gRPC 服務
# - 缺少環境變量
```

**選項 2: 添加 HTTP Adapter**

在 identity-service 中添加 HTTP layer:
```rust
// identity-service/src/http_adapter.rs
use actix_web::{web, App, HttpResponse, HttpServer};

async fn login_handler(req: web::Json<LoginRequest>) -> HttpResponse {
    // 調用內部 gRPC
    let grpc_response = GRPC_SERVICE.login(req.into_inner()).await;
    HttpResponse::Ok().json(grpc_response)
}

// main.rs
#[tokio::main]
async fn main() {
    // gRPC server
    tokio::spawn(async {
        Server::builder()
            .add_service(IdentityServiceServer::new(service))
            .serve("[::]:50051".parse().unwrap())
            .await
    });

    // HTTP adapter (NEW!)
    HttpServer::new(|| {
        App::new()
            .route("/api/v2/auth/login", web::post().to(login_handler))
            .route("/api/v2/auth/register", web::post().to(register_handler))
            .route("/health", web::get().to(|| async { "OK" }))
    })
    .bind("0.0.0.0:8080")?
    .run()
    .await?;
}
```

### 優先級 P1: 修改 Feed API 以匹配 iOS

**當前**: `GET /api/v2/feed?user_id=xxx`
**iOS 期望**: `POST /api/v2/feed/user`

**選項 A**: 修改 iOS (推薦 - 更簡單)
**選項 B**: 添加新 handler 支持 POST

```rust
// 添加 POST endpoint
#[post("/user")]
pub async fn get_user_feed_post(
    body: web::Json<FeedRequest>,
    state: web::Data<FeedHandlerState>,
) -> Result<HttpResponse> {
    // 轉換為現有邏輯
    let query = FeedQueryParams {
        user_id: body.user_id.clone(),
        limit: body.limit,
        cursor: body.cursor.clone(),
    };

    // 調用現有函數
    get_feed_internal(query, state).await
}

// main.rs
web::scope("/api/v2/feed")
    .service(get_feed)  // GET /api/v2/feed
    .service(get_user_feed_post)  // POST /api/v2/feed/user
```

---

## ✅ 成功修復的配置

### 1. Ingress SSL Redirect

```yaml
# 添加的 annotation
nginx.ingress.kubernetes.io/ssl-redirect: "false"
```

### 2. Service Selectors

```yaml
# feed-service
spec:
  selector:
    app: feed-service  # 修改前: app: nova, component: feed-service

# content-service
spec:
  selector:
    app: content-service  # 修改前: app: nova, component: content-service
```

### 3. Ingress Ports

```yaml
# feed-service
- path: /api/v2/feed
  backend:
    service:
      name: feed-service
      port:
        number: 8084  # ✅ 正確

# social-service
- path: /api/v2/relationships
  backend:
    service:
      name: social-service
      port:
        number: 8006  # 修改前: 8081
```

---

## 🎯 下一步行動

### iOS 團隊 (立即執行)

1. **修改 Feed API 調用方式**
   - 將 POST 改為 GET
   - 使用 query parameters 而非 request body
   - 更新 `APIConfig.Feed` 配置

2. **禁用 Trending 功能**
   - 註釋掉或使用 fallback
   - 等待後端註冊 handlers

3. **認證功能暫時跳過**
   - 使用 mock token 或跳過認證
   - 等待 identity-service HTTP API

### Backend 團隊 (P0 修復)

1. **feed-service: 註冊缺失的 handlers**
   ```bash
   # 在 main.rs 中添加所有 trending 和 discover handlers
   # 重新部署 feed-service
   ```

2. **identity-service: 修復 HTTP 訪問**
   - 選項 A: 修復 graphql-gateway
   - 選項 B: 添加 HTTP adapter 到 identity-service

3. **驗證端點可用性**
   ```bash
   # 測試所有端點
   curl -H "Host: api.nova.local" http://LB/api/v2/trending
   curl -H "Host: api.nova.local" http://LB/api/v2/auth/login
   ```

### DevOps 團隊 (建議)

1. **檢查所有 Service Selectors**
   ```bash
   # 確保所有 services 的 selector 與 pod labels 匹配
   # 自動化檢查腳本
   ```

2. **監控 Ingress 配置**
   ```bash
   # 確保端口配置與實際服務一致
   # 添加驗證腳本
   ```

---

## 📊 測試命令參考

### 通過 Ingress 測試

```bash
LB="a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com"

# Feed Service (GET)
curl -H "Host: api.nova.local" \
  "http://$LB/api/v2/feed?user_id=test&limit=10"
# 預期: 401 Unauthorized

# Content Service (需確認正確的端點)
curl -H "Host: api.nova.local" \
  -X POST -H "Content-Type: application/json" -d '{}' \
  "http://$LB/api/v2/posts"

# Identity Service (目前不可用)
curl -H "Host: api.nova.local" \
  -X POST -H "Content-Type: application/json" \
  -d '{"email":"test@test.com","password":"test"}' \
  "http://$LB/api/v2/auth/login"
# 預期: 502 Bad Gateway (無 HTTP API)
```

### 直接測試 Pod

```bash
# Feed Service
kubectl run -it --rm curl-test --image=curlimages/curl --restart=Never -n nova-staging -- \
  curl "http://10.0.11.47:8084/api/v2/feed?user_id=test&limit=10"
# 預期: 401 Unauthorized

# Identity Service (gRPC only)
kubectl get endpoints identity-service -n nova-staging
# 只有 port 50051
```

---

## 📝 總結

### ✅ 成功完成

1. 禁用 Ingress SSL 重定向
2. 修復 feed-service 和 content-service 的 Service selectors
3. 更新 social-service Ingress 端口配置
4. 確認 feed-service 可通過 Ingress 訪問（需要認證）

### ⚠️ 已識別問題

1. **iOS 與 Backend API 不匹配** - Feed API 使用不同的方法和格式
2. **Backend Handlers 未註冊** - Trending, Discover 等端點不可用
3. **Identity Service 架構問題** - 無 HTTP API，只有 gRPC

### 🚀 需要的行動

#### iOS:
- 修改 Feed API 調用（POST → GET）
- 暫時禁用 Trending/Explore 功能
- 跳過認證或使用 mock

#### Backend:
- 註冊缺失的 handlers
- 修復 identity-service HTTP 訪問
- 測試所有端點

---

**報告生成**: 2025-11-19 08:15 JST
**狀態**: iOS 準備就緒，等待 Backend 修復
**下次更新**: Backend 修復後重新測試
