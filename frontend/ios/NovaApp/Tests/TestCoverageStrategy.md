# Nova Instagram 测试覆盖策略

## 目标：80% 代码覆盖率

### 覆盖率优先级

#### 1. 关键路径（必须 100% 覆盖）
- 认证流程（登录、注册、登出）
- 支付相关功能
- 数据持久化和同步
- 安全敏感操作

#### 2. 核心业务逻辑（目标 90%+）
- ViewModels（FeedViewModel, ProfileViewModel, AuthService）
- Repositories（数据访问层）
- Services（业务服务层）
- State Management（状态管理）

#### 3. UI 组件（目标 70%+）
- 关键视图（FeedView, ProfileView, SignInView）
- 可复用组件（PostCardView, UserCardView）
- Design System 组件

#### 4. 工具类和扩展（目标 80%+）
- Extensions
- Utilities
- Helpers
- Formatters

## 测试金字塔分布

```
         ┌──────────┐
         │   E2E    │  10%
         │  Tests   │
      ┌──┴──────────┴──┐
      │  Integration    │  20%
      │     Tests       │
   ┌──┴─────────────────┴──┐
   │    Unit Tests          │  70%
   │  (ViewModels, Models,  │
   │  Services, Utilities)  │
   └────────────────────────┘
```

### 详细分布
- **单元测试（70%）**: 580+ tests
  - ViewModel tests: 250 tests
  - Service tests: 150 tests
  - Model tests: 80 tests
  - Utility tests: 100 tests

- **集成测试（20%）**: 170+ tests
  - Repository tests: 80 tests
  - API integration: 50 tests
  - Database integration: 40 tests

- **UI/E2E 测试（10%）**: 80+ tests
  - Snapshot tests: 50 tests
  - UI flow tests: 30 tests

**总计目标**: 830+ tests

## 测试类型分布

### 1. 单元测试（Unit Tests）

#### ViewModel 测试
```swift
// 覆盖场景
✅ 初始状态
✅ 成功路径（Happy path）
✅ 失败路径（Error handling）
✅ 边界条件（Edge cases）
✅ 并发操作（Concurrent operations）
✅ 状态转换（State transitions）
✅ 乐观更新和回滚（Optimistic updates & rollbacks）
```

**示例文件**:
- `FeedViewModelTests.swift` - Feed 功能测试
- `ProfileViewModelTests.swift` - Profile 功能测试
- `AuthServiceTests.swift` - 认证服务测试

#### Service 测试
```swift
// 覆盖场景
✅ API 调用成功
✅ API 调用失败（网络错误、服务器错误）
✅ Token 刷新
✅ 缓存机制
✅ 数据转换
```

#### Model 测试
```swift
// 覆盖场景
✅ Codable 编解码
✅ 数据验证
✅ 计算属性
✅ 初始化器
```

### 2. 集成测试（Integration Tests）

#### Repository 测试
```swift
// 覆盖场景
✅ API 客户端集成
✅ 数据持久化
✅ 缓存策略
✅ 错误处理和重试逻辑
```

**示例文件**:
- `FeedRepositoryIntegrationTests.swift`
- `AuthRepositoryIntegrationTests.swift`

#### Network 集成测试
```swift
// 覆盖场景
✅ 实际 API 调用（使用测试服务器）
✅ 超时处理
✅ 重试机制
✅ 离线场景
```

### 3. UI 测试（UI/Snapshot Tests）

#### Snapshot 测试
```swift
// 覆盖场景
✅ 不同状态（loading, empty, error, content）
✅ 明暗模式（light/dark mode）
✅ 不同设备尺寸（iPhone SE, 13 Pro, 13 Pro Max）
✅ 可访问性字体大小（Accessibility text sizes）
✅ 本地化（不同语言）
```

**示例文件**:
- `FeedViewSnapshotTests.swift`
- `ProfileViewSnapshotTests.swift`
- `AuthViewSnapshotTests.swift`

#### UI Flow 测试
```swift
// 覆盖场景
✅ 用户注册流程
✅ 登录登出流程
✅ 发布帖子流程
✅ 点赞评论流程
```

## 测试覆盖率配置

### Xcode 配置

1. **启用代码覆盖率收集**
   ```
   Scheme > Test > Options > Code Coverage
   ☑ Gather coverage for some targets
   - NovaApp
   - NovaAppCore
   ```

2. **设置覆盖率阈值**
   - 编辑 `.xcodeproj` 或使用 `xcodebuild` 参数
   - 设置最低覆盖率为 80%

3. **排除文件**
   ```
   排除的文件类型：
   - Generated code (*.generated.swift)
   - Third-party code
   - Test files
   - UI Preview files (*_Previews.swift)
   - AppDelegate.swift
   - SceneDelegate.swift
   ```

### CI/CD 集成

#### GitHub Actions 配置
```yaml
- name: Run tests with coverage
  run: |
    xcodebuild test \
      -scheme NovaApp \
      -destination 'platform=iOS Simulator,name=iPhone 13 Pro' \
      -enableCodeCoverage YES \
      -resultBundlePath TestResults

- name: Generate coverage report
  run: |
    xcrun xccov view --report --json TestResults.xcresult > coverage.json

- name: Check coverage threshold
  run: |
    coverage=$(jq '.lineCoverage' coverage.json)
    if (( $(echo "$coverage < 0.80" | bc -l) )); then
      echo "Coverage $coverage is below 80% threshold"
      exit 1
    fi

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v3
  with:
    files: coverage.json
```

## Mock 对象策略

### 1. Repository Mocks
所有 Repository 都应有对应的 Mock：
- `MockFeedRepository`
- `MockAuthRepository`
- `MockProfileRepository`
- `MockUploadRepository`

### 2. Service Mocks
关键服务的 Mock：
- `MockAPIClient`
- `MockKeychainManager`
- `MockImageCacheManager`
- `MockAnalyticsTracker`

### 3. Mock 设计原则
```swift
class MockRepository {
    // 1. Mock 数据
    var mockResult: Result?
    var mockError: Error?

    // 2. 调用跟踪
    var callCount = 0
    var lastParameters: Parameters?

    // 3. 延迟模拟（可选）
    var delayDuration: TimeInterval = 0

    // 4. 重置方法
    func reset() {
        mockResult = nil
        mockError = nil
        callCount = 0
        lastParameters = nil
    }
}
```

## 测试数据管理

### Test Data Factory
使用 `TestDataFactory` 创建一致的测试数据：
```swift
// ✅ Good - 使用 Factory
let user = TestDataFactory.createUser(username: "testuser")

// ❌ Bad - 手动创建
let user = User(id: "123", username: "testuser", ...)
```

### Mock Extensions
为模型添加 `mock()` 便捷方法：
```swift
let user = User.mock()
let post = Post.mock(likeCount: 100)
let posts = Post.mockList(count: 10)
```

## 性能测试

### 性能基准
```swift
func testFeedViewModel_LoadInitial_Performance() {
    measure {
        await viewModel.loadInitial()
    }
    // 预期: < 100ms
}

func testImageCache_LargeImageLoad_Performance() {
    measure {
        await imageCache.loadImage(url: largeImageURL)
    }
    // 预期: < 500ms
}
```

### 内存泄漏检测
```swift
func testFeedViewModel_NoMemoryLeak() {
    var sut: FeedViewModel? = FeedViewModel()

    addTeardownBlock { [weak sut] in
        XCTAssertNil(sut, "FeedViewModel should be deallocated")
    }

    sut = nil
}
```

## 测试命名规范

### 命名模式
```swift
// 模式: test[MethodName]_[Scenario]_[ExpectedBehavior]

// ✅ Good examples
func testLoadInitial_Success_UpdatesPosts()
func testToggleLike_WithNetworkError_RevertsOptimisticUpdate()
func testSignIn_InvalidCredentials_ThrowsAuthError()

// ❌ Bad examples
func testLoadData()
func testError()
func test1()
```

## 持续改进

### 每周审查
- 检查覆盖率报告
- 识别未覆盖的关键代码
- 优先补充高风险区域的测试

### 每月目标
- **Month 1**: 达到 60% 覆盖率
- **Month 2**: 达到 70% 覆盖率
- **Month 3**: 达到 80% 覆盖率并保持

### 覆盖率门禁
```
PR 合并要求：
- 新代码覆盖率 ≥ 80%
- 总体覆盖率不下降
- 所有测试通过
- 无内存泄漏
```

## 工具和依赖

### 测试框架
```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.12.0"),
    .package(url: "https://github.com/Quick/Nimble", from: "11.0.0")
]
```

### 覆盖率工具
- Xcode Code Coverage
- Codecov（CI 集成）
- Slather（生成 HTML 报告）

### 快照测试
- swift-snapshot-testing
- 支持 SwiftUI 和 UIKit
- 多设备配置

## 附录：快速检查清单

### 编写新功能时
- [ ] 编写单元测试（ViewModel + Service）
- [ ] 编写集成测试（Repository）
- [ ] 添加 UI 快照测试（关键视图）
- [ ] 测试错误场景
- [ ] 测试边界条件
- [ ] 检查内存泄漏
- [ ] 运行全部测试套件
- [ ] 验证覆盖率 ≥ 80%

### 修复 Bug 时
- [ ] 编写重现 bug 的测试（先失败）
- [ ] 修复代码
- [ ] 确认测试通过
- [ ] 添加相关边界情况测试
- [ ] 验证覆盖率未降低

---

**最后更新**: 2025-10-19
**负责人**: iOS Team
**审核周期**: 每周
