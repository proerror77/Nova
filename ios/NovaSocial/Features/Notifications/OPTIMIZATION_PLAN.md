# 通知系統優化計劃

**創建時間**: 2026-01-10 06:00 GMT+8
**狀態**: 規劃中

---

## 📋 已完成的修復（2026-01-10）

### ✅ 1. AvatarView 頭像後備方案
- **問題**: 頭像 URL 加載失敗時顯示警告圖標
- **修復**: 添加 `name` 參數支持首字母縮寫頭像
- **Commit**: df805eb3

### ✅ 2. 關注狀態後端同步
- **問題**: Follow 按鈕狀態僅基於本地 `@State`
- **修復**: 使用 `GraphService.isFollowing()` 查詢真實狀態
- **Commit**: df805eb3

### ✅ 3. 通知導航框架
- **問題**: 無法點擊通知查看相關內容
- **修復**: 添加 `onTap` 處理器和導航邏輯
- **狀態**: 用戶資料導航完成，帖子詳情待實現
- **Commit**: df805eb3, 73af62ce

---

## 🚧 待實現的優化

### 🔴 高優先級

#### 1. 完整的帖子詳情導航

**問題**:
- PostDetailView 需要完整的 `FeedPost` 對象
- 通知只有 `postId`，沒有完整數據
- 當前使用臨時 alert 提示用戶

**解決方案選項**:

**方案 A: 在導航前獲取 FeedPost（推薦）**
```swift
// 在 NotificationView 中
onTap: {
    if let postId = notification.relatedPostId {
        Task {
            do {
                let post = try await contentService.getPost(postId: postId)
                selectedPost = post
                showPostDetail = true
            } catch {
                showError = true
                errorMessage = "Failed to load post"
            }
        }
    }
}
```

**優點**:
- 不需要修改 PostDetailView
- 保持現有架構一致性
- 錯誤處理清晰

**缺點**:
- 需要額外的 API 調用
- 導航有輕微延遲

**方案 B: 創建 PostDetailView 變體**
```swift
struct PostDetailViewWrapper: View {
    let postId: String
    @State private var post: FeedPost?
    @State private var isLoading = true

    var body: some View {
        if isLoading {
            ProgressView()
                .task {
                    post = try? await contentService.getPost(postId: postId)
                    isLoading = false
                }
        } else if let post = post {
            PostDetailView(post: post, ...)
        } else {
            ErrorView()
        }
    }
}
```

**優點**:
- 封裝了加載邏輯
- 可重用於其他場景

**缺點**:
- 增加代碼複雜度
- 需要維護額外組件

**推薦**: 方案 A（簡單直接）

**預計工作量**: 1-2 小時

---

#### 2. 通知分組邏輯優化

**當前問題**:
```swift
// 當前邏輯：相同用戶 + 相同類型 → 只保留最新
let key = "\(userId)_\(notification.type.rawValue)"
```

**問題場景**:
- 用戶 A 點讚了你的 3 個不同帖子
- 只顯示 1 條通知（最新的）
- 用戶錯過了其他 2 個帖子的點讚

**優化方案**:

**選項 1: 按帖子分組（推薦）**
```swift
// 改進：按用戶 + 類型 + 帖子 ID 分組
let key = "\(userId)_\(type)_\(postId ?? "nil")"
```

**選項 2: 智能分組**
```swift
func groupNotifications(_ notifications: [NotificationItem]) -> [NotificationItem] {
    // 只對 follow 類型分組
    if notification.type == .follow {
        // 合併同一用戶的多次關注
    } else {
        // 保留所有其他類型的通知
    }
}
```

**選項 3: 時間窗口分組**
```swift
// 只合併 1 小時內的相同操作
let timeWindow: TimeInterval = 3600
if abs(notification1.timestamp.timeIntervalSince(notification2.timestamp)) < timeWindow {
    // 合併
}
```

**推薦**: 選項 1（簡單有效）

**預計工作量**: 30 分鐘

---

#### 3. 錯誤重試機制

**當前問題**:
```swift
do {
    try await notificationService.markAsRead(notificationId: notificationId)
} catch {
    print("Failed to mark as read")
    // 僅打印日誌，不重試
}
```

**影響**:
- 網絡錯誤時本地狀態與服務器不一致
- 依賴用戶手動刷新

**優化方案**:

```swift
// 添加重試隊列
class NotificationViewModel {
    private var failedOperations: [FailedOperation] = []

    struct FailedOperation {
        let type: OperationType
        let notificationId: String
        let retryCount: Int
        let timestamp: Date
    }

    enum OperationType {
        case markAsRead
        case markAllAsRead
        case follow
        case unfollow
    }

    func markAsRead(notificationId: String) async {
        // 樂觀更新
        updateLocalState()

        do {
            try await notificationService.markAsRead(notificationId: notificationId)
            // 成功：從失敗隊列中移除
            removeFromFailedQueue(notificationId)
        } catch {
            // 失敗：添加到重試隊列
            addToFailedQueue(.markAsRead, notificationId)
        }
    }

    func retryFailedOperations() async {
        for operation in failedOperations where operation.retryCount < 3 {
            // 指數退避重試
            let delay = pow(2.0, Double(operation.retryCount))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            switch operation.type {
            case .markAsRead:
                await retryMarkAsRead(operation.notificationId)
            // ... 其他類型
            }
        }
    }
}
```

**預計工作量**: 2-3 小時

---

### 🟡 中優先級

#### 4. 性能優化

**4.1 批量關注狀態查詢**

**當前問題**:
```swift
// 每個通知單獨查詢關注狀態
for notification in notifications {
    let isFollowing = try await graphService.isFollowing(...)
}
// N 個通知 = N 次 API 調用
```

**優化方案**:
```swift
// 使用批量查詢 API
let userIds = notifications.compactMap { $0.relatedUserId }
let followStatuses = try await graphService.batchCheckFollowing(
    followerId: currentUserId,
    followeeIds: userIds
)

// 1 次 API 調用獲取所有狀態
```

**預計收益**: 減少 90% 的 API 調用

**預計工作量**: 1 小時

---

**4.2 圖片預加載**

**當前問題**:
- 頭像在滾動時才開始加載
- 造成滾動卡頓

**優化方案**:
```swift
// 預加載即將顯示的頭像
func preloadAvatars(for notifications: [NotificationItem]) {
    let urls = notifications.compactMap { $0.userAvatarUrl }
    ImageCache.shared.prefetch(urls: urls)
}

// 在 loadNotifications 成功後調用
await loadNotifications()
preloadAvatars(for: notifications)
```

**預計收益**: 更流暢的滾動體驗

**預計工作量**: 1 小時

---

**4.3 虛擬化長列表**

**當前實現**:
```swift
ScrollView {
    LazyVStack {
        ForEach(notifications) { notification in
            NotificationListItem(...)
        }
    }
}
```

**問題**: 數千條通知時性能下降

**優化方案**:
```swift
// 使用分頁虛擬化
ScrollView {
    LazyVStack {
        ForEach(visibleNotifications) { notification in
            NotificationListItem(...)
                .onAppear {
                    if notification == visibleNotifications.last {
                        loadMore()
                    }
                }
        }
    }
}
```

**預計收益**: 支持無限滾動

**預計工作量**: 已實現 ✅

---

#### 5. 用戶體驗增強

**5.1 下拉刷新動畫**

**當前**: 標準 iOS 刷新指示器

**優化**: 自定義品牌動畫
```swift
.refreshable {
    await viewModel.refresh()
}
.refreshableStyle(CustomRefreshStyle())
```

**預計工作量**: 2 小時

---

**5.2 通知動畫**

**當前**: 無動畫

**優化**: 新通知淡入動畫
```swift
ForEach(notifications) { notification in
    NotificationListItem(...)
        .transition(.opacity.combined(with: .move(edge: .top)))
}
.animation(.easeInOut(duration: 0.3), value: notifications)
```

**預計工作量**: 1 小時

---

**5.3 空狀態優化**

**當前**: 簡單的圖標 + 文字

**優化**:
- 動畫插圖
- 引導用戶操作（"關注更多用戶"）
- 個性化建議

**預計工作量**: 3 小時

---

### 🟢 低優先級

#### 6. 高級功能

**6.1 通知過濾**

```swift
enum NotificationFilter {
    case all
    case unread
    case likes
    case comments
    case follows
}

// UI 頂部添加過濾器
HStack {
    ForEach(NotificationFilter.allCases) { filter in
        FilterButton(filter: filter, isSelected: selectedFilter == filter)
    }
}
```

**預計工作量**: 2 小時

---

**6.2 通知設置**

```swift
struct NotificationSettingsView: View {
    @State private var enableLikes = true
    @State private var enableComments = true
    @State private var enableFollows = true

    var body: some View {
        Form {
            Section("Notification Types") {
                Toggle("Likes", isOn: $enableLikes)
                Toggle("Comments", isOn: $enableComments)
                Toggle("Follows", isOn: $enableFollows)
            }

            Section("Push Notifications") {
                Toggle("Enable Push", isOn: $enablePush)
            }
        }
    }
}
```

**預計工作量**: 3 小時

---

**6.3 通知搜索**

```swift
struct NotificationSearchView: View {
    @State private var searchText = ""

    var filteredNotifications: [NotificationItem] {
        if searchText.isEmpty {
            return notifications
        }
        return notifications.filter {
            $0.userName?.contains(searchText) == true ||
            $0.message.contains(searchText)
        }
    }
}
```

**預計工作量**: 2 小時

---

## 📊 優先級總結

### 立即實施（本週）
1. ✅ AvatarView 名稱參數（已完成）
2. ✅ 關注狀態同步（已完成）
3. 🚧 完整的帖子詳情導航（進行中）
4. 通知分組邏輯優化

### 短期實施（本月）
5. 錯誤重試機制
6. 批量關注狀態查詢
7. 圖片預加載

### 中期實施（下月）
8. 下拉刷新動畫
9. 通知動畫
10. 空狀態優化

### 長期實施（未來）
11. 通知過濾
12. 通知設置
13. 通知搜索

---

## 🎯 成功指標

### 性能指標
- API 調用次數：減少 50%
- 首屏加載時間：< 500ms
- 滾動幀率：60 FPS
- 內存使用：< 100MB

### 用戶體驗指標
- 通知點擊率：提升 30%
- 錯誤率：< 1%
- 用戶滿意度：> 4.5/5

---

## 📝 實施檢查清單

### 帖子詳情導航
- [ ] 添加 ContentService.getPost(postId:) API 調用
- [ ] 實現加載狀態 UI
- [ ] 添加錯誤處理
- [ ] 測試不同通知類型的導航
- [ ] 更新文檔

### 通知分組優化
- [ ] 修改分組邏輯（按帖子 ID）
- [ ] 添加單元測試
- [ ] 驗證不同場景
- [ ] 更新 FRONTEND_CHECK_REPORT.md

### 錯誤重試機制
- [ ] 設計 FailedOperation 數據結構
- [ ] 實現重試隊列
- [ ] 添加指數退避邏輯
- [ ] 實現後台重試
- [ ] 添加持久化（可選）

---

## 🔧 技術債務

### 需要重構的代碼
1. **NotificationListItem 狀態管理**
   - 當前：多個 `@State` 變量
   - 改進：使用 `@Observable` ViewModel

2. **硬編碼的顏色值**
   - 當前：`Color(red: 0.87, green: 0.11, blue: 0.26)`
   - 改進：使用 `DesignTokens.accentColor`

3. **重複的錯誤處理邏輯**
   - 當前：每個 async 函數都有 try-catch
   - 改進：統一的錯誤處理中間件

---

## 📚 參考資料

### 相關文檔
- [FRONTEND_CHECK_REPORT.md](./FRONTEND_CHECK_REPORT.md) - 前端檢查報告
- [DATAFLOW_CHECK_REPORT.md](../../../backend/notification-service/DATAFLOW_CHECK_REPORT.md) - 後端數據流報告
- [APNS_SETUP.md](../../../backend/notification-service/APNS_SETUP.md) - 推送通知配置

### API 文檔
- GraphService: `ios/NovaSocial/Shared/Services/Graph/GraphService.swift`
- NotificationService: `ios/NovaSocial/Shared/Services/Notification/NotificationService.swift`
- ContentService: `ios/NovaSocial/Shared/Services/Content/ContentService.swift`

---

**最後更新**: 2026-01-10 06:00 GMT+8
**維護者**: Claude Sonnet 4.5
