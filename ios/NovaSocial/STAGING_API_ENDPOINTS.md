# Nova iOS - Staging API 端点配置

**环境**: AWS EKS Staging
**更新时间**: 2025-11-17
**LoadBalancer URL**: `http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com`

---

## 可用服务状态

### ✅ 运行中的服务

| 服务 | 状态 | 副本数 | 端口 | 版本 |
|------|------|--------|------|------|
| **identity-service** | Running | 3 | 8080 | c93dafd |
| **content-service** | Running | 1 | 8080 | 4e7634a |
| **media-service** | Running | 1 | 8082 | 38cc45e |
| **search-service** | Running | 1 | 8086 | 3bc3d08 |
| **notification-service** | Running | 1 | 8080 | c849ea7 |

### ❌ 已关闭的服务

- **api-gateway**: 已设置 replicas=0 (之前 CrashLoopBackOff)
- **social-service**: replicas=0 (配置中已禁用)

---

## API 路由配置

所有请求通过 Ingress (`nova-api-gateway`) 路由到对应的后端服务。

### 认证服务 (identity-service:8080)

```
POST /api/v2/auth/login
POST /api/v2/auth/register
POST /api/v2/auth/refresh
POST /api/v2/auth/logout
GET  /api/v2/users/{id}
PUT  /api/v2/users/{id}
```

**示例请求**:
```bash
curl -X POST \
  http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com/api/v2/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test","password":"test123"}'
```

### 内容服务 (content-service:8080)

```
GET    /api/v2/posts/{id}
POST   /api/v2/posts/create
PUT    /api/v2/posts/update
DELETE /api/v2/posts/delete
GET    /api/v2/posts/author/{author_id}
GET    /api/v2/posts/bookmarks
```

**示例请求**:
```bash
curl -X GET \
  http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com/api/v2/posts/author/user123 \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### 媒体服务 (media-service:8082)

```
POST /api/v2/uploads/start
POST /api/v2/uploads/progress
POST /api/v2/uploads/complete
GET  /api/v2/videos/{id}
GET  /api/v2/reels
```

**示例请求**:
```bash
curl -X POST \
  http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com/api/v2/uploads/start \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"filename":"video.mp4","size":1024000}'
```

### 搜索服务 (search-service:8086)

```
GET  /api/v2/search?q={query}
GET  /api/v2/search/users?q={query}
GET  /api/v2/search/posts?q={query}
```

**示例请求**:
```bash
curl -X GET \
  "http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com/api/v2/search?q=test" \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### 通知服务 (notification-service:8080)

```
GET    /api/v2/notifications
POST   /api/v2/notifications/mark-read
DELETE /api/v2/notifications/{id}
```

---

## iOS App 配置

### 1. 环境选择

在 Xcode 中选择 **staging** 环境来使用 AWS EKS 后端：

```swift
// App.swift 或 main scene
APIConfig.current = .staging
```

### 2. 自动配置

`APIConfig.swift` 已更新为自动连接到 staging 环境：

```swift
case .staging:
    return "http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com"
```

### 3. API 端点示例

所有端点已更新为 v2 API：

```swift
// 认证
APIConfig.Auth.login        // /api/v2/auth/login
APIConfig.Auth.register     // /api/v2/auth/register

// 内容
APIConfig.Content.createPost    // /api/v2/posts/create
APIConfig.Content.postsByAuthor // /api/v2/posts/author

// 媒体
APIConfig.Media.uploadStart  // /api/v2/uploads/start
APIConfig.Media.videos       // /api/v2/videos
APIConfig.Media.reels        // /api/v2/reels

// 搜索
// 直接使用: baseURL + "/api/v2/search?q=..."
```

---

## 健康检查

### 服务健康状态

```bash
# Identity Service
curl http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com/health

# 其他服务健康检查（需要配置 ingress 路由）
# /api/v2/content/health
# /api/v2/media/health
# /api/v2/search/health
```

---

## 注意事项

### ⚠️ 当前限制

1. **social-service 未运行**:
   - 关系功能 (follow/unfollow)
   - Feed 功能 (likes, comments, shares)
   - 需要启动 social-service 才能使用这些功能

2. **Ingress Controller 未配置**:
   - 当前直接通过 Service LoadBalancer 访问
   - 可能缺少完整的路由规则
   - 建议配置 nginx-ingress-controller

3. **HTTPS 未配置**:
   - 当前使用 HTTP (不是 HTTPS)
   - 生产环境需要配置 TLS 证书

### ✅ 可用功能

- ✅ 用户认证 (登录/注册)
- ✅ 内容浏览 (posts)
- ✅ 媒体上传 (图片/视频)
- ✅ 搜索功能
- ✅ 通知功能

### ❌ 不可用功能 (需启动 social-service)

- ❌ 关注/取关
- ❌ 点赞/评论
- ❌ Feed 流
- ❌ 分享功能

---

## 启动 social-service (可选)

如果需要社交功能，运行：

```bash
kubectl scale deployment social-service -n nova-staging --replicas=1
```

等待服务启动后，可用端点：

```
POST /api/v2/feed/like
POST /api/v2/feed/unlike
POST /api/v2/feed/comment
GET  /api/v2/feed/comments
POST /api/v2/relationships/follow
POST /api/v2/relationships/unfollow
GET  /api/v2/relationships/followers
GET  /api/v2/relationships/following
```

---

## 故障排查

### 连接失败

```swift
// 检查 APIConfig.swift 中的 baseURL
print(APIConfig.current.baseURL)
// 应该输出: http://abf1c7cfd91c44c8cb038c34cc857372-567097626.ap-northeast-1.elb.amazonaws.com
```

### 401 Unauthorized

确保在请求头中包含有效的 JWT token：

```swift
APIClient.shared.setAuthToken("your-jwt-token")
```

### 404 Not Found

- 检查端点路径是否正确（应该是 `/api/v2/...`）
- 确认目标服务正在运行

### 查看服务日志

```bash
# 查看特定服务的日志
kubectl logs -n nova-staging -l app=identity-service --tail=100
kubectl logs -n nova-staging -l app=content-service --tail=100
kubectl logs -n nova-staging -l app=media-service --tail=100
```

---

## 下一步

1. **配置 Ingress Controller**: 安装 nginx-ingress-controller 以启用完整路由
2. **启用 HTTPS**: 配置 TLS 证书
3. **启动 social-service**: 如需社交功能
4. **配置监控**: 设置 Prometheus/Grafana 监控服务健康状态
5. **性能测试**: 使用 k6 或 JMeter 测试 API 性能

---

**文档维护**: 随着服务更新，请同步更新此文档
**联系方式**: 如有问题，请检查 K8s 集群日志或咨询 DevOps 团队
