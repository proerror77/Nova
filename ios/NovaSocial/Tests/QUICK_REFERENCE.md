# 测试快速参考

## 🚀 常用命令

### 运行所有测试
```bash
cd Tests && ./run_tests.sh
```

### 运行特定测试类
```bash
# 并发测试
xcodebuild test -scheme NovaSocial \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:NovaSocialTests/ConcurrencyTests

# 性能测试
xcodebuild test -scheme NovaSocial \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:NovaSocialTests/NetworkPerformanceTests
```

### Thread Sanitizer
```bash
xcodebuild test -scheme NovaSocial \
  -enableThreadSanitizer YES \
  -only-testing:NovaSocialTests/ConcurrencyTests
```

### 生成覆盖率报告
```bash
./run_tests.sh
./generate_coverage_report.py TestReports/coverage.json
open TestReports/coverage_report.html
```

## 📝 Mock 使用

### 配置 Mock 响应
```swift
// 成功响应
let mockUser = TestFixtures.makeUser()
try MockURLProtocol.mockJSON(mockUser)

// 错误响应
MockURLProtocol.mockError(statusCode: 404)

// 网络超时
MockURLProtocol.mockTimeout()

// 无网络
MockURLProtocol.mockNoConnection()

// 自定义处理
MockURLProtocol.requestHandler = { request in
    let response = TestFixtures.makeHTTPResponse()
    let data = try! TestFixtures.makeJSONData(mockData)
    return (response, data)
}
```

### 测试数据工厂
```swift
// 用户
let user = TestFixtures.makeUser(username: "test")

// Token
let tokens = TestFixtures.makeAuthTokens()

// 帖子
let post = TestFixtures.makePost()
let posts = TestFixtures.makePosts(count: 10)

// Feed 响应
let response = TestFixtures.makeFeedResponse(posts: posts)
```

## 🧪 测试模板

### 基础测试
```swift
func testSomething_WhenCondition_ShouldBehavior() async throws {
    // Given: 准备
    let mockData = TestFixtures.makeUser()
    try MockURLProtocol.mockJSON(mockData)

    // When: 执行
    let result = try await repository.someMethod()

    // Then: 验证
    XCTAssertEqual(result.property, expectedValue)
}
```

### 并发测试
```swift
func testConcurrency() async throws {
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<10 {
            group.addTask {
                _ = try? await self.repository.method()
            }
        }
    }
}
```

### 性能测试
```swift
func testPerformance() {
    measure {
        let exp = expectation(description: "test")
        Task {
            _ = try? await repository.method()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
    }
}
```

## 📊 测试文件

| 文件 | 测试内容 | 用例数 |
|------|---------|--------|
| `ConcurrencyTests.swift` | 并发和竞态 | 9 |
| `AuthRepositoryTests.swift` | 认证流程 | 13 |
| `FeedRepositoryTests.swift` | Feed 逻辑 | 12 |
| `ErrorHandlingTests.swift` | 错误处理 | 18 |
| `CacheTests.swift` | 缓存逻辑 | 18 |
| `NetworkPerformanceTests.swift` | 性能测试 | 14 |

## 🎯 覆盖率目标

- Network Core: **90%+**
- Repositories: **85%+**
- Models: **95%+**
- **总体: 85%+**

## 📚 文档

- 详细文档: `Tests/README.md`
- 测试总结: `TESTING_SUMMARY.md`
- 快速参考: 本文件
