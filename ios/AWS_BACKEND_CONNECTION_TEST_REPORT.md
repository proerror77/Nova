# AWS Backend 連接測試報告

**測試時間**: 2025-11-18
**測試環境**: Staging (AWS EKS)
**測試者**: iOS Team

---

## 📊 執行摘要

✅ **iOS 代碼已修復並準備連接**
⚠️ **後端服務部分可用，需要修復配置問題**

### 關鍵發現

1. **LoadBalancer URL 已更新** - iOS 現在使用正確的 Ingress LoadBalancer
2. **Host Header 已添加** - APIClient 現在發送正確的 Host header 進行路由
3. **端點配置已優化** - 移除硬編碼，統一使用 APIConfig
4. **Content Service 可用** - v1 API 正常工作（需要認證）
5. **Feed Service 配置錯誤** - Ingress 端口配置不正確

---

## 🔧 iOS 修改清單

### 1. APIConfig.swift

#### 添加 Feed 端點配置
```swift
struct Feed {
    // Feed API (v2) - feed-service
    static let userFeed = "/api/v2/feed/user"
    static let exploreFeed = "/api/v2/feed/explore"
    static let trending = "/api/v2/feed/trending"
}
```

#### 更新 LoadBalancer URL
```swift
case .staging:
    // AWS EKS staging environment - Ingress LoadBalancer URL (Updated: 2025-11-18)
    // Note: Requires Host header "Host: api.nova.local" for Ingress routing
    return "http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com"
```

**變更原因**:
- 舊 URL: `abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com` (無效)
- 新 URL: `a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com` (當前 Ingress)

### 2. APIClient.swift

#### 添加 Host Header
```swift
// Set Host header for Ingress routing (required for staging environment)
if APIConfig.current == .staging {
    request.setValue("api.nova.local", forHTTPHeaderField: "Host")
}
```

**變更原因**:
- Ingress 使用基於主機名的路由 (`host: api.nova.local`)
- 沒有 Host header，Ingress 無法正確路由請求

### 3. SocialService.swift

#### 移除硬編碼端點
```swift
// 之前：硬編碼
endpoint: "/api/v2/feed/user"

// 現在：使用配置
endpoint: APIConfig.Feed.userFeed
```

**變更的方法**:
- `getUserFeed()` - 使用 `APIConfig.Feed.userFeed`
- `getExploreFeed()` - 使用 `APIConfig.Feed.exploreFeed`
- `getTrendingPosts()` - 使用 `APIConfig.Feed.trending`

---

## 🧪 後端服務測試結果

### 測試配置

```bash
LoadBalancer: a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com
Host Header: api.nova.local
測試方法: curl with Host header
```

### 服務狀態總覽

| 服務 | 端點 | HTTP 狀態 | 狀態 | 備註 |
|------|------|----------|------|------|
| **content-service** | `/api/v1/posts` | 401 | ✅ 可用 | 需要認證 token |
| **identity-service** | `/api/v1/users` | 502 | ❌ 不可用 | 只提供 gRPC (port 50051) |
| **feed-service** | `/api/v2/feed/trending` | 503 | ❌ 不可用 | Ingress 端口配置錯誤 |
| **search-service** | `/api/v2/search` | 503 | ❌ 不可用 | 服務或配置問題 |

### 詳細測試結果

#### 1. Content Service (v1) ✅

```bash
$ curl -H "Host: api.nova.local" \
  http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/api/v1/posts

HTTP/1.1 401 Unauthorized
Content-Type: text/plain; charset=utf-8
Content-Length: 28

Missing authentication token
```

**分析**:
- ✅ Ingress 路由正常
- ✅ Service 正常運行
- ✅ 正確返回認證錯誤
- 📝 iOS 需要先獲取 auth token

#### 2. Identity Service (v1) ❌

```bash
$ curl -H "Host: api.nova.local" \
  http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/api/v1/users

HTTP/1.1 502 Bad Gateway
```

**分析**:
- ❌ Service 不提供 HTTP API
- ✅ Service 運行正常 (1/1 Ready)
- ℹ️ 只監聽 gRPC port 50051
- 🔧 需要通過 GraphQL Gateway 或其他方式訪問

**Pods 狀態**:
```
identity-service-7844554d77-b8kpb    1/1     Running
identity-service-7844554d77-bf59f    1/1     Running
identity-service-7844554d77-dwg2p    1/1     Running
```

**日誌**:
```json
{"level":"INFO","message":"Starting gRPC server on 0.0.0.0:50051"}
{"level":"INFO","message":"mTLS enabled - service-to-service authentication active"}
```

#### 3. Feed Service (v2) ❌

```bash
$ curl -H "Host: api.nova.local" \
  http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/api/v2/feed/trending

HTTP/1.1 503 Service Unavailable
```

**分析**:
- ❌ Ingress 配置錯誤
- ✅ feed-service pods 運行中 (3 replicas)
- ❌ Pods 狀態: 0/1 (Running but not Ready)

**問題**:
```yaml
# Ingress 配置（錯誤）
- path: /api/v2/feed
  backend:
    service:
      name: feed-service
      port:
        number: 8080  # ❌ 錯誤！
```

**實際情況**:
```json
{"level":"INFO","message":"starting service: actix-web-service-0.0.0.0:8084"}
{"level":"INFO","message":"gRPC server listening on 0.0.0.0:9084"}
```

**修復方案**:
```bash
# 需要更新 Ingress 配置
kubectl patch ingress nova-api-gateway -n nova-staging --type='json' \
  -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/6/backend/service/port/number", "value": 8084}]'
```

#### 4. Search Service (v2) ❌

```bash
$ curl -H "Host: api.nova.local" \
  http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/api/v2/search?q=test

HTTP/1.1 503 Service Unavailable
```

**分析**:
- ❌ 服務不可用或端口配置錯誤
- 需要進一步調查

---

## 🚨 關鍵問題

### 問題 1: Feed Service Ingress 端口錯誤

**嚴重程度**: P0 (阻塞)
**影響**: iOS 無法訪問 Feed API

**問題描述**:
- Ingress 配置指向 `feed-service:8080`
- feed-service 實際監聽 `0.0.0.0:8084`

**當前 Ingress 配置**:
```yaml
- path: /api/v2/feed
  backend:
    service:
      name: feed-service
      port:
        number: 8080  # ❌ 應該是 8084
```

**修復步驟**:
```bash
# 方案 1: 修改 Ingress 配置
kubectl edit ingress nova-api-gateway -n nova-staging
# 將 feed-service port 從 8080 改為 8084

# 方案 2: 使用 patch
kubectl patch ingress nova-api-gateway -n nova-staging --type='json' \
  -p='[{
    "op": "replace",
    "path": "/spec/rules/0/http/paths/6/backend/service/port/number",
    "value": 8084
  }]'

# 驗證
kubectl get ingress nova-api-gateway -n nova-staging -o yaml | grep -A 5 feed-service
```

### 問題 2: Feed Service 依賴服務不可用

**嚴重程度**: P1
**影響**: Feed 功能降級

**問題描述**:
feed-service 無法連接到多個依賴服務：

```
⚠️  Failed to connect to social-service (點讚、評論)
⚠️  Failed to connect to graph-service (關注關係)
⚠️  Failed to connect to ranking-service (排序算法)
⚠️  Failed to connect to media-service (媒體內容)
⚠️  Failed to connect to notification-service (通知)
⚠️  Failed to connect to analytics-service (分析)
```

**影響**:
- Feed 可能返回空結果或有限的數據
- 某些功能會降級

**修復方案**:
```bash
# 部署缺失的服務
kubectl scale deployment social-service -n nova-staging --replicas=1
kubectl scale deployment graph-service -n nova-staging --replicas=1  # 已部署，檢查連接
kubectl scale deployment ranking-service -n nova-staging --replicas=1
kubectl scale deployment media-service -n nova-staging --replicas=1
kubectl scale deployment notification-service -n nova-staging --replicas=1
kubectl scale deployment analytics-service -n nova-staging --replicas=1  # 已運行但有問題
```

### 問題 3: Identity Service 沒有 HTTP API

**嚴重程度**: P0 (阻塞登錄功能)
**影響**: iOS 無法進行用戶認證

**問題描述**:
- identity-service 只提供 gRPC API (port 50051)
- Ingress 配置為 HTTP (port 8080)
- iOS 需要 HTTP/REST API

**解決方案**:

**方案 A: 使用 GraphQL Gateway** (推薦)
```bash
# 檢查 graphql-gateway 狀態
kubectl get pods -n nova-staging | grep graphql-gateway

# 當前狀態: CrashLoopBackOff
# 需要修復 graphql-gateway

# graphql-gateway 應該將 HTTP/GraphQL 轉換為 gRPC
```

**方案 B: 添加 HTTP Adapter**
```rust
// 在 identity-service 中添加 HTTP 層
// 將 HTTP 請求轉換為內部 gRPC 調用
```

**方案 C: 使用 gRPC-Web** (iOS 端修改)
```swift
// 修改 iOS 使用 gRPC-Web 協議
// 需要額外依賴和實現
```

---

## 🔍 Pod 狀態詳情

### 正常運行的服務 ✅

```
content-service-7fc5d7b7f9-zt665         1/1     Running
identity-service-7844554d77-b8kpb        1/1     Running
identity-service-7844554d77-bf59f        1/1     Running
identity-service-7844554d77-dwg2p        1/1     Running
graph-service-65d5d576dd-n24l2           1/1     Running
```

### 運行但未就緒 ⚠️

```
feed-service-58d5c5fbd5-dsjfq            0/1     Running
feed-service-58d5c5fbd5-qs9pf            0/1     Running
feed-service-58d5c5fbd5-vwsdp            0/1     Running
analytics-service-6c96b4bcc7-hb7wv       0/1     Running
```

### 崩潰循環 ❌

```
api-gateway-c7d5669d4-5w6js              0/1     CrashLoopBackOff
api-gateway-c7d5669d4-6wd68              0/1     CrashLoopBackOff
api-gateway-c7d5669d4-spjmd              0/1     CrashLoopBackOff
graphql-gateway-68f85948df-tw2fb         0/1     CrashLoopBackOff
media-service-545bc67948-ttfwq           0/1     CrashLoopBackOff
```

---

## 📝 iOS 測試建議

### 可以測試的功能

#### 1. Content Service (需要認證)

```swift
// 獲取帖子列表
let posts = try await contentService.getPostsByAuthor(authorId: "test-user")
```

**預期結果**: 401 Unauthorized (直到我們實現登錄)

### 暫時無法測試的功能

#### 1. 用戶登錄/註冊

```swift
// ❌ 無法工作（identity-service 無 HTTP API）
let user = try await authService.login(email: "...", password: "...")
```

**需要**: GraphQL Gateway 或 HTTP Adapter

#### 2. Feed 功能

```swift
// ❌ 無法工作（Ingress 端口配置錯誤）
let feed = try await socialService.getUserFeed(userId: "...")
```

**需要**: 修復 Ingress 配置（8080 → 8084）

#### 3. 搜索功能

```swift
// ❌ 無法工作（服務不可用）
let results = try await searchService.searchUsers(query: "john")
```

**需要**: 檢查 search-service 部署和配置

---

## 🚀 優先修復計劃

### P0: 立即修復（阻塞）

1. **修復 feed-service Ingress 端口**
   ```bash
   kubectl patch ingress nova-api-gateway -n nova-staging --type='json' \
     -p='[{"op": "replace", "path": "/spec/rules/0/http/paths/6/backend/service/port/number", "value": 8084}]'
   ```

   **驗證**:
   ```bash
   curl -H "Host: api.nova.local" \
     http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/api/v2/feed/trending
   # 應該返回 200 或 401（而不是 503）
   ```

2. **修復 identity-service 訪問**
   - 選項 A: 修復 graphql-gateway
   - 選項 B: 添加 HTTP adapter 到 identity-service

   **檢查 graphql-gateway 日誌**:
   ```bash
   kubectl logs -n nova-staging graphql-gateway-68f85948df-tw2fb --tail=50
   ```

### P1: 短期修復（功能降級）

3. **部署 feed-service 依賴服務**
   ```bash
   # social-service（點讚、評論）
   kubectl scale deployment social-service -n nova-staging --replicas=1

   # ranking-service（排序）
   kubectl scale deployment ranking-service -n nova-staging --replicas=1
   ```

4. **檢查 search-service**
   ```bash
   kubectl get pods -n nova-staging | grep search-service
   kubectl logs -n nova-staging <search-pod-name>
   ```

### P2: 中期優化

5. **修復 api-gateway** (如果需要)
   ```bash
   # 檢查 api-gateway 配置
   kubectl logs -n nova-staging api-gateway-c7d5669d4-5w6js
   # 更新 nginx 配置中的 upstream URL
   ```

6. **部署其他服務**
   - notification-service
   - analytics-service（修復 ClickHouse 連接）

---

## 🎯 下一步行動

### 後端團隊

- [ ] 修復 feed-service Ingress 端口配置 (8080 → 8084)
- [ ] 修復 graphql-gateway CrashLoopBackOff
- [ ] 部署 social-service 和 ranking-service
- [ ] 檢查 search-service 狀態

### iOS 團隊

- [x] 更新 APIConfig LoadBalancer URL
- [x] 添加 Host header 到 APIClient
- [x] 移除硬編碼端點，使用 APIConfig
- [ ] 等待後端修復後測試連接
- [ ] 實現認證流程（等待 identity-service 可用）
- [ ] 測試 Feed 功能（等待 Ingress 修復）

---

## 📊 測試清單

### 基礎連接測試

- [x] LoadBalancer 可達性
- [x] Ingress 路由（基於 Host header）
- [x] content-service HTTP API
- [x] identity-service 狀態（gRPC only）
- [x] feed-service 狀態（端口錯誤）

### iOS 代碼測試

- [x] APIConfig.swift 更新
- [x] APIClient.swift Host header
- [x] SocialService.swift 端點引用
- [ ] 實際 HTTP 請求測試（待後端修復）
- [ ] 認證流程測試（待 identity-service 可用）
- [ ] Feed 加載測試（待 Ingress 修復）

---

## 🔗 相關文檔

- `HOME_FEED_STATUS.md` - Feed 服務接入狀態
- `V2_API_MIGRATION_SUMMARY.md` - v2 API 遷移總結
- `STAGING_API_ENDPOINTS.md` - Staging 環境 API 端點

---

**報告生成時間**: 2025-11-18 17:00 JST
**狀態**: iOS 準備就緒，等待後端修復
**下次檢查**: 後端修復 Ingress 後
