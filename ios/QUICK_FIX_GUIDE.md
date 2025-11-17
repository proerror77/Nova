# 🚀 iOS快速修复指南 - 5个关键Bug修复

快速、直接的修复步骤。完成后运行Xcode build验证。

---

## 🔴 Bug #1: WebSocket消息内存泄漏 (10分钟)

**文件**: `NovaSocialApp/ViewModels/Chat/ChatViewModel.swift`

**查找这一段**:
```swift
socket.onTyping = { [weak self] uid in
    Task { @MainActor in
        self?.typingUsernames.insert(uid)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self?.typingUsernames.remove(uid)
        }
    }
}
```

**替换为**:
```swift
socket.onTyping = { [weak self] uid in
    Task { @MainActor in
        guard let self else { return }
        self.typingUsernames.insert(uid)

        try? await Task.sleep(nanoseconds: 3_000_000_000)

        if !Task.isCancelled {
            self.typingUsernames.remove(uid)
        }
    }
}
```

**✅ Done** - 移除DispatchQueue，统一使用async/await

---

## 🔴 Bug #2: 编辑资料保存Task黑洞 (15分钟)

**文件**: `NovaSocialApp/Views/User/EditProfileView.swift`

**找到保存按钮的点击处理**:
```swift
ToolbarItem(placement: .confirmationAction) {
    Button {
        Task {
            if let updated = await viewModel.saveChanges() {
                onSave(updated)
                dismiss()
            }
        }
    }
}
```

**完整替换整个View**:
```swift
import SwiftUI

struct EditProfileView: View {
    let user: User
    let onSave: (User) -> Void
    @Environment(\.dismiss) var dismiss

    @StateObject private var viewModel: EditProfileViewModel
    @State private var saveTask: Task<Void, Never>?

    init(user: User, onSave: @escaping (User) -> Void) {
        self.user = user
        self.onSave = onSave
        _viewModel = StateObject(wrappedValue: EditProfileViewModel(user: user))
    }

    var body: some View {
        Form {
            Section("Display Name") {
                TextField("Name", text: $viewModel.displayName)
            }

            Section("Bio") {
                TextEditor(text: $viewModel.bio)
                    .frame(height: 100)
            }
        }
        .navigationTitle("Edit Profile")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveTask?.cancel()

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
        .alert(isPresented: $viewModel.showError) {
            Alert(title: Text("Error"), message: Text(viewModel.errorMessage ?? "Unknown error"))
        }
        .onDisappear {
            saveTask?.cancel()
        }
    }
}
```

**✅ Done** - 添加了Task追踪和cleanup

---

## 🔴 Bug #3: Like按钮快速点击导致多个网络请求 (30分钟)

**文件**: `NovaSocialApp/ViewModels/Feed/FeedViewModel.swift`

**在FeedViewModel顶部添加**:
```swift
@MainActor
final class FeedViewModel: ObservableObject {
    // ... 现有代码 ...

    // 添加这行
    private var likeOperations: [UUID: Task<Void, Never>] = [:]
```

**找到这个方法**:
```swift
func toggleLike(for post: Post) {
    // ... 现有乐观更新代码 ...

    Task {
        do {
            let postRepository = PostRepository()
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

**替换为**:
```swift
func toggleLike(for post: Post) {
    guard let index = posts.firstIndex(where: { $0.id == post.id }) else {
        return
    }

    // 防止同一个post的like操作并发执行
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

    Task {
        await task.value
        likeOperations.removeValue(forKey: post.id)
    }
}
```

**✅ Done** - 添加了并发控制

---

## 🔴 Bug #4: Push通知Token注册竞态 (20分钟)

**文件**: `NovaSocialApp/Services/Notifications/PushNotificationManager.swift`

**在class顶部添加**:
```swift
@MainActor
final class PushNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    // ... 现有代码 ...

    // 添加这行
    private var syncTask: Task<Void, Never>?
```

**找到synchronizeCachedTokenIfNeeded方法**:
```swift
func synchronizeCachedTokenIfNeeded(force: Bool = false) {
    guard AuthManager.shared.isAuthenticated,
          let token = UserDefaults.standard.string(forKey: deviceTokenKey),
          !token.isEmpty else {
        return
    }

    Task {
        do {
            try await repository.registerDeviceToken(...)
            UserDefaults.standard.set(token, forKey: syncedTokenKey)
        } catch { ... }
    }
}
```

**替换为**:
```swift
func synchronizeCachedTokenIfNeeded(force: Bool = false) {
    guard AuthManager.shared.isAuthenticated,
          let token = UserDefaults.standard.string(forKey: deviceTokenKey),
          !token.isEmpty else {
        return
    }

    let lastSynced = UserDefaults.standard.string(forKey: syncedTokenKey)
    if !force && lastSynced == token {
        return
    }

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
        } catch {
            Logger.log("Failed to sync device token: \(error)", level: .error)
        }
    }
}
```

**在deinit中添加**:
```swift
deinit {
    syncTask?.cancel()
}
```

**找到registerObservers方法中的登入观察器**:
```swift
let loginObserver = NotificationCenter.default.addObserver(
    forName: .authDidLogin,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.synchronizeCachedTokenIfNeeded()  // ❌ 同步调用async方法
}
```

**改为**:
```swift
let loginObserver = NotificationCenter.default.addObserver(
    forName: .authDidLogin,
    object: nil,
    queue: .main
) { [weak self] _ in
    Task { @MainActor in
        self?.synchronizeCachedTokenIfNeeded(force: true)
    }
}
```

**✅ Done** - 添加了Task追踪和重复同步检查

---

## 🔴 Bug #5: 离线消息重试延迟计算错误 (5分钟)

**文件**: `NovaSocialApp/ViewModels/Chat/ChatViewModel.swift`

**找到这一行**:
```swift
let delaySeconds = Double(min(2 << currentRetryCount, 60))
```

**替换为**:
```swift
// 标准指数退避：1s, 2s, 4s, 8s, 16s, 32s, 60s (capped)
let delays = [1, 2, 4, 8, 16, 32, 60]
let delaySeconds = Double(delays[min(currentRetryCount, delays.count - 1)])
```

**✅ Done** - 修复了指数退避计算

---

## 🧪 验证所有修复

修复完成后，运行以下命令验证编译：

```bash
cd /Users/proerror/Documents/nova/ios/NovaSocialApp

# 清理旧build
xcodebuild clean -scheme NovaSocialApp

# 构建Debug版本
xcodebuild build \
  -scheme NovaSocialApp \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  2>&1 | tee build.log

# 检查是否有error
echo "---"
echo "Build errors:"
grep -i "error:" build.log || echo "✅ No errors found!"
```

---

## 📝 修复后测试清单

- [ ] 快速点击Like按钮5次，检查网络tab中是否只有1个like请求
- [ ] 编辑资料，在保存中途快速返回，确保不crash
- [ ] 聊天窗口，发送消息，观察typing提示是否在3秒后消失
- [ ] 登入/登出，检查系统日志中device token是否同步
- [ ] 离线模式下发送消息，观察重试间隔是否为1s, 2s, 4s...

---

## 💾 提交修复

修复完成后提交：

```bash
git add -A
git commit -m "fix(ios): Critical bug fixes - concurrency, memory leaks, token sync

- Fix WebSocket typing callback mixing Task + DispatchQueue
- Fix EditProfileView Task black hole memory leak
- Fix FeedViewModel.toggleLike concurrent requests
- Fix PushNotificationManager token registration race condition
- Fix offline message retry exponential backoff calculation"

git push origin feature/US3-message-search-fulltext
```

---

**Total Time**: ~80 minutes
**Complexity**: 🔴 Critical
**Impact**: High - Fixes core functionality bugs

完成后，可以继续做P1的ViewModel@Observable迁移。
