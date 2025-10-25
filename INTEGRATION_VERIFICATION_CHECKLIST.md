# 前端与iOS集成验证清单

**完成日期**: 2025-10-25
**验证时间**: ~30分钟
**难度**: ⭐⭐

---

## 🔍 前端验证 (15分钟)

### 1. 认证系统验证
```bash
# 进入前端目录
cd /Users/proerror/Documents/nova/frontend

# 安装依赖
npm install

# 启动开发服务器
npm run dev

# 在浏览器中:
# 1. 打开 DevTools → Application → Local Storage
# 2. 查看 auth:accessToken 和 auth:refreshToken 是否分离存储 ✅
# 3. 检查没有旧的 "auth:token" 键 ✅
```

**预期结果**:
```
✅ auth:accessToken: "eyJhbGc..."
✅ auth:refreshToken: "eyJhbGc..."
❌ (旧的) auth:token: 不应该存在
```

### 2. Like/Comment 功能验证
```bash
# 前提: 需要运行后端服务

# 1. Feed 加载成功
#    页面显示文章列表 ✅

# 2. 点赞功能
#    - 点击 Like 按钮
#    - 数字立即 +1 ✅
#    - 后端 API 调用成功 (DevTools → Network) ✅
#    - 刷新页面后点赞仍存在 ✅

# 3. 评论功能
#    - 点击 Comment 按钮
#    - 弹出输入框 ✅
#    - 输入评论后点击 OK
#    - 评论计数 +1 ✅
#    - 后端收到评论 ✅

# 4. 错误处理
#    - 禁用网络
#    - 点赞/评论
#    - UI 自动回滚 ✅
#    - 错误消息显示 ✅
#    - 重新启用网络，再试一次成功 ✅
```

**网络错误模拟**:
```javascript
// DevTools Console:
// 方法1: 禁用网络
// 按 Cmd+Shift+P, 输入 "Disable network"

// 方法2: 断点调试
// 打开 DevTools → Network → 右键 → Offline
```

### 3. 代码检查
```bash
# 检查文件修改
git diff --name-only HEAD~1

# 应该包含:
# - frontend/src/context/AuthContext.tsx ✅
# - frontend/src/services/api/postService.ts ✅
# - frontend/src/components/Feed/FeedView.tsx ✅

# 检查没有 console 错误
# DevTools → Console → 应该没有红色错误 ✅
```

---

## 🔍 iOS 验证 (15分钟)

### 1. 硬编码IP修复验证

#### 方法1: 默认值 (推荐开发用)
```bash
# 启动 iOS 模拟器
open -a Simulator

# 选择 iPhone 16 模拟器
# 打开 Xcode 项目
open /Users/proerror/Documents/nova/ios/NovaSocialApp/NovaSocialApp.xcodeproj

# 构建运行
Cmd+R

# 检查: 应该连接到 localhost:8080
# 在 Xcode Console 查看:
# ✅ 应该看到 "Connected to http://localhost:8080"
# ❌ 不应该看到 "192.168.31.154"
```

#### 方法2: 环境变量 (CI/CD 用)
```bash
# 设置环境变量
export API_BASE_URL=http://192.168.1.100:8080
export WS_BASE_URL=ws://192.168.1.100:8085

# 运行 Xcode
xcodebuild \
  -scheme NovaSocialApp \
  -destination generic/platform=iOS Simulator \
  -verbose

# 验证: 应该使用环境变量中的 URL ✅
```

#### 方法3: Info.plist (生产用)
```xml
<!-- NovaSocialApp/Info.plist -->
<dict>
    <key>API_BASE_URL</key>
    <string>https://api-prod.nova.social</string>
    <key>WS_BASE_URL</key>
    <string>wss://api-prod.nova.social</string>
</dict>
```

**优先级验证**:
```swift
// 在 AppConfig.swift 中设置断点
// 查看执行顺序: 环境变量 > Info.plist > localhost

// Xcode Debugger:
// - 设置断点在 baseURL 的 switch 语句
// - 逐步执行
// - 确认优先级 ✅
```

### 2. 离线消息队列验证

#### 测试1: 基本入队
```swift
// 在 ChatViewModel 中测试
let queue = OfflineMessageQueue.shared

// 检查初始状态
print(queue.getCount())  // 应该是 0 ✅

// 添加消息
queue.enqueue(
    conversationId: UUID(),
    peerUserId: UUID(),
    text: "离线测试消息"
)

// 检查入队
print(queue.getCount())  // 应该是 1 ✅

// 检查 UserDefaults 持久化
let defaults = UserDefaults.standard
let data = defaults.data(forKey: "offlineMessages")
print(data != nil)  // 应该是 true ✅
```

#### 测试2: 网络恢复同步
```swift
// 1. 模拟离线环境
override networkStatus: false  // (需要在 NetworkMonitor 中添加测试接口)

// 2. 发送消息 (应该失败)
try? await repository.sendText(...)

// 3. 验证入队
queue.getCount()  // 应该 > 0

// 4. 模拟网络恢复
override networkStatus: true

// 5. 等待自动同步 (应该在 NetworkMonitor 触发)
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    queue.getCount()  // 应该变为 0 ✅
}
```

#### 测试3: 应用重启恢复
```bash
# 1. 启动应用
# 2. 断开网络 (Xcode 中右键选项或 Mac 关闭 WiFi)
# 3. 发送消息 (应该失败)
# 4. 验证入队: queue.getCount() > 0
# 5. 停止应用 (Cmd+.)
# 6. 恢复网络
# 7. 重新启动应用
# 8. 验证:
#    - 消息仍在队列中 ✅
#    - 自动同步到服务器 ✅
#    - 队列清空 ✅
```

### 3. Code Review
```bash
# 查看修改文件
git diff HEAD~1

# 应该包含:
# ✅ ios/NovaSocialApp/Network/Utils/AppConfig.swift
# ✅ ios/NovaSocialApp/Services/OfflineMessageQueue.swift (新)
# ✅ ios/NovaSocialApp/Services/NetworkMonitor.swift (新)
# ✅ ios/NovaSocialApp/Network/Repositories/MessagingRepository.swift

# 检查没有 print() 调试语句
# 应该只有 os_log() 或 Logger
grep -r "print(" /Users/proerror/Documents/nova/ios/NovaSocialApp/Services/

# 应该没有输出 (或只有注释) ✅
```

---

## 🔄 集成测试 (5分钟)

### 跨平台验证

**场景 1: Web → iOS 消息**
```
1. 打开 Web 前端和 iOS 应用 (都连接同一后端)
2. Web: 登录用户 A
3. iOS: 登录用户 B
4. Web: 发送消息给 B
5. iOS: 立即收到消息 (实时) ✅
```

**场景 2: iOS 离线 → Web 显示**
```
1. iOS: 断开网络
2. iOS: 发送消息
3. iOS: 消息进入离线队列 (验证: UI 中显示 "pending")
4. Web: 此时不显示消息
5. iOS: 恢复网络
6. iOS: 消息自动发送 ✅
7. Web: 刷新显示消息 ✅
```

---

## 📋 验证报告模板

```markdown
# 集成验证报告

**日期**: [日期]
**验证人**: [名字]
**环境**: [开发/测试/生产]

## 前端
- [ ] 认证系统: accessToken/refreshToken 分离 ✅
- [ ] Like 功能: UI 乐观更新 + 错误恢复 ✅
- [ ] Comment 功能: 创建和列表 ✅
- [ ] 无 console 错误 ✅

## iOS
- [ ] 硬编码IP 已移除 ✅
- [ ] 支持环境变量配置 ✅
- [ ] 离线队列持久化 ✅
- [ ] 网络恢复自动同步 ✅

## 集成测试
- [ ] Web → iOS 消息实时 ✅
- [ ] iOS 离线消息恢复 ✅

## 问题/建议
[如有]

## 签名
[验证人签名]
```

---

## 🆘 故障排除

### 问题1: 前端点赞提示 "401 Unauthorized"
```bash
# 原因: Token 过期或无效

# 解决:
# 1. 检查 AuthContext 中的 token 是否正确设置
# 2. 检查后端是否返回有效的 JWT
# 3. 验证 Authorization header:
#    Headers: "Bearer <token>"  ✅

# DevTools:
curl -H "Authorization: Bearer <token>" \
  http://localhost:8000/api/v1/posts/123/like \
  -X POST
```

### 问题2: iOS 连接到 192.168.31.154 而不是 localhost
```bash
# 原因: 代码中仍有硬编码值

# 检查:
grep -r "192.168" /Users/proerror/Documents/nova/ios/

# 应该没有输出

# 如果有:
git diff HEAD -- ios/NovaSocialApp/Network/Utils/AppConfig.swift
# 应该显示 hardcoded IP 被移除 ✅
```

### 问题3: 离线队列消息未同步
```bash
# 原因: NetworkMonitor 未触发或 MessagingRepository 错误

# 检查日志:
# Xcode Console 中查看:
# "Syncing 3 pending messages..."  ✅

# 如果没有:
# 1. 检查 NetworkMonitor 是否在 AppDelegate 中初始化
# 2. 检查 MessagingRepository.sendText() 是否抛出错误
# 3. 验证消息是否实际进入队列 (queue.getCount())
```

---

## ✅ 最终验收

```
前端验证通过? [ ] 是
iOS 验证通过? [ ] 是
集成测试通过? [ ] 是

所有检查项目完成? [ ] 是

可以合并到主分支? [ ] 是
```

---

**预计时间**: 30分钟
**难度**: ⭐⭐ (简单)
**责任人**: QA / 开发负责人
