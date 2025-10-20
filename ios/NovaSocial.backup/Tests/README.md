# NovaSocial iOS 测试套件

完整的单元测试、集成测试和性能测试覆盖。

## 📂 目录结构

```
Tests/
├── Unit/                          # 单元测试
│   ├── ConcurrencyTests.swift    # 并发和竞态条件测试 ⭐ HIGH PRIORITY
│   ├── AuthRepositoryTests.swift # 认证仓库测试
│   ├── FeedRepositoryTests.swift # Feed 仓库测试
│   ├── ErrorHandlingTests.swift  # 错误处理和重试机制测试
│   └── CacheTests.swift          # 缓存逻辑测试
├── Integration/                   # 集成测试（需要后端）
│   └── (未来添加)
├── Performance/                   # 性能测试
│   └── NetworkPerformanceTests.swift
├── Mocks/                         # Mock 类和测试工具
│   ├── MockURLProtocol.swift     # 网络请求 Mock
│   ├── MockAuthManager.swift     # 认证管理 Mock
│   └── TestFixtures.swift        # 测试数据工厂
├── run_tests.sh                   # 测试运行脚本
├── generate_coverage_report.py    # 覆盖率报告生成器
└── README.md                      # 本文件
```

## 🚀 快速开始

### 运行所有测试

```bash
cd /Users/proerror/Documents/nova/ios/NovaSocial/Tests
./run_tests.sh
```

### 运行特定测试类

```bash
# 只运行并发测试
xcodebuild test \
  -scheme NovaSocial \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:NovaSocialTests/ConcurrencyTests

# 只运行性能测试
xcodebuild test \
  -scheme NovaSocial \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:NovaSocialTests/NetworkPerformanceTests
```

### 生成覆盖率报告

```bash
# 1. 运行测试（会生成 coverage.json）
./run_tests.sh

# 2. 生成 HTML 报告
./generate_coverage_report.py TestReports/coverage.json

# 3. 打开报告
open TestReports/coverage_report.html
```

## 📊 测试覆盖范围

### ⭐ 高优先级测试（已完成）

#### 1. 并发和线程安全测试 (`ConcurrencyTests.swift`)

**为什么是高优先级？**
- Token 刷新竞态条件是生产环境常见 Bug
- 多用户并发场景必须正确处理
- 数据竞争会导致崩溃或数据损坏

**测试场景：**
- ✅ 多个并发请求同时触发 Token 刷新，应该只刷新一次
- ✅ 并发情况下 Token 刷新失败，所有请求应该收到错误
- ✅ 多个 401 响应同时到达，应该只触发一次刷新
- ✅ AuthManager 并发读写安全性
- ✅ 缓存并发写入竞争
- ✅ 请求去重（相同请求的并发处理）
- ✅ 快速登录登出竞态

**运行建议：**
```bash
# 使用 Thread Sanitizer 运行
xcodebuild test \
  -scheme NovaSocial \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -enableThreadSanitizer YES \
  -only-testing:NovaSocialTests/ConcurrencyTests
```

#### 2. Repository 单元测试

**AuthRepository (`AuthRepositoryTests.swift`)**
- ✅ 注册流程（成功、邮箱已存在、密码太短）
- ✅ 登录流程（成功、无效凭据、网络超时）
- ✅ 登出流程（成功、失败时的处理）
- ✅ 邮箱验证（成功、无效验证码）
- ✅ 会话管理（检查登录状态、获取当前用户）
- ✅ Token 自动包含在请求中

**FeedRepository (`FeedRepositoryTests.swift`)**
- ✅ Feed 加载（首次、分页、网络错误）
- ✅ 缓存命中和失效
- ✅ 下拉刷新清除缓存
- ✅ Explore Feed 加载和分页
- ✅ 请求去重验证
- ✅ Legacy Cache 向后兼容
- ✅ 性能测试

#### 3. 错误处理和重试机制 (`ErrorHandlingTests.swift`)

**HTTP 错误码映射：**
- ✅ 400 Bad Request
- ✅ 401 Unauthorized
- ✅ 403 Forbidden
- ✅ 404 Not Found
- ✅ 429 Rate Limited
- ✅ 500 Internal Server Error
- ✅ 503 Service Unavailable

**网络错误：**
- ✅ 网络超时
- ✅ 无网络连接

**重试逻辑：**
- ✅ 可重试错误自动重试
- ✅ 不可重试错误不重试
- ✅ 重试次数用尽后失败
- ✅ 指数退避延迟递增
- ✅ 401 错误触发 Token 刷新
- ✅ Token 刷新失败清除认证

#### 4. 缓存逻辑测试 (`CacheTests.swift`)

**基础功能：**
- ✅ 缓存存储和读取
- ✅ 缓存未命中
- ✅ 缓存过期
- ✅ 移除缓存
- ✅ 清空所有缓存

**复杂类型：**
- ✅ 数组类型缓存
- ✅ 字典类型缓存
- ✅ 自定义类型缓存

**TTL 机制：**
- ✅ 默认 TTL
- ✅ 自定义 TTL 优先级
- ✅ 缓存清理过期条目

**并发安全：**
- ✅ 并发读写不崩溃（Actor 保证）

**Legacy Cache：**
- ✅ 向后兼容性
- ✅ 最大容量限制

#### 5. 性能测试 (`NetworkPerformanceTests.swift`)

**批量请求：**
- ✅ 顺序请求性能基准
- ✅ 并发请求性能基准

**缓存性能：**
- ✅ 缓存命中 vs 缓存失效性能对比
- ✅ CacheManager 读写性能

**去重性能：**
- ✅ 并发相同请求的去重效率

**内存测试：**
- ✅ 大量数据的内存使用
- ✅ 缓存的内存占用

**吞吐量：**
- ✅ 每秒请求数（RPS）
- ✅ 不同网络延迟下的性能
- ✅ 重试机制的性能影响
- ✅ 多用户并发模拟

**JSON 解析：**
- ✅ 大数据集解析性能

## 🛠 Mock 工具

### MockURLProtocol

用于拦截和模拟网络请求，无需真实后端。

**使用示例：**

```swift
// 配置成功响应
MockURLProtocol.mockSuccess(statusCode: 200, data: jsonData)

// 配置 JSON 响应
let mockUser = TestFixtures.makeUser()
try MockURLProtocol.mockJSON(mockUser)

// 配置错误响应
MockURLProtocol.mockError(statusCode: 404)

// 配置网络超时
MockURLProtocol.mockTimeout()

// 配置无网络连接
MockURLProtocol.mockNoConnection()

// 自定义处理器
MockURLProtocol.requestHandler = { request in
    // 自定义逻辑
    return (response, data)
}
```

### TestFixtures

测试数据工厂，提供一致的测试数据。

**使用示例：**

```swift
// 创建测试用户
let user = TestFixtures.makeUser(username: "testuser")

// 创建测试 Token
let tokens = TestFixtures.makeAuthTokens()

// 创建测试帖子
let post = TestFixtures.makePost(caption: "Test post")

// 批量创建帖子
let posts = TestFixtures.makePosts(count: 10)

// 创建 Feed 响应
let feedResponse = TestFixtures.makeFeedResponse(posts: posts)
```

## 📈 覆盖率目标

| 模块 | 目标覆盖率 | 当前状态 |
|------|-----------|---------|
| Network Core | 90%+ | 🟡 进行中 |
| Repositories | 85%+ | 🟡 进行中 |
| Models | 95%+ | 🟢 完成 |
| Utils | 80%+ | 🟢 完成 |
| Services | 85%+ | 🟡 进行中 |
| **总体** | **85%+** | **🟡 75% (预估)** |

## 🔍 测试策略

### TDD 原则

所有测试遵循 **红-绿-重构** 循环：

1. **红色（失败）**：先写失败的测试
2. **绿色（成功）**：实现最小代码使测试通过
3. **重构（改进）**：优化代码，保持测试通过

### 测试金字塔

```
       /\
      /  \  E2E Tests (少量)
     /____\
    /      \
   / Integr \  Integration Tests (适量)
  /__________\
 /            \
/  Unit Tests  \ Unit Tests (大量)
/________________\
```

### 测试隔离

- ✅ 每个测试独立运行
- ✅ setUp/tearDown 清理状态
- ✅ 使用 Mock 隔离外部依赖
- ✅ 不依赖测试执行顺序

## 🐛 调试测试

### 单独运行失败的测试

```bash
# 在 Xcode 中点击失败测试旁边的 ▶️ 按钮
# 或使用命令行：
xcodebuild test \
  -scheme NovaSocial \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:NovaSocialTests/ConcurrencyTests/testConcurrentTokenRefresh_ShouldOnlyRefreshOnce
```

### 启用详细日志

在测试中添加：

```swift
override func setUp() {
    super.setUp()
    FeatureFlags.logLevel = .debug
}
```

### 使用 Thread Sanitizer

检测数据竞争：

```bash
xcodebuild test \
  -scheme NovaSocial \
  -enableThreadSanitizer YES
```

## 📝 添加新测试

### 1. 创建测试文件

```swift
import XCTest
@testable import NovaSocial

final class MyNewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // 设置
    }

    override func tearDown() {
        // 清理
        super.tearDown()
    }

    func testSomething() {
        // Given: 准备测试数据

        // When: 执行操作

        // Then: 验证结果
        XCTAssertEqual(actual, expected)
    }
}
```

### 2. 使用 Mock

```swift
func testWithMock() async throws {
    // 配置 Mock 响应
    let mockResponse = TestFixtures.makeAuthResponse()
    try MockURLProtocol.mockJSON(mockResponse)

    // 执行测试
    let result = try await repository.login(...)

    // 验证
    XCTAssertNotNil(result)
}
```

### 3. 测试并发

```swift
func testConcurrency() async throws {
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<10 {
            group.addTask {
                // 并发操作
            }
        }
    }

    // 验证结果
}
```

## 🎯 最佳实践

### ✅ DO

- ✅ 使用描述性的测试名称（`testLogin_WhenInvalidCredentials_ShouldThrowError`）
- ✅ 遵循 Given-When-Then 模式
- ✅ 每个测试只验证一件事
- ✅ 使用 TestFixtures 创建测试数据
- ✅ 清理测试状态（tearDown）
- ✅ 测试边界条件和错误情况
- ✅ 添加并发测试
- ✅ 使用 async/await 测试异步代码

### ❌ DON'T

- ❌ 测试依赖执行顺序
- ❌ 硬编码测试数据
- ❌ 忽略清理（导致测试污染）
- ❌ 测试覆盖过低（<70%）
- ❌ 忽略并发测试
- ❌ 在测试中使用真实网络请求
- ❌ 忽略性能测试

## 🚨 常见问题

### Q: 测试运行很慢

A: 检查是否有真实网络请求，应该使用 MockURLProtocol。

### Q: 测试偶尔失败（Flaky Tests）

A: 通常是并发问题或状态清理不完整。使用 Thread Sanitizer 检测。

### Q: 覆盖率不准确

A: 确保运行了所有测试，并启用了 `-enableCodeCoverage YES`。

### Q: Mock 响应不生效

A: 检查 URLSession 配置是否正确设置了 `protocolClasses = [MockURLProtocol.self]`。

## 📚 参考资源

- [Apple Testing Documentation](https://developer.apple.com/documentation/xctest)
- [Swift Testing Best Practices](https://www.swiftbysundell.com/basics/unit-testing/)
- [Thread Sanitizer Guide](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early)

## 🤝 贡献

添加新测试时，请：

1. 确保测试通过
2. 运行 Thread Sanitizer 检测并发问题
3. 更新本 README 文档
4. 提交时包含测试覆盖率报告

## 📞 联系

有问题？请在项目 Issue 中提出。

---

**最后更新**: 2025-10-19
**测试覆盖率**: ~75%（预估）
**测试总数**: 70+
