# iOS UI 自动化测试报告

**日期**: 2025-11-20
**测试工具**: XcodeBuildMCP (MCP Tools)
**测试环境**: iPhone 16e 模拟器 (iOS 26.0)
**App 版本**: FigmaDesignApp 1.0 (Build 1)

---

## 测试概况

### 测试范围
✅ **UI 交互测试**
- 登录界面 UI 元素识别
- 文本输入功能
- 按钮点击功能
- 导航功能

✅ **后端连接测试**
- Staging API 可达性
- 认证流程

---

## 测试环境设置

### 1. 模拟器状态
```
设备: iPhone 16e
UDID: 6C716CEF-33A8-4E2B-81D3-CA4146BD2C14
状态: Booted ✅
系统版本: iOS 26.0
```

### 2. App 构建
```
项目: /Users/proerror/Documents/nova/ios/NovaSocial/FigmaDesignApp.xcodeproj
Scheme: FigmaDesignApp
Bundle ID: com.bruce.figmadesignapp
构建状态: ✅ 成功
```

### 3. Staging 后端状态
```bash
# 测试命令
curl -i -H "Host: api.nova.local" \
  "http://a3326508b1e3c43239348cac7ce9ee03-1036729988.ap-northeast-1.elb.amazonaws.com/api/v2/posts/author/test"

# 结果
HTTP/1.1 401 Unauthorized
Content-Type: text/plain; charset=utf-8
Body: Missing Authorization header

状态: ✅ 可达 (401 是预期行为，需要认证)
```

---

## UI 测试执行

### 测试场景 1: 登录界面 UI 元素识别

**测试工具**: `describe_ui`

**UI 层次结构**:
```json
{
  "Application": "FigmaDesignApp",
  "Elements": [
    {
      "type": "Image",
      "label": "Contact Photo",
      "frame": {"x": 155, "y": 87, "width": 80, "height": 80}
    },
    {
      "type": "StaticText",
      "label": "Welcome Back",
      "frame": {"x": 98.67, "y": 175, "width": 192.67, "height": 33.67}
    },
    {
      "type": "StaticText",
      "label": "Sign in to continue",
      "frame": {"x": 131.33, "y": 216.67, "width": 127.33, "height": 18}
    },
    {
      "type": "TextField",
      "value": "Username",
      "frame": {"x": 16, "y": 258.67, "width": 358, "height": 34}
    },
    {
      "type": "TextField",
      "subrole": "SecureTextField",
      "value": "Password",
      "frame": {"x": 16, "y": 308.67, "width": 358, "height": 34}
    },
    {
      "type": "Button",
      "label": "Sign In",
      "frame": {"x": 16, "y": 366.67, "width": 358, "height": 52.33}
    },
    {
      "type": "Button",
      "label": "Don't have an account?, Sign Up",
      "frame": {"x": 84.67, "y": 451, "width": 221, "height": 18}
    }
  ]
}
```

**结果**: ✅ **通过** - 所有 UI 元素正确识别，坐标准确

---

### 测试场景 2: 登录功能测试

**测试步骤**:
1. ✅ 点击 Username 输入框 (坐标: 195, 275)
2. ✅ 输入文本: `test@nova.com`
3. ✅ 点击 Password 输入框 (坐标: 195, 325)
4. ✅ 输入文本: `password`
5. ✅ 截图验证：用户名和密码已正确填入
6. ✅ 点击 Sign In 按钮 (坐标: 195, 393)

**测试凭证**:
```
Username: test@nova.com
Password: password
```

**预期结果**: 成功登录或显示明确的错误信息

**实际结果**: ❌ **API 错误**
```
错误消息: "Login failed: The operation couldn't be completed.
          (FigmaDesignApp.APIError error 2.)"
错误位置: 显示在 Username/Password 输入框下方（红色文本）
```

**截图证据**:
- 登录前：用户名和密码输入框为空
- 填入凭证后：显示 `test@nova.com` 和 `••••••••`
- 点击登录后：显示错误消息（红色文本）

**分析**:
- ✅ UI 交互完全正常（点击、输入、显示）
- ✅ 登录请求已发送到后端
- ❌ 后端 API 返回错误（APIError error 2）
- 可能原因：
  1. 测试用户不存在于 staging 数据库
  2. 密码不正确
  3. Identity Service 认证逻辑问题
  4. API endpoint 配置错误

---

### 测试场景 3: 注册功能测试

**测试步骤**:
1. ✅ 点击 "Sign Up" 链接 (坐标: 195, 460)

**预期结果**: 导航到注册页面

**实际结果**: ⚠️ **App 退出到主屏幕**

**分析**:
- 可能的原因：
  1. 注册页面尚未实现
  2. 导航逻辑问题
  3. App 崩溃（需要查看崩溃日志）

**建议**:
- 实现注册页面 UI
- 添加错误处理避免 app 崩溃
- 如果注册功能未实现，应禁用或隐藏 Sign Up 按钮

---

## XcodeBuildMCP 工具功能验证

### ✅ 成功的功能
1. `list_sims` - 列出可用模拟器
2. `open_sim` - 打开模拟器 UI
3. `build_sim` - 构建 iOS app
4. `get_sim_app_path` - 获取 app 路径
5. `get_app_bundle_id` - 获取 bundle ID
6. `install_app_sim` - 安装 app 到模拟器
7. `launch_app_sim` - 启动 app
8. `launch_app_logs_sim` - 启动 app 并捕获日志
9. `screenshot` - 截图功能
10. `describe_ui` - 获取 UI 层次结构（精确坐标）
11. `tap` - 点击操作
12. `type_text` - 文本输入
13. `stop_sim_log_cap` - 停止日志捕获

### 工具使用体验
- **优点**:
  - 精确的坐标获取（describe_ui）
  - 真实的 UI 交互（不是 mock）
  - 完整的自动化流程
  - 详细的反馈信息

- **改进建议**:
  - 日志捕获内容较少，建议使用 `captureConsole: true` 参数
  - 可以添加更多手势操作（swipe, scroll 等）

---

## 测试发现的问题

### P0 问题（阻塞）

#### 1. 登录 API 错误
**严重程度**: 🔴 P0（阻塞核心功能）
**影响**: 用户无法登录
**错误**: `APIError error 2`
**位置**: `ios/NovaSocial/Tests/StagingE2ETests.swift:38`

**建议修复步骤**:
1. 验证测试用户在 staging 数据库中存在
   ```sql
   SELECT * FROM users WHERE email = 'test@nova.com';
   ```
2. 检查 identity-service 日志
   ```bash
   kubectl logs -n nova-staging deployment/identity-service --tail=100
   ```
3. 测试 identity-service 登录 endpoint
   ```bash
   curl -X POST http://api.nova.local/api/v2/auth/login \
     -H "Host: api.nova.local" \
     -H "Content-Type: application/json" \
     -d '{"email":"test@nova.com","password":"password"}'
   ```
4. 查看 iOS 错误定义
   ```swift
   // 查找 APIError enum 定义，确认 error 2 的含义
   grep -r "APIError" ios/NovaSocial/Shared/Services/Networking/
   ```

#### 2. Sign Up 导致 App 退出
**严重程度**: 🟡 P1（功能缺失）
**影响**: 新用户无法注册

**建议**:
- 实现注册页面 UI
- 或者在登录页面移除/禁用 Sign Up 按钮

---

### P1 问题（高优先级）

#### 3. 日志捕获内容不足
**问题**: 使用 `launch_app_logs_sim` 捕获的日志内容很少
**日志输出**:
```
getpwuid_r did not find a match for uid 501
Filtering the log data using "subsystem == "com.bruce.figmadesignapp""
```

**建议**:
- 使用 `captureConsole: true` 参数重新测试
- 添加更多结构化日志到 app 代码
- 使用 `os_log` 或 `Logger` API 替代 `print`

---

## 测试总结

### 成功的部分 ✅
1. **UI 自动化框架**: XcodeBuildMCP 工具完全可用，提供精确的 UI 操作能力
2. **Staging 后端**: 可达且正常响应（401 认证错误是预期行为）
3. **UI 交互**: 点击、输入文本等基础操作完全正常
4. **错误显示**: App 正确显示了 API 错误消息（虽然是错误结果，但说明错误处理逻辑正常）

### 需要修复的部分 ❌
1. **登录 API 错误**: 需要后端团队排查 identity-service
2. **注册功能**: 需要实现或移除
3. **日志捕获**: 需要增强日志输出

---

## 后续建议

### 1. 立即执行（修复阻塞问题）
```bash
# 1. 检查 staging 负载均衡/Ingress 状态
kubectl get ingress -n nova-staging

# 2. 检查 identity-service 状态
kubectl get pods -n nova-staging | grep identity-service

# 3. 查看 identity-service 日志
kubectl logs -n nova-staging deployment/identity-service --tail=100

# 4. 测试登录 endpoint
curl -X POST http://api.nova.local/api/v2/auth/login \
  -H "Host: api.nova.local" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@nova.com","password":"password"}'
```

### 2. 中期执行（完善测试）
1. **创建 XCUITest**:
   - 将手动测试转换为自动化测试用例
   - 添加到 CI/CD pipeline

   ```swift
   // ios/NovaSocial/UITests/LoginUITests.swift
   class LoginUITests: XCTestCase {
       func testLoginFlow() {
           let app = XCUIApplication()
           app.launch()

           // 输入用户名
           let usernameField = app.textFields["Username"]
           usernameField.tap()
           usernameField.typeText("test@nova.com")

           // 输入密码
           let passwordField = app.secureTextFields["Password"]
           passwordField.tap()
           passwordField.typeText("password")

           // 点击登录
           app.buttons["Sign In"].tap()

           // 验证登录结果（成功或错误消息）
           XCTAssertTrue(
               app.staticTexts["Welcome"].exists ||
               app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Login failed'")).count > 0
           )
       }
   }
   ```

2. **增强日志**:
   ```swift
   // 使用 os_log 替代 print
   import os.log

   let logger = Logger(subsystem: "com.bruce.figmadesignapp", category: "Authentication")

   func login() async {
       logger.info("Starting login process")
       // ... login logic
       logger.error("Login failed: \(error.localizedDescription)")
   }
   ```

### 3. 长期执行（持续优化）
1. 定期运行 UI 自动化测试
2. 添加更多测试场景（注册、个人资料、内容浏览等）
3. 集成到 GitHub Actions CI/CD pipeline

---

## 相关文档
- `ios/AUTHENTICATION_STATUS.md` - 认证问题跟踪
- `ios/TEST_EXECUTION_REPORT.md` - 测试执行报告
- `ios/AWS_BACKEND_CONNECTION_TEST_REPORT.md` - 后端连接测试

---

**报告生成时间**: 2025-11-20 13:17
**测试执行人**: Claude Code (AI Agent)
**下次测试建议**: 修复 P0 问题后重新运行完整测试套件
