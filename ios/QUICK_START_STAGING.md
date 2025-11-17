# iOS App - Staging 环境快速启动指南

## 一、当前状态总结

### ✅ 已完成的配置

1. **关闭问题服务**：api-gateway (CrashLoopBackOff) 已设置 replicas=0
2. **iOS 配置更新**：`APIConfig.swift` 已更新连接到 AWS staging 环境
3. **API 路径升级**：所有端点从 v1 升级到 v2
4. **文档创建**：完整的 API 端点文档已生成

### 🚀 可用服务 (AWS EKS Staging)

| 服务 | 状态 | 功能 |
|------|------|------|
| identity-service | ✅ Running (3 副本) | 用户认证、登录注册 |
| content-service | ✅ Running | 内容管理、Posts |
| media-service | ✅ Running | 媒体上传、视频、Reels |
| search-service | ✅ Running | 搜索功能 |
| notification-service | ✅ Running | 通知推送 |

### ❌ 暂不可用的功能

- social-service (replicas=0): 关注、点赞、评论等社交功能

---

## 二、启动 iOS App

### 方法 1: 使用 Xcode (推荐)

```bash
cd /Users/proerror/Documents/nova/ios/NovaSocial

# 打开 Xcode 项目
open FigmaDesignApp.xcodeproj
```

在 Xcode 中：
1. 选择 **Debug** 配置（自动使用 staging 环境）
2. 选择模拟器或真机
3. 点击 ▶️ 运行

### 方法 2: 使用命令行

```bash
# 构建并运行在模拟器
xcodebuild -project FigmaDesignApp.xcodeproj \
  -scheme FigmaDesignApp \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build

# 运行应用
xcrun simctl launch booted com.nova.FigmaDesignApp
```

---

## 三、验证连接

### 1. 检查 API 配置

在 `App.swift` 或首次启动时，确认：

```swift
print("Current API Base URL: \(APIConfig.current.baseURL)")
// 应该输出: http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com
```

### 2. 测试健康检查

从 iOS 代码中测试：

```swift
let healthURL = "\(APIConfig.current.baseURL)/health"
// GET 请求应该返回 200 OK
```

### 3. 测试登录功能

```swift
// 使用 APIConfig.Auth.login 端点
let loginURL = APIConfig.current.baseURL + APIConfig.Auth.login
// POST /api/v2/auth/login
```

---

## 四、可用的 API 端点

### 认证 API (identity-service)
```
POST /api/v2/auth/login       - 用户登录
POST /api/v2/auth/register    - 用户注册
POST /api/v2/auth/refresh     - 刷新 Token
POST /api/v2/auth/logout      - 用户登出
GET  /api/v2/users/{id}       - 获取用户信息
```

### 内容 API (content-service)
```
GET    /api/v2/posts/{id}          - 获取单个 Post
POST   /api/v2/posts/create        - 创建 Post
GET    /api/v2/posts/author/{id}   - 获取用户的所有 Posts
GET    /api/v2/posts/bookmarks     - 获取收藏的 Posts
```

### 媒体 API (media-service)
```
POST /api/v2/uploads/start     - 开始上传
POST /api/v2/uploads/complete  - 完成上传
GET  /api/v2/videos/{id}       - 获取视频
GET  /api/v2/reels             - 获取 Reels 列表
```

### 搜索 API (search-service)
```
GET /api/v2/search?q={query}  - 全局搜索
```

### 通知 API (notification-service)
```
GET    /api/v2/notifications           - 获取通知列表
POST   /api/v2/notifications/mark-read - 标记已读
DELETE /api/v2/notifications/{id}      - 删除通知
```

---

## 五、常见问题

### Q1: 连接失败 "Cannot connect to server"

**检查**:
```bash
# 1. 验证 LoadBalancer 是否可访问
curl -I http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com/health

# 2. 检查服务状态
kubectl get pods -n nova-staging -l 'app in (identity-service,content-service)'

# 3. 查看服务日志
kubectl logs -n nova-staging -l app=identity-service --tail=50
```

### Q2: 401 Unauthorized 错误

**原因**: 缺少认证 token 或 token 已过期

**解决**:
```swift
// 登录后设置 token
APIClient.shared.setAuthToken(loginResponse.token)
```

### Q3: 404 Not Found 错误

**检查**:
- API 路径是否正确（应该是 `/api/v2/...`）
- 目标服务是否在运行

```bash
kubectl get pods -n nova-staging | grep Running
```

### Q4: 社交功能不可用 (关注、点赞等)

**原因**: social-service 当前 replicas=0

**启用**:
```bash
# 启动 social-service
kubectl scale deployment social-service -n nova-staging --replicas=1

# 等待服务启动
kubectl wait --for=condition=ready pod -l app=social-service -n nova-staging --timeout=60s
```

---

## 六、开发建议

### 启用请求日志

在 Debug 模式下查看所有 API 请求：

```swift
APIFeatureFlags.enableRequestLogging = true
```

### 使用 Mock 数据测试

如果后端不稳定，可以启用 mock 模式：

```swift
APIFeatureFlags.enableMockData = true
```

### 离线模式

启用缓存和重试机制：

```swift
APIFeatureFlags.enableOfflineMode = true
APIFeatureFlags.maxRetryAttempts = 3
```

---

## 七、监控和调试

### 查看 K8s 服务状态

```bash
# 查看所有 pods
kubectl get pods -n nova-staging

# 查看服务详情
kubectl describe svc -n nova-staging identity-service

# 实时查看日志
kubectl logs -f -n nova-staging -l app=identity-service
```

### 测试服务健康

```bash
# 从本地测试
curl http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com/health

# 测试认证端点
curl -X POST \
  http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com/api/v2/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"test123"}'
```

---

## 八、下一步

1. **启动应用**: 使用 Xcode 打开并运行 iOS app
2. **测试基础功能**:
   - ✅ 用户注册/登录
   - ✅ 浏览内容 (Posts)
   - ✅ 搜索功能
   - ✅ 通知查看
3. **启用社交功能** (可选):
   ```bash
   kubectl scale deployment social-service -n nova-staging --replicas=1
   ```
4. **查看详细文档**: `ios/NovaSocial/STAGING_API_ENDPOINTS.md`

---

## 需要帮助？

- **K8s 问题**: 检查 pod 日志 `kubectl logs -n nova-staging POD_NAME`
- **iOS 问题**: 查看 Xcode 控制台输出
- **API 问题**: 参考 `STAGING_API_ENDPOINTS.md` 文档

---

**🎉 现在可以开始开发和测试了！**
