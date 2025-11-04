# Nova 架构快速参考

## 系统概览

```
┌─────────────────────────────────────────────────────────────┐
│                    iOS App (Swift)                          │
│  Network/Core/APIClient.swift → Authorization + Requests   │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTP(S)
                     │ 192.168.31.127:3000 (开发)
                     ▼
┌─────────────────────────────────────────────────────────────┐
│            Nginx Gateway (API Gateway)                      │
│  Port 3000 → Routes requests to microservices              │
└────┬─────────┬──────────┬─────────────┬────────────────────┘
     │         │          │             │
  /feed  /posts /users  /auth        /ws
     │         │          │             │
     ▼         ▼          ▼             ▼
   Feed-     Content-   User-        Messaging-
  Service    Service    Service      Service
  (8082)     (8081)     (8080)       (3000)
     │         │          │             │
     └─────────┴──────────┴─────────────┘
                     │
        ┌────────────┼────────────┐
        ▼            ▼            ▼
    PostgreSQL    Redis       ClickHouse
    (主数据库)    (缓存)      (分析/Feed)
```

---

## 关键文件位置

### 后端
- **Services**: `/backend/{service-name}/src/`
- **Migrations**: `/backend/migrations/`
  - `003_posts_schema.sql` ← 帖子表定义
  - `019_stories_schema.sql` ← 故事表定义
- **Docker**: `/docker-compose.yml`

### iOS
- **网络层**: `/ios/NovaSocial/Network/`
  - `Core/APIClient.swift` ← HTTP 客户端
  - `Utils/AppConfig.swift` ← 环境配置
- **业务层**: `/ios/NovaSocial/Network/Repositories/`
  - `PostRepository.swift` ← 帖子操作
  - `FeedRepository.swift` ← Feed 加载

---

## 数据流

### 发送帖子
```
1. iOS: PostRepository.createPost(image, caption)
   ↓
2. iOS: 压缩图片 → 上传到 S3 → 获取 image_key
   ↓
3. iOS: POST /api/v1/posts { image_key, caption }
   ↓
4. Backend: ContentService 插入 posts + post_metadata
   ↓
5. iOS: 收到 { id, created_at, ... }
```

### 加载 Feed
```
1. iOS: FeedRepository.loadFeed(cursor, limit)
   ↓
2. iOS: GET /api/v1/feed?cursor=...&limit=20&algo=ch
   ↓
3. Backend: Feed-Service 查询 ClickHouse
   ↓
4. Backend: 返回 { posts: [id1, id2, ...], cursor, has_more }
   ↓
5. iOS: 并发获取 Post 详情 (post_images + 统计)
   ↓
6. iOS: 缓存并显示
```

---

## API 端点

| 方法 | 路径 | 描述 |
|------|------|------|
| POST | `/api/v1/posts` | 创建帖子 |
| GET | `/api/v1/posts/{id}` | 获取帖子详情 |
| GET | `/api/v1/posts/user/{user_id}` | 获取用户帖子 |
| DELETE | `/api/v1/posts/{id}` | 删除帖子 |
| GET | `/api/v1/feed` | 获取 Feed（需要游标参数） |
| POST | `/api/v1/auth/login` | 登录 |
| GET | `/api/v1/users/{id}` | 获取用户资料 |

---

## 数据库表

### posts
```sql
id (UUID)
user_id (UUID) → 外键 users.id
caption (TEXT, ≤2200 chars)
image_key (VARCHAR) → S3 key
status (pending|processing|published|failed)
created_at, updated_at, soft_delete
```

### post_images
```sql
post_id (UUID) → 外键 posts.id
s3_key (VARCHAR)
size_variant (thumbnail|medium|original)
status (pending|processing|completed|failed)
url (VARCHAR)
```

### post_metadata
```sql
post_id (UUID, PK)
like_count, comment_count, view_count
```

---

## 环境配置

### 开发环境
```swift
// iOS Simulator
baseURL = "http://192.168.31.127:3000"

// iOS Device (same network)
baseURL = "http://<mac_ip>:3000"

// 后端服务（Docker）
内部访问：service-name:port
外部访问（iOS）：192.168.31.127:3000
```

### 认证
```
1. POST /api/v1/auth/login
   ← { access_token, refresh_token, expires_in }
2. 保存到 Keychain (AuthManager.shared)
3. 所有请求自动注入: Authorization: Bearer <token>
4. 过期时自动刷新
```

---

## 关键问题排查

| 问题 | 原因 | 解决 |
|------|------|------|
| 连接超时 | localhost 而非 IP | 改用 192.168.31.127:3000 |
| 401 Unauthorized | 无 token | 先登录 `/api/v1/auth/login` |
| Feed 为空 | 无帖子数据 | 先创建帖子或检查权限 |
| 图片不显示 | post_images 未生成 | 检查后端转码 Job |

---

## 工作流

### 后端开发
```bash
cd backend
cargo build
docker-compose up
# 修改代码 → cargo build → 重启容器
```

### iOS 开发
```bash
cd ios/NovaSocial
# 在 Xcode 中
# 确保 AppConfig.swift 指向正确的 baseURL
# 运行模拟器或设备
```

### 测试 API
```bash
# 获取 token
curl -X POST http://192.168.31.127:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"pass"}'

# 使用 token
curl -X GET http://192.168.31.127:3000/api/v1/feed \
  -H "Authorization: Bearer <token>"
```

---

## 下一步优先级

1. **完成 Content-Service** (2-3 天)
   - 实现 posts CRUD
   - 连接 post_images 表

2. **Feed 数据集成** (3-5 天)
   - ClickHouse 查询
   - Cursor 分页

3. **iOS 模型和视图** (2-3 天)
   - Post Codable 结构
   - FeedView 集成

4. **端到端测试** (1-2 天)

---

详见：`BACKEND_IOS_ARCHITECTURE_ANALYSIS.md`
