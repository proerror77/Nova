# iOS 代码审查 - P0/P1 问题快速修复指南

**总结**: 7 个关键问题，需要 ~2 小时修复  
**风险**: 不修复会影响应用稳定性和用户隐私

---

## 问题 1: LocalStorageManager fatalError (P0 - 15 min)

**位置**: `LocalData/Managers/LocalStorageManager.swift:51`

**当前代码**:
```swift
} catch {
    fatalError("❌ Failed to initialize LocalStorageManager: \(error)")
}
```

**问题**: 任何初始化失败都会崩溃应用

**修复方案**:
```swift
private init() {
    do {
        let schema = Schema([...])
        let modelConfiguration = ModelConfiguration(...)
        self.modelContainer = try ModelContainer(...)
        self.modelContext = ModelContext(modelContainer)
        self.modelContext.autosaveEnabled = true
    } catch {
        Logger.log("❌ Failed to initialize LocalStorageManager: \(error)", level: .error)
        // 创建内存模型容器作为备选
        do {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            self.modelContainer = try ModelContainer(for: LocalPost.self, configurations: config)
            self.modelContext = ModelContext(modelContainer)
        } catch {
            fatalError("❌ Failed to initialize even in-memory storage: \(error)")
        }
    }
}
```

---

## 问题 2: AppState 依赖验证 (P0 - 20 min)

**位置**: `ViewModels/Auth/AuthViewModel.swift:60-65, 89-94`

**当前代码**:
```swift
func login() async {
    // ...
    if let appState {
        appState.isAuthenticated = true
    } else {
        assertionFailure("AppState not attached before login()")  // ❌ 生产环境被忽略
    }
}
```

**修复**:
```swift
func login() async {
    guard let appState = appState else {
        self.errorMessage = "System configuration error. Please restart the app."
        self.isLoading = false
        Logger.log("❌ AppState not attached during login", level: .error)
        return
    }
    
    // ... 继续登录逻辑
    appState.isAuthenticated = true
}
```

**同时修改 init**:
```swift
init(authRepository: AuthRepository = AuthRepository(), appState: AppState? = nil) {
    self.authRepository = authRepository
    self.appState = appState
    
    // 如果没有 appState，在这里提示
    if appState == nil {
        Logger.log("⚠️  Warning: AuthViewModel initialized without AppState", level: .warning)
    }
}
```

---

## 问题 3: ChatViewModel WebSocket 生命周期 (P0 - 30 min)

**位置**: `ViewModels/Chat/ChatViewModel.swift:94-104`

**当前代码**:
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

**问题**: 虽然代码看起来正确，但问题在于多个 Task 的管理  
**修复**:

创建一个辅助结构来管理输入状态:

```swift
@Observable
@MainActor
final class ChatViewModel: @unchecked Sendable {
    private var typingCancellations: [UUID: Task<Void, Never>] = [:]
    
    // 在 start() 中修改：
    socket.onTyping = { [weak self] uid in
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            // 取消前一个输入任务
            self.typingCancellations[uid]?.cancel()
            
            self.typingUsernames.insert(uid)
            
            let task = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    self.typingUsernames.remove(uid)
                }
                self.typingCancellations.removeValue(forKey: uid)
            }
            
            self.typingCancellations[uid] = task
        }
    }
    
    // 在 deinit 中清理：
    deinit {
        typingCancellations.values.forEach { $0.cancel() }
        socket.disconnect()
    }
}
```

---

## 问题 4: AuthManager 并发安全 (P1 - 45 min)

**位置**: `Network/Core/AuthManager.swift`

**当前问题**: 非原子访问

**修复方案 A (使用 NSLock)**:

```swift
final class AuthManager {
    static let shared = AuthManager()
    
    private let lock = NSLock()
    private var _currentUser: User?
    private var _isAuthenticated: Bool = false
    
    var currentUser: User? {
        lock.lock()
        defer { lock.unlock() }
        return _currentUser
    }
    
    var isAuthenticated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isAuthenticated
    }
    
    func saveAuth(user: User, tokens: AuthTokens) {
        lock.lock()
        defer { lock.unlock() }
        
        _currentUser = user
        _isAuthenticated = true
        // ... 其他存储操作
    }
    
    func clearAuth() {
        lock.lock()
        defer { lock.unlock() }
        
        _currentUser = nil
        _isAuthenticated = false
    }
}
```

**修复方案 B (使用 @MainActor - 推荐)**:

```swift
@MainActor
final class AuthManager {
    static let shared = AuthManager()
    
    nonisolated(unsafe) private(set) var currentUser: User?
    nonisolated(unsafe) private(set) var isAuthenticated: Bool = false
    
    // ... 其他代码
}
```

---

## 问题 5: OAuth Token 不安全存储 (P1 - 30 min)

**位置**: `ViewModels/Auth/AuthViewModel+OAuth.swift:274-279`

**当前代码**:
```swift
private func saveOAuthTokens(tokens: OAuthTokenResponse, provider: String) throws {
    let keyPrefix = "oauth_\(provider)"
    
    // ❌ 使用 UserDefaults - 不安全！
    UserDefaults.standard.set(tokens.accessToken, forKey: "\(keyPrefix)_access_token")
    if let refreshToken = tokens.refreshToken {
        UserDefaults.standard.set(refreshToken, forKey: "\(keyPrefix)_refresh_token")
    }
    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "\(keyPrefix)_created_at")
}
```

**修复** - 改用 Keychain:

```swift
private func saveOAuthTokens(tokens: OAuthTokenResponse, provider: String) throws {
    let keyPrefix = "oauth_\(provider)"
    
    // ✅ 使用 Keychain - 安全！
    try saveToKeychain(value: tokens.accessToken, key: "\(keyPrefix)_access_token")
    
    if let refreshToken = tokens.refreshToken {
        try saveToKeychain(value: refreshToken, key: "\(keyPrefix)_refresh_token")
    }
    
    // Token 创建时间可以放在 UserDefaults（无敏感信息）
    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "\(keyPrefix)_created_at")
}

private func saveToKeychain(value: String, key: String) throws {
    guard let data = value.data(using: .utf8) else {
        throw NSError(domain: "OAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid data"])
    }
    
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.nova.oauth",
        kSecAttrAccount as String: key,
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ]
    
    // 先删除旧值
    SecItemDelete(query as CFDictionary)
    
    // 添加新值
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw NSError(domain: "Keychain", code: Int(status), userInfo: nil)
    }
}

private func loadFromKeychain(key: String) -> String? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.nova.oauth",
        kSecAttrAccount as String: key,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    
    guard status == errSecSuccess,
          let data = result as? Data,
          let value = String(data: data, encoding: .utf8) else {
        return nil
    }
    
    return value
}
```

---

## 问题 6: 敏感数据日志输出 (P1 - 30 min)

**搜索所有包含敏感信息的日志**:

```bash
grep -r "user\." /Users/proerror/Documents/nova/ios/NovaSocialApp --include="*.swift" | grep Logger
grep -r "tokens\|password\|token\|key" /Users/proerror/Documents/nova/ios/NovaSocialApp --include="*.swift" | grep Logger
```

**示例修复**:

坏的日志:
```swift
Logger.log("✅ Auth saved for user: \(user.username)", level: .info)
Logger.log("Token: \(tokens.accessToken)", level: .debug)
Logger.log("Keys loaded: \(publicKey)", level: .info)
```

好的日志:
```swift
Logger.log("✅ Auth saved for user: \(user.id.uuidString.prefix(8))...", level: .info)
Logger.log("Token saved successfully", level: .debug)  // 不打印实际 token
Logger.log("Keys loaded for encryption", level: .info)  // 不打印密钥
```

---

## 问题 7: Keychain 错误处理 (P1 - 15 min)

**位置**: `Services/Security/CryptoKeyStore.swift:28-40`

**当前代码**:
```swift
private func save(_ value: String, key: String) {
    guard let data = value.data(using: .utf8) else { return }
    let query: [String: Any] = [...]
    SecItemDelete(query as CFDictionary)
    var newQuery = query
    newQuery[kSecValueData as String] = data
    newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(newQuery as CFDictionary, nil)  // ❌ 错误被忽略
}
```

**修复**:

```swift
private func save(_ value: String, key: String) throws {
    guard let data = value.data(using: .utf8) else {
        throw NSError(domain: "CryptoKeyStore", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8 data"])
    }
    
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: key
    ]
    
    // 删除旧值
    let deleteStatus = SecItemDelete(query as CFDictionary)
    if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
        Logger.log("⚠️  Warning deleting old key: \(deleteStatus)", level: .warning)
    }
    
    // 添加新值
    var newQuery = query
    newQuery[kSecValueData as String] = data
    newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    
    let addStatus = SecItemAdd(newQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
        throw NSError(
            domain: "CryptoKeyStore",
            code: Int(addStatus),
            userInfo: [NSLocalizedDescriptionKey: "Failed to save key to Keychain"]
        )
    }
    
    Logger.log("✅ Crypto key saved: \(key)", level: .info)
}

// 更新调用点：
func ensureKeyPair() throws -> (publicKeyB64: String, secretKeyB64: String) {
    if let pk = load(pkKey), let sk = load(skKey) {
        return (pk, sk)
    }
    
    let (pk, sk) = try NaClCrypto.generateKeyPair()
    try save(pk, key: pkKey)  // ✅ 现在会抛出异常
    try save(sk, key: skKey)
    return (pk, sk)
}
```

---

## 测试修复 (可选但推荐)

### 并发测试

```swift
// Tests/Unit/AuthManagerConcurrencyTests.swift
import XCTest
@testable import NovaSocial

final class AuthManagerConcurrencyTests: XCTestCase {
    
    func testConcurrentAuthAccess() async throws {
        let authManager = AuthManager.shared
        let user = User(id: UUID(), username: "test", email: "test@example.com")
        let tokens = AuthTokens(accessToken: "token", refreshToken: "refresh", expiresIn: 3600)
        
        // 并发访问
        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask {
                    if i % 2 == 0 {
                        authManager.saveAuth(user: user, tokens: tokens)
                    } else {
                        _ = authManager.currentUser
                    }
                }
            }
            
            try await group.waitForAll()
        }
        
        // 验证最终状态一致
        XCTAssertEqual(authManager.currentUser?.id, user.id)
        XCTAssertTrue(authManager.isAuthenticated)
    }
}
```

---

## 优先级执行清单

✅ **第 1 天** (2 小时):
- [ ] 问题 1: LocalStorageManager fatalError (15 min)
- [ ] 问题 2: AppState 依赖验证 (20 min)
- [ ] 问题 3: WebSocket 生命周期 (30 min)
- [ ] 问题 4: AuthManager 并发 (45 min)

✅ **第 2-3 天** (4 小时):
- [ ] 问题 5: OAuth Token 安全 (30 min)
- [ ] 问题 6: 日志敏感信息 (30 min)
- [ ] 问题 7: Keychain 错误处理 (15 min)
- [ ] 运行测试套件验证 (60 min)
- [ ] 代码审查 (45 min)

✅ **第 4 天**:
- [ ] 集成测试 (见主审查报告)
- [ ] 提交 PR 合并

---

**总预计时间**: 2-3 天 (开发 6 小时 + 测试 2 小时)  
**风险降低**: 从 5/10 → 8/10

