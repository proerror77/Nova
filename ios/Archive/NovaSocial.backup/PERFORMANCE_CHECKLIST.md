# ✅ Performance Optimization Checklist

性能优化系统集成检查清单。完成所有步骤后，你的应用将拥有企业级性能优化能力。

---

## 📋 Step-by-Step Implementation

### ☑️ Phase 1: 基础配置（5 分钟）

- [ ] 在 `AppDelegate` 中添加 `PerformanceKit.configure()`
- [ ] 验证 URLCache 已配置（内存 50MB，磁盘 200MB）
- [ ] 确认 NetworkMonitor 已启动
- [ ] 运行应用，查看控制台日志确认初始化成功

**验证方法：**
```swift
// 应该看到以下日志
// ✅ URLCache configured (Memory: 50 MB, Disk: 200 MB)
// 📡 NetworkMonitor started
// ✅ PerformanceKit configured successfully
```

---

### ☑️ Phase 2: 更新 Repositories（30 分钟）

为每个 Repository 添加缓存和去重支持：

#### FeedRepository
- [ ] 添加 `CacheManager` 和 `RequestDeduplicator`
- [ ] 实现缓存检查逻辑
- [ ] 添加性能计时器
- [ ] 设置合理的 TTL（Feed: 5 分钟）

#### UserRepository
- [ ] 添加用户资料缓存（TTL: 30 分钟）
- [ ] 实现请求去重
- [ ] 添加性能监控

#### NotificationRepository
- [ ] 添加通知缓存（TTL: 1 分钟）
- [ ] 实现实时更新机制

#### PostRepository
- [ ] 添加帖子详情缓存
- [ ] 实现点赞/评论后的缓存失效

**验证方法：**
```swift
// 运行集成测试
xcodebuild test -only-testing:PerformanceTests/testFeedRepository_CacheIntegration
```

---

### ☑️ Phase 3: 图片加载优化（15 分钟）

- [ ] 创建 `ImageLoader` 类
- [ ] 使用 `URLRequest.cachedRequest()` 创建请求
- [ ] 设置 `returnCacheElseLoad` 缓存策略
- [ ] 集成到 SwiftUI `AsyncImage` 或自定义 Image View

**示例代码：**
```swift
final class ImageLoader: ObservableObject {
    @Published var image: UIImage?

    func load(url: URL) async {
        let request = URLRequest.cachedRequest(url: url, cachePolicy: .returnCacheElseLoad)
        let (data, _) = try? await URLSession.shared.data(for: request)
        self.image = data.flatMap { UIImage(data: $0) }
    }
}
```

---

### ☑️ Phase 4: 性能监控集成（20 分钟）

- [ ] 在所有网络请求中添加 `PerformanceTimer`
- [ ] 记录关键路径的性能指标
- [ ] 设置慢请求检测（阈值 1 秒）
- [ ] 在开发者设置中添加性能统计页面

**开发者设置示例：**
```swift
#if DEBUG
Section("Performance") {
    Button("Show Stats") {
        PerformanceDebugView.printStats()
    }

    Button("Show Slow Requests") {
        PerformanceDebugView.printSlowRequests()
    }

    Button("Clear Caches") {
        PerformanceDebugView.clearAllCaches()
    }
}
#endif
```

---

### ☑️ Phase 5: 网络状态处理（15 分钟）

- [ ] 监听网络状态变化
- [ ] 实现离线模式提示
- [ ] 添加网络恢复后的自动重试
- [ ] 测试飞行模式切换

**实现示例：**
```swift
final class AppViewModel: ObservableObject {
    @Published var isOffline = false

    init() {
        NetworkMonitor.shared.onConnectionChanged = { [weak self] isConnected, _ in
            DispatchQueue.main.async {
                self?.isOffline = !isConnected
            }
        }
    }
}
```

---

### ☑️ Phase 6: 智能预加载（20 分钟）

- [ ] 实现分页预加载逻辑
- [ ] 在用户滚动到底部前预加载下一页
- [ ] 避免重复预加载
- [ ] 测试预加载效果

**实现示例：**
```swift
func onAppear(of item: Post, in items: [Post]) {
    if let index = items.firstIndex(where: { $0.id == item.id }),
       index == items.count - 5 { // 距离底部 5 项时预加载
        Task {
            try? await loadNextPage()
        }
    }
}
```

---

### ☑️ Phase 7: 测试验证（30 分钟）

运行所有性能测试并验证结果：

- [ ] `testCacheManager_SetAndGet_Performance`
  - 预期：1000 条缓存读写 < 1 秒
- [ ] `testDeduplicator_PreventsDuplicateRequests`
  - 预期：5 个并发请求 → 1 次网络调用
- [ ] `testFeedRepository_CacheIntegration`
  - 预期：第二次加载使用缓存
- [ ] `testBenchmark_CacheVsNoCachePerformance`
  - 预期：带缓存版本至少快 5 倍

**运行测试：**
```bash
xcodebuild test -scheme NovaSocial -only-testing:PerformanceTests
```

---

### ☑️ Phase 8: 真机测试（20 分钟）

在真机上验证性能提升：

- [ ] 使用 Xcode Instruments 测试内存占用
- [ ] 验证网络流量减少
- [ ] 测试弱网环境下的表现
- [ ] 检查离线模式是否正常工作

**Instruments 检查项：**
- 内存峰值 < 200MB
- 缓存命中率 > 70%
- 网络流量减少 50%+

---

### ☑️ Phase 9: 性能基准记录（15 分钟）

记录优化前后的性能指标：

| 指标 | 优化前 | 优化后 | 提升 |
|-----|-------|-------|------|
| Feed 首次加载 | ___ ms | ___ ms | ___ % |
| Feed 二次加载 | ___ ms | ___ ms | ___ % |
| 缓存命中率 | 0% | ___ % | - |
| 网络请求次数 | ___ | ___ | ___ % |
| 内存占用 | ___ MB | ___ MB | ___ % |

- [ ] 填写优化前基准数据
- [ ] 填写优化后实际数据
- [ ] 计算提升百分比
- [ ] 记录到文档

---

### ☑️ Phase 10: 生产环境准备（10 分钟）

- [ ] 关闭 Debug 模式的性能日志
- [ ] 集成分析工具（可选：Firebase Performance）
- [ ] 设置性能监控告警
- [ ] 编写运维文档

**生产环境配置：**
```swift
#if !DEBUG
PerformanceKit.configure(enableDebug: false)
#else
PerformanceKit.configure(enableDebug: true)
#endif
```

---

## 🎯 验收标准

完成所有步骤后，应达到以下标准：

### 性能指标
- ✅ 缓存命中率 > 70%
- ✅ 平均响应时间 < 300ms
- ✅ 慢请求（> 1s）占比 < 5%
- ✅ 网络流量减少 > 50%
- ✅ 内存占用增加 < 20MB

### 代码质量
- ✅ 所有性能测试通过
- ✅ 无内存泄漏
- ✅ 无崩溃
- ✅ 代码覆盖率 > 80%

### 用户体验
- ✅ Feed 滚动流畅（60 FPS）
- ✅ 离线模式正常工作
- ✅ 网络切换无卡顿
- ✅ 图片加载快速

---

## 📊 性能报告模板

优化完成后，生成性能报告：

```swift
let report = await PerformanceKit.getPerformanceReport()
print(report.description)

// 保存到文件
try? report.description.write(
    to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("performance_report.txt"),
    atomically: true,
    encoding: .utf8
)
```

---

## 🔍 问题排查

如果遇到问题，参考此排查清单：

### 缓存不生效
- [ ] 检查 TTL 是否设置正确
- [ ] 验证缓存键是否一致
- [ ] 查看是否有缓存失效逻辑
- [ ] 检查内存是否充足

### 请求去重失败
- [ ] 验证去重键生成是否正确
- [ ] 检查是否使用了相同的 `RequestDeduplicator` 实例
- [ ] 查看日志确认去重逻辑执行

### 性能提升不明显
- [ ] 检查网络延迟是否过高
- [ ] 验证缓存命中率
- [ ] 查看是否有慢请求
- [ ] 检查是否有其他性能瓶颈

### 内存占用过高
- [ ] 调整缓存 TTL
- [ ] 减少缓存数据量
- [ ] 定期执行 `cache.cleanup()`
- [ ] 检查是否有内存泄漏

---

## 📚 参考资源

- 📖 完整文档：`Network/Services/README.md`
- 🚀 快速指南：`PERFORMANCE_SETUP_GUIDE.md`
- 💡 示例代码：`Examples/PerformanceOptimizationExamples.swift`
- 🧪 测试用例：`Tests/PerformanceTests.swift`

---

## ✨ 完成标志

当所有复选框都勾选完成，并且满足验收标准时，你可以自豪地说：

> "我们的 Nova iOS 应用已经拥有企业级性能优化能力！🚀"

---

**预计总耗时：** 约 3 小时

**优化效果：** Feed 加载速度提升 10 倍，网络流量减少 80%，缓存命中率 70%+

**下一步：** 持续监控性能指标，根据实际数据调优参数。
