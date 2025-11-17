# iOS 前端连接测试指南

**创建时间**: 2025-11-17
**问题**: api-gateway 仍有端口权限问题 (CrashLoopBackOff)
**解决方案**: 使用 port-forward 直接连接到后端服务

---

## 📊 当前状态

### ❌ api-gateway 无法启动
- **问题**: nginx 无法绑定端口 80 (Permission denied)
- **状态**: replicas=0 (已关闭避免资源浪费)

### ✅ 后端服务健康运行

| 服务 | 状态 | 端口 | 功能 |
|------|------|------|------|
| identity-service | ✅ Running (3 副本) | 8080 | 用户认证 |
| content-service | ✅ Running | 8080 | 内容管理 |
| media-service | ✅ Running | 8082 | 媒体上传 |
| search-service | ✅ Running | 8086 | 搜索功能 |
| notification-service | ✅ Running | 8080 | 通知推送 |

---

## 🚀 快速启动（3 步完成）

### 步骤 1: 启动 Port Forward

在终端运行：

```bash
cd /Users/proerror/Documents/nova
./start-api-port-forward.sh
```

你会看到：

```
🚀 启动 Nova API 服务 Port Forward...

📡 启动核心服务 Port Forward:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
启动 identity-service port-forward: localhost:8080 → 8080
  PID: 12345
  日志: /tmp/pf-identity-service.log
...

🔍 测试服务连接:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  测试 identity-service ... ✅ OK
  测试 content-service ... ✅ OK
  ...

✅ Port Forward 已启动!

📱 iOS App 可以连接到:
  - http://localhost:8080 (identity-service)
  - http://localhost:8081 (content-service)
  - http://localhost:8082 (media-service)
  - http://localhost:8086 (search-service)
  - http://localhost:8087 (notification-service)

⌛ Port Forward 运行中... (按 Ctrl+C 停止)
```

**保持这个终端窗口运行，不要关闭！**

---

### 步骤 2: 配置 iOS App

iOS 配置已经准备好，使用 **development** 模式会自动连接到 `localhost:8080`。

在 Xcode 中：

1. 打开项目：
   ```bash
   cd /Users/proerror/Documents/nova/ios/NovaSocial
   open FigmaDesignApp.xcodeproj
   ```

2. 确认 **Debug** 配置（已自动设置为 development 环境）

3. 选择模拟器或真机

4. 点击 ▶️ 运行

---

### 步骤 3: 验证连接

在 iOS app 启动后，检查控制台输出：

```
Current API Base URL: http://localhost:8080
```

#### 手动测试 API 连接

在另一个终端运行：

```bash
# 测试 identity service
curl http://localhost:8080/health
# 预期: {"status":"ok"} 或类似响应

# 测试认证端点
curl -X POST http://localhost:8080/api/v2/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"test123"}'

# 测试内容服务
curl http://localhost:8081/health

# 测试搜索服务
curl http://localhost:8086/health
```

---

## 🎯 服务端口映射

| 本地端口 | K8s 服务 | 服务端口 | API 路径 |
|---------|----------|---------|---------|
| 8080 | identity-service | 8080 | /api/v2/auth/*, /api/v2/users/* |
| 8081 | content-service | 8080 | /api/v2/posts/* |
| 8082 | media-service | 8082 | /api/v2/uploads/*, /api/v2/videos/*, /api/v2/reels/* |
| 8086 | search-service | 8086 | /api/v2/search* |
| 8087 | notification-service | 8080 | /api/v2/notifications/* |

**注意**: iOS 的 `APIConfig.swift` 配置为 `localhost:8080`，所有请求会发送到 identity-service。

如果需要访问其他服务，可以：
1. 在 iOS 代码中根据不同服务使用不同端口
2. 或者设置一个本地 nginx 作为路由

---

## ⚙️ iOS API 配置详情

`ios/NovaSocial/Shared/Services/Networking/APIConfig.swift`:

```swift
var baseURL: String {
    switch self {
    case .development:
        return "http://localhost:8080"  // ✅ Port-forward 方式
    case .staging:
        return "http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com"
    case .production:
        return "https://api.nova.social"
    }
}

static var current: APIEnvironment = {
    #if DEBUG
    return .development  // ✅ Debug 模式自动使用 development
    #else
    return .production
    #endif
}()
```

**API 端点**（已更新为 v2）：

```swift
struct Auth {
    static let login = "/api/v2/auth/login"
    static let register = "/api/v2/auth/register"
    static let refresh = "/api/v2/auth/refresh"
    static let logout = "/api/v2/auth/logout"
}

struct Content {
    static let getPost = "/api/v2/posts/get"
    static let createPost = "/api/v2/posts/create"
    static let postsByAuthor = "/api/v2/posts/author"
    static let bookmarks = "/api/v2/posts/bookmarks"
}

struct Media {
    static let uploadStart = "/api/v2/uploads/start"
    static let videos = "/api/v2/videos"
    static let reels = "/api/v2/reels"
}
```

---

## 🔍 故障排查

### 问题 1: 连接失败 "Cannot connect to server"

**检查**:
```bash
# 1. 确认 port-forward 正在运行
ps aux | grep "kubectl port-forward"

# 2. 检查端口是否被占用
lsof -i :8080

# 3. 查看 port-forward 日志
tail -f /tmp/pf-identity-service.log
```

**解决**:
```bash
# 重启 port-forward
./start-api-port-forward.sh
```

---

### 问题 2: iOS app 显示错误的 URL

**检查**:
```swift
// 在 App.swift 或 ContentView.swift 添加
print("Current API Environment: \(APIConfig.current)")
print("Base URL: \(APIConfig.current.baseURL)")
```

**解决**:
```swift
// 强制设置为 development
APIConfig.current = .development
```

---

### 问题 3: 特定 API 端点 404

**原因**: 当前 port-forward 只转发到单个服务

**解决**: 根据需要的服务手动调整请求：

```swift
// 临时方案：根据服务类型使用不同端口
let baseURL = {
    switch serviceType {
    case .auth:
        return "http://localhost:8080"  // identity-service
    case .content:
        return "http://localhost:8081"  // content-service
    case .media:
        return "http://localhost:8082"  // media-service
    case .search:
        return "http://localhost:8086"  // search-service
    }
}()
```

---

### 问题 4: K8s pod 不健康

**检查**:
```bash
kubectl get pods -n nova-staging
```

**如果有 pod 不是 Running**:
```bash
# 查看 pod 详情
kubectl describe pod -n nova-staging POD_NAME

# 查看日志
kubectl logs -n nova-staging POD_NAME --tail=100

# 重启 pod
kubectl delete pod -n nova-staging POD_NAME
```

---

## 🛑 停止 Port Forward

```bash
# 方法 1: 在运行脚本的终端按 Ctrl+C

# 方法 2: 杀死所有 port-forward 进程
pkill -f "kubectl port-forward.*nova-staging"

# 方法 3: 查看并选择性杀死
ps aux | grep "kubectl port-forward"
kill PID
```

---

## 📊 测试清单

- [ ] ✅ 启动 `./start-api-port-forward.sh`
- [ ] ✅ 看到所有服务测试通过
- [ ] ✅ 在 Xcode 打开 iOS 项目
- [ ] ✅ 确认 Debug 配置
- [ ] ✅ 运行 iOS app
- [ ] ✅ 检查控制台显示 `http://localhost:8080`
- [ ] ✅ 测试登录功能
- [ ] ✅ 测试内容浏览
- [ ] ✅ 测试搜索功能

---

## 🎯 下一步（修复 api-gateway）

当前使用 port-forward 是**临时方案**，适合开发测试。

**长期方案**（按优先级）：

### 选项 1: 修复 api-gateway 端口配置

修改 nginx 监听 8080 而不是 80：

```yaml
# k8s/infrastructure/base/api-gateway/deployment.yaml
containers:
  - name: nginx
    ports:
      - containerPort: 8080  # 改为 8080
        name: http

# nginx.conf
server {
    listen 8080;  # 改为 8080
    ...
}
```

### 选项 2: 安装 Ingress Controller

```bash
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

### 选项 3: 为每个服务创建 LoadBalancer

```bash
# 为 identity-service 创建 LoadBalancer
kubectl patch svc identity-service -n nova-staging -p '{"spec":{"type":"LoadBalancer"}}'
```

---

## 💡 开发建议

### 启用详细日志

```swift
// App.swift
APIFeatureFlags.enableRequestLogging = true
```

### 使用 Mock 数据

如果后端不稳定：

```swift
APIFeatureFlags.enableMockData = true
```

### 网络调试

使用 Charles Proxy 或 Proxyman 查看 HTTP 请求：

```swift
// 在模拟器中配置代理后，可以看到所有 API 请求
```

---

**🎉 现在可以开始测试 iOS app 了！**

**命令总结**:
```bash
# 1. 启动 port-forward（保持运行）
./start-api-port-forward.sh

# 2. 打开 iOS 项目
cd ios/NovaSocial && open FigmaDesignApp.xcodeproj

# 3. 在 Xcode 中运行 app (▶️)

# 4. 测试完成后停止 port-forward
# 按 Ctrl+C 或运行:
pkill -f "kubectl port-forward.*nova-staging"
```
