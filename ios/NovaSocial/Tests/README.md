# iOS Unit Tests

## 目录结构

```
Tests/
├── UnitTests/
│   ├── Mocks/
│   │   ├── MockURLProtocol.swift   # 网络请求模拟
│   │   └── TestFixtures.swift       # 测试数据工厂
│   ├── Networking/
│   │   ├── APIClientTests.swift     # API 客户端测试
│   │   └── ErrorHandlingTests.swift # 错误处理测试
│   └── Services/
│       ├── AuthenticationManagerTests.swift  # 认证管理测试
│       └── IdentityServiceTests.swift        # 身份服务测试
└── StagingE2ETests.swift            # E2E 测试 (已有)
```

## 如何添加测试 Target 到 Xcode 项目

### 方法 1: 使用 Xcode UI (推荐)

1. 在 Xcode 中打开 `ICERED.xcodeproj`
2. 选择项目 → File → New → Target
3. 选择 "Unit Testing Bundle"
4. 命名为 `ICEREDTests`
5. Language: Swift
6. Host Application: ICERED
7. 点击 Finish

### 方法 2: 手动添加文件

创建 target 后，将以下文件添加到测试 target:

- `Tests/UnitTests/Mocks/MockURLProtocol.swift`
- `Tests/UnitTests/Mocks/TestFixtures.swift`
- `Tests/UnitTests/Networking/APIClientTests.swift`
- `Tests/UnitTests/Networking/ErrorHandlingTests.swift`
- `Tests/UnitTests/Services/AuthenticationManagerTests.swift`
- `Tests/UnitTests/Services/IdentityServiceTests.swift`

## 运行测试

### 命令行

```bash
# 运行所有测试
xcodebuild test \
  -project ICERED.xcodeproj \
  -scheme ICERED \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -enableCodeCoverage YES

# 运行特定测试类
xcodebuild test \
  -project ICERED.xcodeproj \
  -scheme ICERED \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:ICEREDTests/APIClientTests
```

### Xcode

1. `Cmd + U` 运行所有测试
2. 在测试导航器中点击特定测试

## 测试覆盖率

| 模块 | 测试文件 | 覆盖场景 |
|------|----------|----------|
| APIClient | APIClientTests.swift | GET/POST 请求、HTTP 错误码、网络错误、解码错误 |
| ErrorHandling | ErrorHandlingTests.swift | 错误映射、isRetryable、用户消息 |
| AuthenticationManager | AuthenticationManagerTests.swift | 登录/登出、访客模式、Token 刷新 |
| IdentityService | IdentityServiceTests.swift | 登录/注册、Token 刷新、用户资料 |

## Mock 基础设施

### MockURLProtocol

拦截所有网络请求，用于测试：

```swift
// 配置成功响应
MockURLProtocol.mockSuccess(statusCode: 200, data: jsonData)

// 配置 JSON 响应
try MockURLProtocol.mockJSON(myObject)

// 配置错误
MockURLProtocol.mockError(statusCode: 401)

// 配置网络超时
MockURLProtocol.mockTimeout()

// 配置无网络
MockURLProtocol.mockNoConnection()
```

### TestFixtures

测试数据工厂：

```swift
// 创建测试用户
let user = TestFixtures.makeUserProfile(
    id: "test_id",
    username: "testuser"
)

// 创建认证响应
let authResponse = TestFixtures.makeAuthResponse(
    token: "access_token",
    user: user
)
```

## 添加新测试

1. 在适当的目录创建新的测试文件
2. 导入 XCTest 和 `@testable import ICERED`
3. 创建继承 `XCTestCase` 的类
4. 在 `setUp()` 中初始化 `MockURLProtocol`
5. 在 `tearDown()` 中调用 `MockURLProtocol.reset()`

示例：

```swift
import XCTest
@testable import ICERED

final class MyNewTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        super.setUp()
        session = MockURLProtocol.createMockSession()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testMyFeature() async throws {
        // Given
        try MockURLProtocol.mockJSON(expectedResponse)

        // When
        let result = try await myService.doSomething()

        // Then
        XCTAssertEqual(result, expected)
    }
}
```
