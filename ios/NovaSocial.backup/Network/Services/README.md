# Performance Optimization Services

高性能缓存和请求优化系统，为 Nova iOS 应用提供企业级性能优化能力。

## 📋 功能概览

| 组件 | 功能 | 文件 |
|-----|------|-----|
| **CacheManager** | 带 TTL 的内存缓存 | `CacheManager.swift` |
| **RequestDeduplicator** | 请求去重器 | `RequestDeduplicator.swift` |
| **NetworkMonitor** | 网络状态监听 | `NetworkMonitor.swift` |
| **PerformanceMetrics** | 性能指标收集 | `PerformanceMetrics.swift` |
| **URLCacheConfig** | 图片/资源缓存 | `URLCacheConfig.swift` |
| **PerformanceDebugView** | 调试工具 | `PerformanceDebugView.swift` |

## 🚀 快速开始

### 1. 初始化（AppDelegate/SceneDelegate）

```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions ...) -> Bool {
    // 配置 URLCache（图片缓存）
    URLCacheConfig.configure()

    // 启动网络监听
    NetworkMonitor.shared.startMonitoring()

    #if DEBUG
    // 启用性能调试（可选）
    PerformanceDebugView.startAutoLogging(interval: 60)
    #endif

    return true
}
```

### 2. 在 Repository 中使用

```swift
final class PostRepository {
    private let cache = CacheManager(defaultTTL: CacheTTL.feed)
    private let deduplicator = RequestDeduplicator()

    func loadPosts() async throws -> [Post] {
        let cacheKey = "posts"

        // 先查缓存
        if let cached: [Post] = await cache.get(forKey: cacheKey) {
            return cached
        }

        // 网络请求（自动去重）
        return try await deduplicator.deduplicate(key: cacheKey) {
            let timer = PerformanceTimer(path: "/posts", method: .get)

            let posts = try await self.fetchFromNetwork()

            await self.cache.set(posts, forKey: cacheKey, ttl: 300)
            timer.stop(statusCode: 200)

            return posts
        }
    }
}
```

## 📊 核心组件详解

### CacheManager - 智能缓存管理器

**特性：**
- ✅ 支持 TTL（生存时间）自动过期
- ✅ Actor-based 线程安全（无需 NSLock）
- ✅ 泛型支持，类型安全
- ✅ 自动清理过期条目

**使用场景：**
```swift
let cache = CacheManager(defaultTTL: 300) // 默认 5 分钟

// 存储数据（使用默认 TTL）
await cache.set(posts, forKey: "feed")

// 存储数据（自定义 TTL）
await cache.set(userProfile, forKey: "user_123", ttl: 1800) // 30 分钟

// 读取数据
if let posts: [Post] = await cache.get(forKey: "feed") {
    // 缓存命中
}

// 手动清理过期条目
await cache.cleanup()
```

**预设 TTL：**
```swift
CacheTTL.feed          // 5 分钟
CacheTTL.exploreFeed   // 10 分钟
CacheTTL.userProfile   // 30 分钟
CacheTTL.notifications // 1 分钟
CacheTTL.image         // 24 小时
```

---

### RequestDeduplicator - 请求去重器

**问题场景：**
用户快速点击"刷新"按钮 5 次，导致发起 5 个相同的网络请求。

**解决方案：**
RequestDeduplicator 会识别相同请求，只执行一次，其他 4 次复用结果。

**使用示例：**
```swift
let deduplicator = RequestDeduplicator()

// 并发发起 5 个相同请求
let results = try await withThrowingTaskGroup(of: [Post].self) { group in
    for _ in 0..<5 {
        group.addTask {
            try await deduplicator.deduplicate(key: "load_feed") {
                try await self.loadFeedFromNetwork()
            }
        }
    }

    var results: [[Post]] = []
    for try await result in group {
        results.append(result)
    }
    return results
}

// 结果：只发起 1 次网络请求，5 个调用者都得到结果
```

**去重键生成：**
```swift
// 自动生成去重键
let endpoint = APIEndpoint(path: "/feed", method: .get, queryItems: [...])
let key = endpoint.deduplicationKey

// 或手动生成
let key = DeduplicationKey.generate(
    path: "/posts",
    method: .get,
    queryItems: [URLQueryItem(name: "page", value: "1")]
)
```

---

### NetworkMonitor - 网络状态监听

**功能：**
- ✅ 实时监听网络连接状态（WiFi/蜂窝/有线）
- ✅ 网络恢复时自动重试
- ✅ 离线优雅降级

**使用示例：**
```swift
let monitor = NetworkMonitor.shared

// 监听网络状态变化
monitor.onConnectionChanged = { isConnected, connectionType in
    if isConnected {
        print("✅ 网络恢复: \(connectionType)")
        // 重试待处理的请求
    } else {
        print("❌ 网络断开")
        // 显示离线提示
    }
}

// 检查当前状态
if monitor.isConnected {
    print("当前网络: \(monitor.connectionType)")
}
```

**自动重试管理器：**
```swift
let retryManager = RetryManager()

func importantAPICall() async throws {
    guard NetworkMonitor.shared.isConnected else {
        // 添加到待重试队列
        await retryManager.addPendingRetry(key: "important_call") {
            try await importantAPICall()
        }
        throw NetworkError.offline
    }

    // 执行请求
}
```

---

### PerformanceMetrics - 性能指标收集

**收集指标：**
- ✅ 请求延迟（平均/最大/最小）
- ✅ 缓存命中率
- ✅ 数据传输量
- ✅ 慢请求检测

**使用示例：**
```swift
// 方式 1: 手动记录
let timer = PerformanceTimer(path: "/api/posts", method: .get)
// ... 执行请求 ...
timer.stop(statusCode: 200, bytesTransferred: 2048)

// 方式 2: 自动测量
let result = try await PerformanceTimer.measure(path: "/api/users") {
    try await fetchUsers()
}

// 查看统计
let stats = await PerformanceMetrics.shared.getStats()
print(stats.description)

// 查找慢请求
let slowRequests = await PerformanceMetrics.shared.getSlowRequests(threshold: 1.0)
```

---

### URLCacheConfig - 图片/资源缓存

**配置：**
- ✅ 内存缓存：50 MB
- ✅ 磁盘缓存：200 MB
- ✅ 自动缓存 HTTP 响应

**使用示例：**
```swift
// 1. 在 AppDelegate 初始化
URLCacheConfig.configure()

// 2. 创建带缓存策略的请求
let imageURL = URL(string: "https://example.com/image.jpg")!
let request = URLRequest.cachedRequest(url: imageURL, cachePolicy: .returnCacheElseLoad)

// 3. 发起请求（自动缓存）
let (data, _) = try await URLSession.shared.data(for: request)
let image = UIImage(data: data)

// 4. 查看缓存统计
let stats = URLCacheConfig.shared.getCacheStats()
print(stats.description)
```

**缓存策略：**
```swift
CachePolicy.default              // 使用默认策略
CachePolicy.reloadIgnoringCache  // 忽略缓存，总是加载
CachePolicy.returnCacheElseLoad  // 优先缓存，缓存不存在时加载
CachePolicy.onlyFromCache        // 仅使用缓存，不发起网络请求
```

---

## 🔍 性能调试工具

### PerformanceDebugView

**可用命令：**
```swift
#if DEBUG
// 打印性能统计
PerformanceDebugView.printStats()

// 打印慢请求
PerformanceDebugView.printSlowRequests(threshold: 1.0)

// 获取优化建议
PerformanceRecommendations.printRecommendations()

// 启用自动日志
PerformanceDebugView.startAutoLogging(interval: 30)

// 清除所有缓存
PerformanceDebugView.clearAllCaches()

// 重置统计
PerformanceDebugView.resetStats()
#endif
```

**LLDB 调试：**
```bash
(lldb) po PerformanceDebugView.printStats()
(lldb) po PerformanceDebugView.printSlowRequests()
```

---

## 📈 性能优化建议

### 1. 合理设置 TTL

```swift
// ❌ 错误：所有数据使用相同 TTL
await cache.set(data, forKey: key) // 使用默认 5 分钟

// ✅ 正确：根据数据特性设置 TTL
await cache.set(feed, forKey: "feed", ttl: CacheTTL.feed)           // 5 分钟
await cache.set(user, forKey: "user", ttl: CacheTTL.userProfile)    // 30 分钟
await cache.set(notifications, forKey: "notif", ttl: CacheTTL.notifications) // 1 分钟
```

### 2. 智能预加载

```swift
func loadPage(_ page: Int) async throws -> [Post] {
    let posts = try await fetchPage(page)

    // 后台预加载下一页（不阻塞）
    Task {
        try? await preloadPage(page + 1)
    }

    return posts
}
```

### 3. 缓存粒度控制

```swift
// ❌ 错误：缓存整个 Feed
await cache.set(allPosts, forKey: "feed")

// ✅ 正确：分页缓存
await cache.set(posts, forKey: "feed_page_\(page)")
```

### 4. 监控性能指标

```swift
// 定期检查性能
Task {
    let stats = await PerformanceMetrics.shared.getStats()

    if stats.cacheHitRate < 50 {
        Logger.log("⚠️ Cache hit rate is low", level: .warning)
    }

    if stats.averageDurationMs > 500 {
        Logger.log("⚠️ Average request time is high", level: .warning)
    }
}
```

---

## 🧪 测试

运行性能测试：
```bash
# 运行所有性能测试
xcodebuild test -scheme NovaSocial -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:PerformanceTests

# 运行特定测试
xcodebuild test -only-testing:PerformanceTests/testCacheManager_SetAndGet_Performance
```

**关键测试用例：**
- `testCacheManager_SetAndGet_Performance` - 缓存读写性能
- `testDeduplicator_PreventsDuplicateRequests` - 请求去重验证
- `testFeedRepository_CacheIntegration` - 集成测试
- `testBenchmark_CacheVsNoCachePerformance` - 缓存效果对比

---

## 📊 性能基准

**缓存性能：**
- 写入 1000 条缓存：< 1 秒
- 读取 1000 条缓存：< 1 秒
- TTL 过期检测：毫秒级

**去重效果：**
- 5 个并发相同请求 → 1 次实际网络调用
- 节省网络流量：80%+

**缓存命中率目标：**
- Feed 数据：> 70%
- 用户信息：> 80%
- 图片资源：> 90%

---

## ⚠️ 注意事项

### 1. 内存管理

```swift
// ❌ 不要缓存过大的数据
await cache.set(hugeBinaryData, forKey: "video") // 可能导致内存问题

// ✅ 大文件使用 URLCache 或磁盘缓存
let request = URLRequest.cachedRequest(url: videoURL)
```

### 2. 缓存失效

```swift
// 用户登出时清空缓存
func logout() async {
    await cache.clear()
    URLCacheConfig.shared.clearCache()
}

// 数据更新后失效缓存
func updatePost(postId: String) async {
    await cache.remove(forKey: "post_\(postId)")
    await cache.remove(forKey: CacheKey.feed(cursor: nil)) // 失效 Feed 缓存
}
```

### 3. 线程安全

```swift
// ✅ CacheManager 和 RequestDeduplicator 是 Actor，天然线程安全
let cache = CacheManager()
await cache.set(data, forKey: "key")

// ❌ 不要在多线程中直接访问 UserDefaults
// FeedCache（旧版）不是线程安全的，建议迁移到 CacheManager
```

---

## 🔄 迁移指南

### 从 FeedCache 迁移到 CacheManager

**之前：**
```swift
let cache = FeedCache()
cache.cacheFeed(posts)
let cachedPosts = cache.getCachedFeed()
```

**之后：**
```swift
let cache = CacheManager(defaultTTL: CacheTTL.feed)
await cache.set(posts, forKey: CacheKey.feed(cursor: nil))
let cachedPosts: [Post]? = await cache.get(forKey: CacheKey.feed(cursor: nil))
```

**优势：**
- ✅ 支持 TTL 自动过期
- ✅ Actor 线程安全
- ✅ 泛型类型安全
- ✅ 更灵活的缓存键

---

## 📚 参考资料

- [Apple URLCache 文档](https://developer.apple.com/documentation/foundation/urlcache)
- [Network Framework 文档](https://developer.apple.com/documentation/network)
- [Swift Concurrency 最佳实践](https://developer.apple.com/videos/play/wwdc2021/10254/)

---

## 🤝 贡献

发现性能问题或有优化建议？欢迎提交 Issue 或 Pull Request！
