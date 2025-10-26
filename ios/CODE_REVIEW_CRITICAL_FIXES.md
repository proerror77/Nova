# 🔴 iOS前端代码审查 - 关键修复清单

**审查日期**: 2024-10-26
**审查范围**: PushNotificationManager, EditProfileView, ChatView搜索, FeedViewModel
**总问题数**: 20 (其中5个Critical)

---

## 🚨 立即修复 (P0 - 影响功能正常性)

### 1️⃣ [Critical] WebSocket回调中混合Task + DispatchQueue导致内存泄漏
**位置**: `ChatViewModel.swift` 第60-81行
**影响**: 消息未正确清除，内存持续上升

**问题代码**:
```swift
socket.onTyping = { [weak self] uid in
    Task { @MainActor in
        self?.typingUsernames.insert(uid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {  // ❌ 混合并发模型
            self?.typingUsernames.remove(uid)
        }
    }
}
```

**修复**:
```swift
socket.onTyping = { [weak self] uid in
    Task { @MainActor in
        guard let self else { return }

        self.typingUsernames.insert(uid)

        // 使用async/await而非DispatchQueue
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        if !Task.isCancelled {
            self.typingUsernames.remove(uid)
        }
    }
}
```

**优先级**: 🔴 **P0** | **工作量**: 10分钟 | **测试**: 发送消息，观察typing提示消失

---

### 2️⃣ [Critical] EditProfileView的Task黑洞
**位置**: `EditProfileView.swift` 第34-40行
**影响**: 如果View在保存中途销毁，数据不一致

**问题代码**:
```swift
Button {
    Task {  // ❌ 黑洞Task：View销毁时无法cancel
        if let updated = await viewModel.saveChanges() {
            onSave(updated)
            dismiss()
        }
    }
}
```

**修复**:
```swift
@State private var saveTask: Task<Void, Never>?

var body: some View {
    Form {
        // ...
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                saveTask?.cancel()  // 清理前一个任务

                saveTask = Task {
                    do {
                        if let updated = await viewModel.saveChanges() {
                            onSave(updated)
                            dismiss()
                        }
                    } catch {
                        viewModel.errorMessage = error.localizedDescription
                        viewModel.showError = true
                    }
                }
            }
            .disabled(viewModel.isSaving)
        }
    }
    .onDisappear {
        saveTask?.cancel()  // View销毁时清理
    }
}
```

**优先级**: 🔴 **P0** | **工作量**: 15分钟 | **测试**: 编辑资料，在保存中快速返回，检查是否crash

---

### 3️⃣ [Critical] FeedViewModel.toggleLike()的并发控制缺失
**位置**: `FeedViewModel.swift` 第180-201行
**影响**: 快速点击Like按钮会导致多个网络请求和UI不一致

**问题代码**:
```swift
func toggleLike(for post: Post) {
    // ... 乐观更新 ...

    Task {  // ❌ 可以被同时调用多次
        do {
            let postRepository = PostRepository()  // ❌ 每次创建新对象
            if wasLiked {
                _ = try await postRepository.unlikePost(id: post.id)
            } else {
                _ = try await postRepository.likePost(id: post.id)
            }
        } catch {
            await rollbackOptimisticUpdate(for: post.id)
        }
    }
}
```

**修复**:
```swift
@MainActor
final class FeedViewModel: ObservableObject {
    private let postRepository: PostRepository  // DI注入
    private var likeOperations: [UUID: Task<Void, Never>] = [:]

    func toggleLike(for post: Post) {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else {
            return
        }

        // 防止重复点击 - 如果操作进行中，直接返回
        if likeOperations[post.id] != nil {
            return
        }

        let originalPost = posts[index]
        let wasLiked = originalPost.isLiked

        optimisticUpdateBackup[post.id] = originalPost

        // 乐观更新UI
        let updatedPost = Post(
            id: originalPost.id,
            userId: originalPost.userId,
            imageUrl: originalPost.imageUrl,
            thumbnailUrl: originalPost.thumbnailUrl,
            caption: originalPost.caption,
            likeCount: wasLiked ? originalPost.likeCount - 1 : originalPost.likeCount + 1,
            commentCount: originalPost.commentCount,
            isLiked: !wasLiked,
            createdAt: originalPost.createdAt,
            user: originalPost.user
        )

        withAnimation(.easeInOut(duration: 0.2)) {
            posts[index] = updatedPost
        }

        let task = Task {
            do {
                if wasLiked {
                    _ = try await postRepository.unlikePost(id: post.id)
                } else {
                    _ = try await postRepository.likePost(id: post.id)
                }

                optimisticUpdateBackup.removeValue(forKey: post.id)
            } catch {
                await rollbackOptimisticUpdate(for: post.id)
                showErrorMessage("Failed to \(wasLiked ? "unlike" : "like") post")
            }
        }

        likeOperations[post.id] = task

        // 清理完成的操作
        Task {
            await task.value
            likeOperations.removeValue(forKey: post.id)
        }
    }
}
```

**优先级**: 🔴 **P0** | **工作量**: 30分钟 | **测试**: 快速连续点击Like按钮，检查网络请求计数和UI状态

---

### 4️⃣ [Critical] PushNotificationManager的Token注册竞态条件
**位置**: `PushNotificationManager.swift` 第41-70行
**影响**: Token可能不同步或重复注册

**问题代码**:
```swift
func synchronizeCachedTokenIfNeeded(force: Bool = false) {
    guard AuthManager.shared.isAuthenticated,
          let token = UserDefaults.standard.string(forKey: deviceTokenKey),
          !token.isEmpty else {
        return
    }

    Task {  // ❌ 无结构化并发管理，可能内存泄漏
        do {
            try await repository.registerDeviceToken(...)
            UserDefaults.standard.set(token, forKey: syncedTokenKey)
        } catch { ... }
    }
}
```

**修复**:
```swift
@MainActor
final class PushNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    private var syncTask: Task<Void, Never>?

    @MainActor
    func synchronizeCachedTokenIfNeeded(force: Bool = false) {
        guard AuthManager.shared.isAuthenticated,
              let token = UserDefaults.standard.string(forKey: deviceTokenKey),
              !token.isEmpty else {
            return
        }

        let lastSynced = UserDefaults.standard.string(forKey: syncedTokenKey)
        if !force && lastSynced == token {
            return  // 已同步过，不需要重复
        }

        // 取消前一个同步任务
        syncTask?.cancel()
        syncTask = nil

        syncTask = Task {
            do {
                try await repository.registerDeviceToken(
                    token: token,
                    platform: "ios",
                    appVersion: Bundle.main.appVersion ?? "unknown",
                    locale: Locale.current.identifier
                )
                UserDefaults.standard.set(token, forKey: syncedTokenKey)
                Logger.log("Device token synced successfully", level: .info)
            } catch {
                Logger.log("Failed to sync device token: \(error)", level: .error)
            }
        }
    }

    deinit {
        syncTask?.cancel()
    }
}
```

**修复登入时的调用**:
```swift
private func registerObservers() {
    let loginObserver = NotificationCenter.default.addObserver(
        forName: .authDidLogin,
        object: nil,
        queue: .main
    ) { [weak self] _ in
        Task { @MainActor in  // ✓ 改成async
            self?.synchronizeCachedTokenIfNeeded(force: true)
        }
    }
}
```

**优先级**: 🔴 **P0** | **工作量**: 20分钟 | **测试**: 登入/登出/重启应用，检查设备token是否正确同步

---

### 5️⃣ [Critical] 离线消息重试的指数退避计算错误
**位置**: `ChatViewModel.swift` 第185行
**影响**: 重试延迟不符合预期，可能造成服务器压力

**问题代码**:
```swift
let delaySeconds = Double(min(2 << currentRetryCount, 60))  // ❌ 位移运算不对
```

**修复**:
```swift
// 标准指数退避：1s, 2s, 4s, 8s, 16s, 32s, 60s (capped)
let delays = [1, 2, 4, 8, 16, 32, 60]
let delaySeconds = Double(delays[min(currentRetryCount, delays.count - 1)])

// 或者用pow计算
let delaySeconds = min(pow(2.0, Double(currentRetryCount)), 60.0)
```

**优先级**: 🔴 **P0** | **工作量**: 5分钟 | **测试**: 离线发送消息，观察日志中的重试延迟

---

## 🟡 本周修复 (P1 - 影响用户体验)

### 6️⃣ EditProfileViewModel的状态管理冗余
**位置**: `EditProfileViewModel.swift`
**影响**: 状态管理混乱，易出bug

**问题代码**:
```swift
@Published var displayName: String
@Published var bio: String
@Published var isSaving = false
@Published var errorMessage: String?
@Published var showError = false  // ❌ 两个变量维护一个概念
```

**修复**:
```swift
@Observable
@MainActor
final class EditProfileViewModel {
    enum SaveState {
        case idle
        case saving
        case success(User)
        case failure(String)
    }

    var displayName: String
    var bio: String
    var saveState: SaveState = .idle

    // 计算属性，方便UI使用
    var isSaving: Bool {
        if case .saving = saveState { return true }
        return false
    }

    var errorMessage: String? {
        if case .failure(let msg) = saveState { return msg }
        return nil
    }
}
```

**优先级**: 🟡 **P1** | **工作量**: 20分钟 | **测试**: 编辑资料，检查各种保存状态的UI反馈

---

### 7️⃣ ChatView搜索的内存泄漏
**位置**: `ChatView.swift` 第95-115行
**影响**: 频繁搜索会导致内存持续占用

**问题代码**:
```swift
@State private var searchTask: Task<Void, Never>?

private func handleSearchQueryChange(_ newValue: String) {
    searchTask?.cancel()

    searchTask = Task { [trimmed] in
        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return
        }

        if Task.isCancelled { return }
        await vm.searchMessages(query: trimmed)
    }
}
```

**修复**:
```swift
@State private var searchTask: Task<Void, Never>?

private func handleSearchQueryChange(_ newValue: String) {
    searchTask?.cancel()
    searchTask = nil

    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        vm.clearSearchResults()
        return
    }

    searchTask = Task {
        // 300ms去抖动
        try? await Task.sleep(nanoseconds: 300_000_000)

        if !Task.isCancelled {
            await vm.searchMessages(query: trimmed)
        }
    }
}

// 在onDisappear中清理
.onDisappear {
    searchTask?.cancel()
    searchTask = nil
}
```

**优先级**: 🟡 **P1** | **工作量**: 15分钟 | **测试**: 频繁搜索消息，观察内存使用

---

### 8️⃣ UserProfileViewModel的并发加载保护
**位置**: `ProfileView.swift` 第87-91行
**影响**: 滑动刷新时可能多个loadProfile()并发执行

**修复**:
```swift
@MainActor
final class UserProfileViewModel: ObservableObject {
    enum ViewState {
        case idle
        case loading
        case loaded(user: User, stats: UserStats?, posts: [Post])
        case error(String)
    }

    @Published var viewState: ViewState = .idle

    func loadProfile() async {
        guard case .idle = viewState else {
            return  // 防止重复加载
        }

        viewState = .loading
        do {
            let profile = try await userRepository.getUserProfile(userId: userId ?? AuthManager.shared.currentUser!.id)
            let posts = try await userRepository.getUserPosts(userId: profile.user.id, limit: 50)
            viewState = .loaded(user: profile.user, stats: profile.stats, posts: posts)
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }
}
```

**在View中**:
```swift
.task {
    if case .idle = viewModel.viewState {
        await viewModel.loadProfile()
    }
}
.refreshable {
    viewModel.viewState = .idle
    await viewModel.loadProfile()
}
```

**优先级**: 🟡 **P1** | **工作量**: 20分钟 | **测试**: 快速下拉刷新，检查网络请求数

---

### 9️⃣ ChatMessage撤销状态设计
**位置**: `ChatViewModel.swift` 第10行
**影响**: 消息状态管理混乱

**修复**:
```swift
struct ChatMessage: Identifiable, Equatable {
    enum State {
        case normal(text: String)
        case recalled(recalledAt: Date)
    }

    let id: UUID
    let state: State
    let mine: Bool
    let createdAt: Date

    var text: String {
        if case .normal(let text) = state {
            return text
        }
        return "(已撤销)"
    }
}
```

**优先级**: 🟡 **P1** | **工作量**: 15分钟 | **测试**: 撤销消息，检查UI显示

---

### 🔟 所有ViewModel从@Published迁移到@Observable
**位置**: 所有ViewModel文件
**影响**: 性能和Swift Concurrency兼容性

**修复模板**:
```swift
// ❌ 旧方式
final class FeedViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var isLoading = false
}

// ✅ 新方式
@Observable
@MainActor
final class FeedViewModel {
    var posts: [Post] = []
    var isLoading = false
}
```

**优先级**: 🟡 **P1** | **工作量**: 3小时 (全项目迁移) | **测试**: 逐个ViewModel测试其对应的页面

---

## 🟢 后续优化 (P2 - Nice to have)

### 11️⃣ SearchService缺失去抖动保护
```swift
final class SearchService: Sendable {
    private var lastSearchTask: Task<Void, Never>?

    func searchUsers(query: String) async throws -> [User] {
        guard !query.isEmpty else { return [] }

        lastSearchTask?.cancel()  // 取消前一个搜索

        let cacheKey = "search_users_\(query)"
        if let cached: [User] = cache.get(for: cacheKey) {
            return cached
        }

        let response: SearchResponse = try await httpClient.request(...)
        cache.set(response.users, for: cacheKey, ttl: 300)

        return response.users
    }
}
```

**优先级**: 🟢 **P2** | **工作量**: 10分钟

---

### 1️⃣2️⃣ PushTokenRepository改用Body而非URL
```swift
func unregisterDeviceToken(token: String) async throws {
    guard !token.isEmpty else { throw ValidationError.emptyInput }

    let endpoint = APIEndpoint(
        path: "/notifications/device-tokens",
        method: .delete,
        body: ["device_token": token]  // 改成body
    )

    try await interceptor.executeNoResponseWithRetry(endpoint)
}
```

**优先级**: 🟢 **P2** | **工作量**: 10分钟

---

### 1️⃣3️⃣ AuthManager敏感信息应存Keychain而非UserDefaults
```swift
@MainActor
final class AuthManager {
    private(set) var currentUser: User?  // 仅内存，不持久化

    func saveAuth(user: User, tokens: AuthTokens) {
        currentUser = user  // 内存
        isAuthenticated = true

        // 所有敏感信息存Keychain
        saveToKeychain(value: try! JSONEncoder().encode(user).base64EncodedString(), key: "current_user")
        saveToKeychain(value: tokens.accessToken, key: accessTokenKey)
        saveToKeychain(value: tokens.refreshToken, key: refreshTokenKey)
    }
}
```

**优先级**: 🟢 **P2** | **工作量**: 20分钟

---

## 📋 修复执行计划

### 第1天 (立即，全部P0)
```
1. 修复WebSocket typing (10分钟)
2. 修复EditProfileView Task (15分钟)
3. 修复FeedViewModel.toggleLike (30分钟)
4. 修复PushNotificationManager (20分钟)
5. 修复重试延迟计算 (5分钟)

总计: ~80分钟
```

### 第2-3天 (P1功能)
```
6. 修复EditProfileViewModel状态 (20分钟)
7. 修复ChatView搜索内存泄漏 (15分钟)
8. 修复UserProfileViewModel并发 (20分钟)
9. 修复ChatMessage撤销状态 (15分钟)
10. 迁移所有ViewModel到@Observable (3小时)

总计: ~4小时
```

### 第4天 (P2优化)
```
11-13. SearchService、URL编码、Keychain (30分钟)

总计: ~30分钟
```

---

## ✅ 验证清单

修复后需要测试：

- [ ] 快速点击Like按钮，检查网络请求数（应该只有最后一个生效）
- [ ] 编辑资料在保存中途返回，检查是否crash
- [ ] 频繁搜索消息，检查内存使用（Instruments Memory Profiler）
- [ ] 登入/登出，检查设备Token是否正确同步
- [ ] 离线发送消息后恢复连接，检查重试间隔（1s, 2s, 4s...）
- [ ] 快速下拉刷新多次，检查网络请求数（应该dedup）
- [ ] WebSocket消息，检查typing提示正确消失（3s后）
- [ ] 运行`xcodebuild build -scheme Nova -configuration Debug`，确保无警告

---

## 🚀 Xcode Build验证

在执行修复前，先运行：

```bash
cd /Users/proerror/Documents/nova/ios/NovaSocialApp
xcodebuild build \
  -scheme NovaSocialApp \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  2>&1 | tee build.log

# 检查是否有error (警告可以接受)
grep -i "error:" build.log
```

修复后再运行一遍确保编译通过。

---

**预计总工作量**: 5-6小时
**建议完成时间**: 2-3天
**优先级**: P0 (80分钟) → P1 (4小时) → P2 (30分钟)
