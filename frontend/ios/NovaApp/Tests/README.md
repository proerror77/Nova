# NovaInstagram iOS 测试套件

完整的测试框架，包括单元测试、集成测试和 UI 快照测试，目标代码覆盖率 80%。

## 目录结构

```
Tests/
├── Unit/                          # 单元测试 (70%)
│   ├── ViewModels/                # ViewModel 测试
│   │   ├── FeedViewModelTests.swift
│   │   ├── ProfileViewModelTests.swift
│   │   └── AuthServiceTests.swift
│   ├── Models/                    # Model 测试
│   │   ├── PostModelTests.swift
│   │   └── UserModelTests.swift
│   ├── Services/                  # Service 测试
│   │   └── AuthServiceTests.swift
│   ├── Mocks/                     # Mock 对象
│   │   ├── MockFeedRepository.swift
│   │   ├── MockAuthRepository.swift
│   │   ├── MockProfileRepository.swift
│   │   └── MockAPIClient.swift
│   └── Helpers/                   # 测试工具
│       └── TestHelpers.swift
├── Integration/                   # 集成测试 (20%)
│   ├── FeedRepositoryIntegrationTests.swift
│   └── AuthRepositoryIntegrationTests.swift
├── UI/                            # UI 测试 (10%)
│   └── SnapshotTests/
│       ├── FeedViewSnapshotTests.swift
│       ├── ProfileViewSnapshotTests.swift
│       └── AuthViewSnapshotTests.swift
├── TestConfiguration.swift        # 测试配置
├── TestCoverageStrategy.md        # 覆盖率策略文档
└── README.md                      # 本文件
```

## 快速开始

### 运行所有测试

```bash
# 命令行
xcodebuild test \
  -scheme NovaApp \
  -destination 'platform=iOS Simulator,name=iPhone 13 Pro' \
  -enableCodeCoverage YES

# 或使用 Xcode
⌘ + U
```

### 运行特定测试套件

```bash
# 只运行单元测试
xcodebuild test \
  -scheme NovaApp \
  -only-testing:NovaAppTests/FeedViewModelTests

# 只运行集成测试
xcodebuild test \
  -scheme NovaApp \
  -only-testing:NovaAppTests/FeedRepositoryIntegrationTests

# 只运行快照测试
xcodebuild test \
  -scheme NovaApp \
  -only-testing:NovaAppTests/FeedViewSnapshotTests
```

### 生成覆盖率报告

```bash
# 使用 xcodebuild
xcodebuild test \
  -scheme NovaApp \
  -destination 'platform=iOS Simulator,name=iPhone 13 Pro' \
  -enableCodeCoverage YES \
  -resultBundlePath TestResults.xcresult

# 查看覆盖率
xcrun xccov view --report TestResults.xcresult

# 生成 JSON 格式
xcrun xccov view --report --json TestResults.xcresult > coverage.json
```

## 测试类型

### 1. 单元测试（Unit Tests）

测试独立组件的行为，使用 Mock 对象隔离依赖。

**示例：FeedViewModel 测试**
```swift
func testLoadInitial_Success() async {
    // Given - 准备测试数据
    let mockPosts = Post.mockList(count: 5)
    mockRepository.mockFeedResult = FeedResult(posts: mockPosts, hasMore: true)

    // When - 执行操作
    await sut.loadInitial()

    // Then - 验证结果
    XCTAssertEqual(sut.posts.count, 5)
    XCTAssertFalse(sut.isLoading)
    XCTAssertNil(sut.error)
}
```

**覆盖场景：**
- ✅ 成功路径（Happy Path）
- ✅ 失败路径（Error Handling）
- ✅ 边界条件（Edge Cases）
- ✅ 乐观更新和回滚（Optimistic Updates）
- ✅ 并发操作（Concurrency）

### 2. 集成测试（Integration Tests）

测试多个组件的集成，验证它们协同工作。

**示例：Repository 集成测试**
```swift
func testFetchFeed_Success() async throws {
    // Given
    let mockResponse = FeedAPIResponse(posts: [...], pagination: ...)
    mockAPIClient.mockResponse = mockResponse

    // When
    let result = try await sut.fetchFeed(page: 0, limit: 20)

    // Then
    XCTAssertEqual(result.posts.count, 2)
    XCTAssertEqual(mockAPIClient.lastEndpoint?.path, "/feed")
}
```

**覆盖场景：**
- ✅ API 集成
- ✅ 缓存机制
- ✅ 重试逻辑
- ✅ 错误传播

### 3. UI 快照测试（Snapshot Tests）

捕获 UI 的视觉快照，防止意外的 UI 变化。

**示例：Feed 视图快照**
```swift
func testFeedView_WithPosts() {
    // Given
    mockViewModel.posts = Post.mockList(count: 3)

    // When
    let view = FeedView(viewModel: mockViewModel)
        .environment(\.colorScheme, .light)

    // Then
    assertSnapshot(matching: view, as: .image(layout: .device(config: .iPhone13Pro)))
}
```

**覆盖场景：**
- ✅ 不同状态（Empty, Loading, Error, Content）
- ✅ 明暗模式（Light/Dark Mode）
- ✅ 设备尺寸（iPhone SE, 13 Pro, 13 Pro Max）
- ✅ 可访问性（Accessibility Text Sizes）

## Mock 对象

### 核心 Mock 类

#### MockFeedRepository
```swift
let mockRepository = MockFeedRepository()
mockRepository.mockFeedResult = FeedResult(posts: posts, hasMore: true)
mockRepository.mockError = APIError.mock()
```

**特性：**
- 调用计数追踪
- 参数记录
- 可配置延迟
- 错误模拟

#### MockAPIClient
```swift
let mockClient = MockAPIClient()
mockClient.mockResponse = feedResponse
mockClient.requestDelay = 0.5
```

**特性：**
- 请求追踪
- 重试模拟
- 延迟模拟
- 响应验证

#### MockAuthRepository
```swift
let mockAuth = MockAuthRepository()
mockAuth.mockAuthResult = AuthResult(user: user, accessToken: "token")
```

### 测试数据工厂

使用 `TestDataFactory` 创建一致的测试数据：

```swift
// 创建单个对象
let user = TestDataFactory.createUser(username: "testuser")
let post = TestDataFactory.createPost(likeCount: 100)

// 创建列表
let users = TestDataFactory.createUserList(count: 10)
let posts = TestDataFactory.createPostList(count: 5)

// 使用便捷方法
let user = User.mock()
let posts = Post.mockList(count: 10)
```

## 测试工具

### 异步测试工具

```swift
// 等待条件
try await AsyncTestUtility.wait(timeout: 1.0) {
    viewModel.isLoading == false
}

// 测量执行时间
let duration = try await PerformanceTestHelper.measureAsync {
    await viewModel.loadInitial()
}

// 断言完成时间
try await PerformanceTestHelper.assertCompletes(within: 0.5) {
    await viewModel.loadInitial()
}
```

### 自定义断言

```swift
// 验证数组内容（忽略顺序）
assertArraysEqualIgnoringOrder(actual, expected)

// 验证数值范围
assertInRange(value, min: 0, max: 100)

// 验证异步错误
await assertThrowsError(
    try await service.signIn(email: "", password: ""),
    expectedError: AuthError.invalidCredential
)
```

### 内存泄漏检测

```swift
func testViewModel_NoMemoryLeak() {
    var sut: FeedViewModel? = FeedViewModel()

    LeakDetector.trackForMemoryLeaks(sut)

    sut = nil
    // 测试结束时自动验证对象已释放
}
```

## 覆盖率目标

### 总体目标：80%

| 组件类型 | 目标覆盖率 | 优先级 |
|---------|-----------|-------|
| ViewModels | 90%+ | 🔴 最高 |
| Services | 90%+ | 🔴 最高 |
| Repositories | 85%+ | 🟠 高 |
| Models | 80%+ | 🟡 中 |
| Views | 70%+ | 🟡 中 |
| Utilities | 80%+ | 🟡 中 |

### 当前覆盖率

```bash
# 查看当前覆盖率
xcrun xccov view --report TestResults.xcresult

# 按文件查看
xcrun xccov view --report --files-for-target NovaApp.app TestResults.xcresult
```

### 覆盖率趋势

建议每周检查覆盖率趋势：

```bash
# 生成覆盖率历史报告
./scripts/coverage-trend.sh
```

## 最佳实践

### 1. 测试命名

使用清晰的命名模式：

```swift
// ✅ Good
func testLoadInitial_Success_UpdatesPosts()
func testToggleLike_NetworkError_RevertsOptimisticUpdate()
func testSignIn_InvalidCredentials_ThrowsAuthError()

// ❌ Bad
func testLoad()
func testError()
func test1()
```

### 2. Given-When-Then 模式

```swift
func testExample() async {
    // Given - 准备测试条件
    let mockData = Post.mockList(count: 5)
    mockRepository.mockFeedResult = FeedResult(posts: mockData, hasMore: true)

    // When - 执行被测试的操作
    await sut.loadInitial()

    // Then - 验证结果
    XCTAssertEqual(sut.posts.count, 5)
    XCTAssertFalse(sut.isLoading)
}
```

### 3. 测试独立性

每个测试应该独立运行：

```swift
override func setUp() {
    super.setUp()
    // 为每个测试创建新的实例
    mockRepository = MockFeedRepository()
    sut = FeedViewModel(repository: mockRepository)
}

override func tearDown() {
    // 清理
    sut = nil
    mockRepository = nil
    super.tearDown()
}
```

### 4. 测试边界条件

```swift
// 空数据
func testLoadInitial_EmptyFeed()

// 大量数据
func testLoadInitial_LargeFeed()

// 并发操作
func testMultipleSimultaneousLoads()

// 边界值
func testPagination_LastPage()
```

### 5. 性能测试

```swift
func testLoadInitial_Performance() {
    measure {
        let expectation = XCTestExpectation(description: "Load complete")
        Task {
            await sut.loadInitial()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}
```

## CI/CD 集成

### GitHub Actions

测试自动在 PR 和 push 时运行：

```yaml
- name: Run tests
  run: |
    xcodebuild test \
      -scheme NovaApp \
      -destination 'platform=iOS Simulator,name=iPhone 13 Pro' \
      -enableCodeCoverage YES

- name: Upload coverage
  uses: codecov/codecov-action@v3
```

### 覆盖率门禁

PR 合并要求：
- ✅ 所有测试通过
- ✅ 新代码覆盖率 ≥ 80%
- ✅ 总体覆盖率不下降
- ✅ 无内存泄漏

## 依赖

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.12.0"),
    .package(url: "https://github.com/Quick/Nimble", from: "11.0.0")
]
```

### 安装快照测试

```bash
# 在 Xcode 中
File > Add Packages...
# 添加 https://github.com/pointfreeco/swift-snapshot-testing
```

## 故障排除

### 快照测试失败

```bash
# 重新录制快照（当 UI 有意变更时）
# 在测试中设置：
isRecording = true
```

### 测试超时

```swift
// 增加超时时间
wait(for: [expectation], timeout: 10.0)

// 或使用 async 版本
try await AsyncTestUtility.wait(timeout: 10.0) { condition }
```

### Mock 未被调用

```swift
// 检查 Mock 配置
XCTAssertEqual(mockRepository.fetchFeedCallCount, 1)
XCTAssertNotNil(mockRepository.lastFetchedPage)
```

## 贡献指南

### 添加新测试

1. 确定测试类型（Unit/Integration/UI）
2. 在对应目录创建测试文件
3. 遵循命名规范
4. 使用 Given-When-Then 模式
5. 添加必要的 Mock 对象
6. 运行并验证测试
7. 检查覆盖率

### 更新快照

```swift
// 1. 设置录制模式
isRecording = true

// 2. 运行测试
// 3. 查看生成的快照
// 4. 验证快照正确
// 5. 关闭录制模式
isRecording = false

// 6. 再次运行测试验证
```

## 参考资源

- [Swift Testing Best Practices](https://developer.apple.com/documentation/xctest)
- [Snapshot Testing Documentation](https://github.com/pointfreeco/swift-snapshot-testing)
- [Test Coverage Strategy](./TestCoverageStrategy.md)
- [Testing ViewModels in SwiftUI](https://www.swiftbysundell.com/articles/testing-swiftui-views/)

## 常见问题

### Q: 如何测试 @Published 属性的变化？

```swift
func testPublishedValueChange() async {
    let expectation = XCTestExpectation(description: "Value changed")

    let cancellable = sut.$posts.sink { posts in
        if !posts.isEmpty {
            expectation.fulfill()
        }
    }

    await sut.loadInitial()
    await fulfillment(of: [expectation], timeout: 1.0)
}
```

### Q: 如何测试 MainActor 代码？

```swift
@MainActor
func testMainActorCode() async {
    await sut.loadInitial()
    XCTAssertEqual(sut.posts.count, 5)
}
```

### Q: 如何避免测试依赖顺序？

每个测试都应该：
- 在 `setUp()` 中初始化
- 在 `tearDown()` 中清理
- 不依赖其他测试的状态

---

**维护者**: iOS Team
**最后更新**: 2025-10-19
**测试框架版本**: XCTest + swift-snapshot-testing 1.12.0
