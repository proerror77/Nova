# ICERED 全面性 QA 自動化測試計劃

## 📋 概覽

本計劃涵蓋 iOS 應用和後端服務的全面性自動化測試，包括：
- 單元測試 (Unit Tests)
- UI 自動化測試 (XCUITest)
- API 整合測試 (Integration Tests)
- 端對端測試 (E2E Tests)
- 效能測試 (Performance Tests)

---

## 🏗️ 測試架構

```
┌─────────────────────────────────────────────────────────────┐
│                    E2E Tests (端對端)                        │
│    完整用戶流程：註冊 → 登入 → 瀏覽 Feed → 互動 → 聊天      │
├─────────────────────────────────────────────────────────────┤
│                Integration Tests (整合測試)                  │
│         API 端點測試、服務間通訊、資料庫操作                 │
├─────────────────────────────────────────────────────────────┤
│                  UI Tests (UI 自動化)                        │
│           XCUITest：畫面流程、按鈕操作、表單驗證             │
├─────────────────────────────────────────────────────────────┤
│                  Unit Tests (單元測試)                       │
│          Model 解析、Service 邏輯、ViewModel 狀態           │
└─────────────────────────────────────────────────────────────┘
```

---

## 📱 iOS 測試計劃

### 1. 單元測試 (Unit Tests)

#### 1.1 Feed 模組測試
| 測試檔案 | 測試內容 | 優先級 |
|---------|---------|--------|
| `FeedServiceTests.swift` | FeedPostRaw JSON 解析 | P0 |
| `FeedServiceTests.swift` | bookmarkCount 欄位解析 | P0 |
| `FeedServiceTests.swift` | Feed 分頁載入邏輯 | P1 |
| `ContentModelsTests.swift` | Post model Codable | P0 |
| `ContentModelsTests.swift` | FeedPost 轉換邏輯 | P1 |

#### 1.2 Chat/Matrix 模組測試
| 測試檔案 | 測試內容 | 優先級 |
|---------|---------|--------|
| `ChatServiceTests.swift` | 訊息去重邏輯 | P0 |
| `MatrixServiceTests.swift` | Session 恢復邏輯 | P0 |
| `MatrixServiceTests.swift` | Token 刷新機制 | P1 |
| `ChatViewModelTests.swift` | 訊息狀態管理 | P1 |

#### 1.3 認證模組測試
| 測試檔案 | 測試內容 | 優先級 |
|---------|---------|--------|
| `AuthenticationManagerTests.swift` | 登入流程 | P0 |
| `AuthenticationManagerTests.swift` | Token 儲存/讀取 | P0 |
| `AuthenticationManagerTests.swift` | Session 過期處理 | P1 |

### 2. UI 自動化測試 (XCUITest)

#### 2.1 認證流程
```swift
// 測試案例
- testLoginWithEmail()           // 郵箱密碼登入
- testLoginWithPasskey()         // Passkey 登入 (真機)
- testRegistrationFlow()         // 註冊流程
- testLogout()                   // 登出
- testSessionExpiry()            // Session 過期重新登入
```

#### 2.2 Feed 功能
```swift
// 測試案例
- testFeedLoads()                // Feed 載入
- testFeedScrolling()            // 滾動分頁
- testLikePost()                 // 點讚操作
- testBookmarkPost()             // 書籤操作
- testBookmarkCountDisplay()     // 書籤數顯示
- testChannelSwitching()         // 頻道切換
```

#### 2.3 聊天功能
```swift
// 測試案例
- testOpenChat()                 // 開啟聊天
- testSendMessage()              // 發送訊息
- testMessageNotDuplicated()     // 訊息不重複
- testReceiveMessage()           // 接收訊息
- testGroupChat()                // 群組聊天
```

#### 2.4 Profile 功能
```swift
// 測試案例
- testViewOwnProfile()           // 查看自己 Profile
- testViewOtherProfile()         // 查看他人 Profile
- testEditProfile()              // 編輯 Profile
- testProfilePostsDisplay()      // Profile 帖子顯示
```

### 3. 快照測試 (Snapshot Tests)
```swift
// 使用 swift-snapshot-testing
- FeedPostCard 各種狀態
- ProfilePostCard 各種狀態
- ChatBubble 各種狀態
- 空狀態畫面
```

---

## 🖥️ 後端測試計劃

### 1. API 整合測試

#### 1.1 Feed API
| 端點 | 測試內容 | 優先級 |
|-----|---------|--------|
| `GET /api/v2/feed` | 回傳 bookmark_count | P0 |
| `GET /api/v2/feed` | 分頁功能 | P1 |
| `GET /api/v2/feed/trending` | Trending 演算法 | P1 |
| `GET /api/v2/feed/explore` | Explore 功能 | P2 |

#### 1.2 Social API
| 端點 | 測試內容 | 優先級 |
|-----|---------|--------|
| `POST /api/v2/bookmarks` | 新增書籤 | P0 |
| `DELETE /api/v2/bookmarks` | 刪除書籤 | P0 |
| `GET /api/v2/bookmarks` | 查詢書籤 | P1 |

#### 1.3 Content API
| 端點 | 測試內容 | 優先級 |
|-----|---------|--------|
| `GET /api/v2/posts/{id}` | 帖子詳情含 bookmark_count | P0 |
| `GET /api/v2/posts/author/{id}` | 作者帖子列表 | P1 |

### 2. gRPC 服務測試
```rust
// feed-service
- test_get_feed_returns_bookmark_count()
- test_feed_pagination()
- test_feed_algorithm_v2()

// social-service
- test_bookmark_creates_correctly()
- test_bookmark_count_increments()
- test_get_counters_batch()

// content-service
- test_post_includes_counts()
```

---

## 🔄 CI/CD 測試流水線

### GitHub Actions Workflow

```yaml
# .github/workflows/test-ios.yml
name: iOS Tests

on:
  push:
    paths:
      - 'ios/**'
  pull_request:
    paths:
      - 'ios/**'

jobs:
  unit-tests:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Run Unit Tests
        run: |
          xcodebuild test \
            -workspace ios/NovaSocial/ICERED.xcodeproj/project.xcworkspace \
            -scheme ICERED \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -only-testing:ICEREDTests

  ui-tests:
    runs-on: macos-14
    needs: unit-tests
    steps:
      - uses: actions/checkout@v4
      - name: Run UI Tests
        run: |
          xcodebuild test \
            -workspace ios/NovaSocial/ICERED.xcodeproj/project.xcworkspace \
            -scheme ICERED \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -only-testing:ICEREDUITests
```

```yaml
# .github/workflows/test-backend.yml
name: Backend Tests

on:
  push:
    paths:
      - 'backend/**'
  pull_request:
    paths:
      - 'backend/**'

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Run Unit Tests
        run: cargo test --workspace

  integration-tests:
    runs-on: ubuntu-latest
    needs: unit-tests
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: test
        ports:
          - 5432:5432
      redis:
        image: redis:7
        ports:
          - 6379:6379
    steps:
      - uses: actions/checkout@v4
      - name: Run Integration Tests
        run: cargo test --workspace -- --ignored
```

---

## 📊 測試覆蓋率目標

| 模組 | 目標覆蓋率 | 當前狀態 |
|-----|-----------|---------|
| iOS Models | 90% | 待測量 |
| iOS Services | 80% | 待測量 |
| iOS ViewModels | 70% | 待測量 |
| Backend APIs | 85% | 待測量 |
| Backend Services | 80% | 待測量 |

---

## 🚀 執行測試

### iOS 測試
```bash
# 單元測試
xcodebuild test -scheme ICERED -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:ICEREDTests

# UI 測試
xcodebuild test -scheme ICERED -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:ICEREDUITests

# 全部測試
xcodebuild test -scheme ICERED -destination 'platform=iOS Simulator,name=iPhone 15'
```

### 後端測試
```bash
# 單元測試
cd backend && cargo test

# 整合測試 (需要 Docker)
cd backend && cargo test -- --ignored

# 特定服務測試
cd backend/graphql-gateway && cargo test
cd backend/feed-service && cargo test
```

---

## 📅 實施時程

### Phase 1: 基礎建設 (Week 1)
- [ ] 設置 iOS 測試 Target 結構
- [ ] 設置測試 Mock/Fixture 架構
- [ ] 配置 CI/CD 測試流水線

### Phase 2: 單元測試 (Week 2)
- [ ] Feed 模組單元測試
- [ ] Chat 模組單元測試
- [ ] 認證模組單元測試

### Phase 3: UI 自動化 (Week 3)
- [ ] 認證流程 UI 測試
- [ ] Feed 功能 UI 測試
- [ ] Chat 功能 UI 測試

### Phase 4: 整合測試 (Week 4)
- [ ] Backend API 整合測試
- [ ] E2E 測試完善
- [ ] 效能測試基準

---

## 📝 測試報告

測試執行後會生成以下報告：
- JUnit XML 報告 (CI/CD 整合)
- 測試覆蓋率報告 (Codecov)
- UI 測試截圖 (失敗時)
- 效能測試基準報告
