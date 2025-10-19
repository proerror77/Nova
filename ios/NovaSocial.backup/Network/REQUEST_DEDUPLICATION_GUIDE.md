# 请求去重使用指南

## 概述

RequestDeduplicator 是一个轻量级的请求去重器,防止用户快速重复操作导致的并发请求风暴。

## 核心原理

```
用户快速点击"点赞" 10 次
    ↓
RequestDeduplicator 检查 key: "POST|/posts/{id}/like"
    ↓
第 1 次: 创建新的 Task 并执行 API 请求
第 2-10 次: 复用第 1 次的 Task,等待同一个结果
    ↓
所有 10 次调用返回相同的结果
    ↓
实际只发送了 1 次 API 请求
```

## 使用方法

### 1. 基本用法

```swift
// 在 Repository 中添加 deduplicator
final class PostRepository {
    private let deduplicator = RequestDeduplicator()

    func likePost(id: UUID) async throws -> (liked: Bool, likeCount: Int) {
        // 生成去重 key
        let key = RequestDeduplicator.likeKey(postId: id)

        // 执行去重请求
        return try await deduplicator.execute(key: key) {
            // 实际的 API 请求
            let endpoint = APIEndpoint(
                path: "/posts/\(id.uuidString)/like",
                method: .post
            )

            let response: LikeResponse = try await self.interceptor.executeWithRetry(endpoint)
            return (response.liked, response.likeCount)
        }
    }
}
```

### 2. 自定义 Key

```swift
// 场景1: 简单的 POST 请求
let key = "POST|/users/\(userId)/follow"

// 场景2: 包含请求体的去重
let key = "POST|/posts/\(postId)/comments|\(commentText)"

// 场景3: 包含查询参数
let key = RequestDeduplicator.makeKey(
    method: .get,
    path: "/users/search",
    queryItems: [
        URLQueryItem(name: "q", value: query),
        URLQueryItem(name: "limit", value: "20")
    ]
)
```

### 3. 内置便捷方法

```swift
// 点赞
RequestDeduplicator.likeKey(postId: id)
// → "POST|/posts/{id}/like"

// 取消点赞
RequestDeduplicator.unlikeKey(postId: id)
// → "DELETE|/posts/{id}/like"

// 关注
RequestDeduplicator.followKey(userId: id)
// → "POST|/users/{id}/follow"

// 取关
RequestDeduplicator.unfollowKey(userId: id)
// → "DELETE|/users/{id}/follow"

// 评论 (包含内容)
RequestDeduplicator.commentKey(postId: id, text: "Nice post!")
// → "POST|/posts/{id}/comments|Nice post!"
```

## 适用场景

### ✅ 应该使用去重的场景

1. **点赞/收藏** - 用户可能快速点击
2. **关注/取关** - 防止重复关注
3. **发表评论** - 防止重复提交相同评论
4. **投票/打分** - 防止重复投票
5. **加入购物车** - 防止重复添加

### ❌ 不应该使用去重的场景

1. **创建帖子** - 每次都是新内容
2. **上传图片** - 每次可能是不同图片
3. **搜索** - 用户可能想刷新结果
4. **获取列表** - 数据可能实时变化
5. **支付请求** - 需要幂等性令牌,不是去重

## 高级用法

### 1. 自定义去重策略

```swift
// 场景: 搜索去重 (0.5 秒内相同搜索词去重)
class SearchRepository {
    private let deduplicator = RequestDeduplicator()
    private var lastSearchTime: [String: Date] = [:]

    func search(query: String) async throws -> [User] {
        let now = Date()

        // 如果 0.5 秒内有相同搜索,使用去重
        if let lastTime = lastSearchTime[query],
           now.timeIntervalSince(lastTime) < 0.5 {
            let key = "SEARCH|\(query)"
            return try await deduplicator.execute(key: key) {
                try await self.performSearch(query: query)
            }
        }

        // 否则直接搜索
        lastSearchTime[query] = now
        return try await performSearch(query: query)
    }
}
```

### 2. 手动清理缓存

```swift
// 测试场景或重置场景
await deduplicator.clear()

// 检查活跃任务数 (调试用)
let count = await deduplicator.activeCount()
print("Active tasks: \(count)")
```

### 3. 与 UI 集成

```swift
// ViewModel 示例
@MainActor
class PostViewModel: ObservableObject {
    @Published var isLiked = false
    @Published var likeCount = 0
    @Published var isLoading = false

    private let repository = PostRepository()

    func toggleLike() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let (liked, count) = try await repository.likePost(id: post.id)

            // 去重确保了多次点击也只发一次请求
            // UI 状态更新也是正确的
            self.isLiked = liked
            self.likeCount = count
        } catch {
            // 错误处理
            print("Like failed: \(error)")
        }
    }
}
```

## 性能优势

### 请求数量对比

| 场景 | 无去重 | 有去重 | 节省 |
|------|--------|--------|------|
| 用户快速点击 10 次 | 10 请求 | 1 请求 | 90% |
| 100 个并发点赞 | 100 请求 | 1 请求 | 99% |
| 网络抖动时重试 | 5 请求 | 1 请求 | 80% |

### 内存开销

- **空闲时**: 0 字节
- **1 个活跃请求**: ~200 字节 (Task overhead)
- **100 个活跃请求**: ~20 KB
- **自动清理**: 请求完成后立即释放

## 线程安全

RequestDeduplicator 使用 `actor` 实现,完全线程安全:

```swift
actor RequestDeduplicator {
    // Actor 保证串行访问
    private var activeTasks: [String: Task<Any, Error>] = [:]

    // 所有方法自动在 actor 上下文执行
    func execute<T>(...) async throws -> T { ... }
}
```

**优势**:
- 无需手动加锁
- 无 race condition
- 编译器静态检查

## 常见问题

### Q1: 如何判断请求是否被去重了?

**A**: 添加日志:

```swift
func execute<T>(key: String, operation: @escaping () async throws -> T) async throws -> T {
    if let existingTask = activeTasks[key] {
        Logger.log("🔄 Reusing request: \(key)", level: .debug)
        return try await existingTask.value as! T
    }

    Logger.log("🆕 New request: \(key)", level: .debug)
    // ...
}
```

### Q2: 去重会影响错误处理吗?

**A**: 不会,所有调用者都会收到相同的错误:

```swift
// 第 1 个调用: 发送请求,失败
try await deduplicator.execute(key: key) {
    throw APIError.serverError
}
// → 抛出 APIError.serverError

// 第 2-10 个调用: 等待第 1 个,收到相同错误
try await deduplicator.execute(key: key) { ... }
// → 同样抛出 APIError.serverError
```

### Q3: 如何避免去重时间过长?

**A**: 使用不同的 key:

```swift
// 方案1: 添加时间戳(每秒不同)
let timestamp = Int(Date().timeIntervalSince1970)
let key = "POST|/posts/\(id)/like|\(timestamp)"

// 方案2: 只在短时间内去重
if Date().timeIntervalSince(lastRequestTime) > 2.0 {
    // 超过 2 秒,使用新 key
    let key = "POST|/posts/\(id)/like|\(UUID())"
}
```

### Q4: 可以用于下载大文件吗?

**A**: 可以,但需要注意:

```swift
// 下载去重
func downloadImage(url: URL) async throws -> UIImage {
    let key = "DOWNLOAD|\(url.absoluteString)"

    return try await deduplicator.execute(key: key) {
        // 实际下载
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw ImageError.invalidFormat
        }
        return image
    }
}

// 多个 ImageView 同时显示同一图片,只下载一次
```

## 最佳实践

### 1. Key 设计原则

```swift
// ✅ 好的 key: 简洁、唯一、可读
"POST|/posts/{id}/like"
"DELETE|/users/{id}/follow"

// ❌ 坏的 key: 过于复杂、包含无关信息
"POST|/posts/{id}/like|timestamp=123456|user=john|device=iPhone"
```

### 2. 去重粒度

```swift
// ✅ 细粒度: 每个资源单独去重
let key = RequestDeduplicator.likeKey(postId: id)

// ❌ 粗粒度: 所有点赞共享一个 key (错误!)
let key = "LIKE"  // 不同帖子的点赞会互相干扰
```

### 3. 与缓存结合

```swift
// 先检查缓存,再使用去重
func getPost(id: UUID) async throws -> Post {
    // 1. 缓存命中,直接返回
    if let cached = cache.get(id) {
        return cached
    }

    // 2. 缓存未命中,使用去重请求
    let key = "GET|/posts/\(id)"
    let post = try await deduplicator.execute(key: key) {
        let endpoint = APIEndpoint(path: "/posts/\(id)", method: .get)
        let response: PostResponse = try await interceptor.executeWithRetry(endpoint)
        return response.post
    }

    // 3. 存入缓存
    cache.set(id, post)
    return post
}
```

## 调试技巧

### 1. 开启详细日志

```swift
// 在 RequestDeduplicator.swift 中添加:
func execute<T>(key: String, operation: @escaping () async throws -> T) async throws -> T {
    let taskCount = activeTasks.count

    if let existingTask = activeTasks[key] {
        Logger.log("♻️ [Dedup] Reusing task for key: \(key) (active: \(taskCount))", level: .debug)
        return try await existingTask.value as! T
    }

    Logger.log("🆕 [Dedup] Creating new task for key: \(key) (active: \(taskCount))", level: .debug)

    let task = Task<Any, Error> {
        defer {
            Logger.log("✅ [Dedup] Task completed: \(key)", level: .debug)
            Task { await self.removeTask(for: key) }
        }
        return try await operation()
    }

    activeTasks[key] = task
    return try await task.value as! T
}
```

### 2. 性能监控

```swift
// 统计去重率
class DeduplicationMonitor {
    static var totalRequests = 0
    static var deduplicatedRequests = 0

    static var deduplicationRate: Double {
        guard totalRequests > 0 else { return 0 }
        return Double(deduplicatedRequests) / Double(totalRequests)
    }
}

// 在 execute 中:
DeduplicationMonitor.totalRequests += 1
if let existingTask = activeTasks[key] {
    DeduplicationMonitor.deduplicatedRequests += 1
    // ...
}
```

## 总结

RequestDeduplicator 通过简单的数据结构 (`[String: Task]`) 实现了强大的请求去重功能:

- ✅ **简单** - 只有 150 行代码
- ✅ **高效** - 节省 90%+ 的重复请求
- ✅ **安全** - Actor 保证线程安全
- ✅ **灵活** - 支持自定义 key 和策略

**Linus 的建议**: "好的工具应该是看不见的,你用了它,但你不需要记住它的存在。"
