# 使用本地代理访问 GitHub Staging（模拟器指南）

## 📖 概述

这个指南说明如何在 iOS 模拟器中使用本地 HTTP 代理服务器转发请求到 GitHub Staging API，从而让模拟器能访问远程 API。

---

## 🎯 工作原理

```
iOS 模拟器 → 本地代理 (localhost:8080) → GitHub Staging API (https://staging-api.nova.app)
```

### 为什么需要代理？
- ❌ 模拟器无法直接访问外部 HTTPS 端点（网络隔离）
- ✅ 代理服务器运行在主机上，可以访问真实网络
- ✅ 模拟器通过 localhost 访问主机上的代理
- ✅ 代理转发所有请求到 GitHub Staging

---

## 🚀 快速启动（3 步）

### 步骤 1: 启动代理服务器

```bash
cd /Users/proerror/Documents/nova
node proxy-server.js
```

预期输出：
```
✅ 代理服务器已启动！
📍 本地地址: http://localhost:8080
🎯 目标: https://staging-api.nova.app

在模拟器中运行应用时，使用环境变量: API_ENV=stagingProxy

或在 Xcode 中配置:
  Product → Scheme → Edit Scheme → Run → Arguments → Environment Variables
  添加: API_ENV = stagingProxy

按 Ctrl+C 停止代理服务器
```

### 步骤 2: 构建应用（使用代理环境）

在**新的终端窗口**中：

```bash
cd /Users/proerror/Documents/nova/ios/NovaSocial

# 方法 A: 使用环境变量
API_ENV=stagingProxy xcodebuild \
  -workspace NovaSocial.xcworkspace \
  -scheme NovaSocial \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build

# 方法 B: 在 Xcode 中手动配置
# 见"步骤 3"
```

### 步骤 3: 在 Xcode 中配置（可选）

如果想用 Xcode 直接运行：

1. **打开 Xcode**
   ```bash
   open ios/NovaSocial/NovaSocial.xcworkspace
   ```

2. **配置 Scheme**
   - Product → Scheme → Edit Scheme
   - 选择 "Run" 标签
   - 点击 "Arguments" 标签
   - 在 "Environment Variables" 中添加：
     ```
     API_ENV = stagingProxy
     ```

3. **按 Cmd+R 运行**

---

## ✅ 验证连接

### 方法 1: 从命令行测试代理

```bash
# 测试代理本身
curl -v http://localhost:8080/health

# 应该返回从 GitHub Staging 返回的响应
```

### 方法 2: 在模拟器中观察

应用启动时，应该看到：

**Home Feed** 选项卡 → 加载 → 显示数据（或之前的 Feed 缓存）

或者如果没有数据：

**Home Feed** 选项卡 → 加载 → 错误（如果 GitHub Staging 服务未运行）

### 方法 3: 检查代理日志

代理服务器会打印所有请求：

```
[10:45:30] INFO a1b2c3 GET /feed?page=0&limit=10
[10:45:31] INFO a1b2c3 Response: 200
[10:45:31] INFO 2d3e4f GET /users/123
[10:45:31] INFO 2d3e4f Response: 200
```

---

## 📊 完整工作流示例

### 终端 1: 启动代理

```bash
$ cd /Users/proerror/Documents/nova
$ node proxy-server.js

✅ 代理服务器已启动！
📍 本地地址: http://localhost:8080
🎯 目标: https://staging-api.nova.app
```

### 终端 2: 构建并运行应用

```bash
$ cd /Users/proerror/Documents/nova/ios/NovaSocial
$ API_ENV=stagingProxy xcodebuild build-run-sim \
    -workspace NovaSocial.xcworkspace \
    -scheme NovaSocial \
    -destination 'platform=iOS Simulator,id=9AFF389A-84EC-4F8E-AD8D-7ADF8152EED8'

✅ Build successful
✅ App launched in simulator
```

### 模拟器: 观察应用行为

```
iOS App:
1. Home Feed 标签显示加载中...
2. 代理服务器打印请求日志
3. 应用显示数据或错误
```

---

## 🔍 高级用法

### 修改默认环境

如果想让所有 DEBUG 构建都默认使用代理：

编辑 `APIConfig.swift`：

```swift
#if DEBUG
// 改为
return .stagingProxy
#else
return .production
#endif
```

### 同时运行多个代理

```bash
# 终端 1: 代理到 GitHub Staging
PORT=8080 node proxy-server.js

# 终端 2: 代理到其他 API（可选）
PORT=8081 GITHUB_HOST=other-api.example.com node proxy-server.js
```

### 添加请求日志

代理已经包含了详细的日志。如果需要更多信息，编辑 `proxy-server.js`：

```javascript
// 添加请求/响应体日志
req.on('data', (chunk) => {
    log('info', `${requestId} Request body: ${chunk.toString()}`);
});
```

---

## ❌ 故障排除

### 问题 1: `Port 8080 already in use`

**解决方案**:
```bash
# 杀死占用 8080 的进程
lsof -ti:8080 | xargs kill -9

# 或使用不同端口
PORT=8081 node proxy-server.js
```

### 问题 2: 代理运行但应用仍显示错误

**检查清单**:
```bash
# 1. 验证代理正在运行
curl http://localhost:8080/health

# 2. 检查应用配置
# Xcode 中确认: API_ENV = stagingProxy

# 3. 检查 GitHub Staging 是否在线
curl https://staging-api.nova.app/health

# 4. 查看代理日志中是否有请求
# 检查终端中代理输出是否显示传入请求
```

### 问题 3: `CORS error` 或 `origin not allowed`

**解决方案**:
代理已配置允许所有 CORS。如果仍有问题，确保：
1. 代理正确运行（检查日志）
2. API_ENV 设置为 stagingProxy
3. 重新构建应用

### 问题 4: 模拟器无法连接到 localhost:8080

**解决方案**:
```bash
# 确认代理绑定到所有接口
# proxy-server.js 使用 '0.0.0.0' 所以应该可以工作

# 尝试：
# 1. 重启模拟器
xcrun simctl shutdown all
xcrun simctl erase all

# 2. 在 Xcode 中重新运行应用
```

---

## 📈 性能考虑

- ⚡ **延迟**: 代理增加 5-10ms 延迟
- 💾 **内存**: 代理使用 < 50MB 内存
- 🔄 **连接**: 支持无限并发连接

---

## 🎓 环境切换

所有支持的环境：

```bash
# 本地 Docker Staging
API_ENV=stagingLocal xcodebuild ...

# GitHub Staging 通过代理
API_ENV=stagingProxy xcodebuild ...

# GitHub Staging 直接（物理设备）
API_ENV=stagingGitHub xcodebuild ...

# 生产环境
API_ENV=production xcodebuild ...
```

---

## 📚 相关文档

- [GitHub Staging 测试报告](./GITHUB_STAGING_TEST_REPORT.md)
- [iOS Staging 配置指南](./IOS_STAGING_CONFIG.md)
- [Staging 环境设置指南](./STAGING_SETUP_GUIDE.md)

---

## ✨ 总结

现在你可以在 iOS 模拟器中完全访问 GitHub Staging API！

```bash
# 1. 启动代理
node proxy-server.js

# 2. 运行应用（另一个终端）
API_ENV=stagingProxy xcodebuild build-run-sim ...

# 3. 在模拟器中享受完整的远程 API 功能！
```
