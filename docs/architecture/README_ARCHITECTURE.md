# Nova 架构文档

本目录包含 Nova 社交应用的完整后端架构和 iOS 集成分析。

## 📄 文档清单

### 1. **BACKEND_IOS_ARCHITECTURE_ANALYSIS.md** (详细版)
完整的架构分析文档，包含：
- 后端服务概览（8个微服务）
- 数据库表结构详解
- API 端点完整参考
- iOS 网络层实现
- 数据流和认证流程
- 常见问题排查指南
- 10 阶段实施计划

**适合：** 深入理解系统设计，规划实现细节

### 2. **ARCHITECTURE_QUICK_REFERENCE.md** (快速版)
快速参考指南，包含：
- 系统框图
- 关键文件位置
- 数据流摘要
- 常见问题表格
- 工作流说明

**适合：** 日常开发查询，快速定位问题

---

## 🏗️ 系统架构

```
iOS App (Swift/SwiftUI)
    ↓
APIClient (网络层)
    ↓
Nginx Gateway (API 网关 :3000)
    ↓
├── Feed Service (:8082)
├── Content Service (:8081)
├── User Service (:8080)
├── Auth Service (:8084)
└── Messaging Service (:3000)
    ↓
├── PostgreSQL (主数据库)
├── Redis (缓存)
└── ClickHouse (分析/Feed)
```

---

## ✅ 现状总结

### 已完成
- ✅ 数据库 schema（posts, post_images, post_metadata）
- ✅ API 路由和网关配置
- ✅ iOS HTTP 客户端（APIClient）
- ✅ 认证流程（JWT + Keychain）
- ✅ 网络配置（正确的 IP 和端口）

### 需要完成
- ⚠️ Content-Service handlers（CRUD 业务逻辑）
- ⚠️ Feed-Service ClickHouse 集成
- ⚠️ iOS Post 模型定义（Codable）
- ⚠️ 图片转码异步 Job

---

## 🎯 快速开始

### 查看架构
```bash
# 详细版本
cat docs/BACKEND_IOS_ARCHITECTURE_ANALYSIS.md

# 快速参考
cat docs/ARCHITECTURE_QUICK_REFERENCE.md
```

### 常见问题
1. **iOS 如何连接后端？**
   → 见 Quick Reference §四（iOS 客户端网络配置分析）

2. **哪些数据库表已完成？**
   → 见 Analysis §二（数据库架构）

3. **API 端点有哪些？**
   → 见 Analysis §三（API 端点详解）

4. **连接超时怎么办？**
   → 见 Analysis §九（常见问题排查）

---

## 🛠️ 开发路线图

### Phase 1 (2-3 天)
实现 Content-Service posts CRUD
- [ ] create_post handler
- [ ] get_post handler
- [ ] get_user_posts handler
- [ ] delete_post handler

### Phase 2 (3-5 天)
Feed 数据聚合
- [ ] ClickHouse 查询集成
- [ ] Cursor 分页实现
- [ ] Fallback 查询（时间排序）

### Phase 3 (2-3 天)
iOS 完整集成
- [ ] Post Codable 模型
- [ ] FeedRepository 实现
- [ ] SwiftUI 视图集成

### Phase 4 (2-3 天)
测试和优化
- [ ] 端到端测试
- [ ] 性能基准测试
- [ ] 错误恢复测试

---

## 📊 关键数据

### 数据库
- **posts**: 用户帖子，包含 caption、image_key、status
- **post_images**: 转码的图片变体（thumbnail, medium, original）
- **post_metadata**: 参与统计（like_count, comment_count, view_count）

### API 端点
```
POST   /api/v1/posts                      # 创建帖子
GET    /api/v1/posts/{id}                 # 获取帖子
GET    /api/v1/feed                       # 获取 Feed
DELETE /api/v1/posts/{id}                 # 删除帖子
```

### 认证
```
POST /api/v1/auth/login      # 获取 token
Bearer <token>               # 自动注入到请求头
```

---

## 🔐 网络配置

### iOS Simulator
```
baseURL = "http://192.168.31.127:3000"
```

### iOS Device (同网络)
```
baseURL = "http://<host_ip>:3000"
```

### 后端（Docker）
```
内部：service-name:port
外部：192.168.31.127:3000 (通过 nginx)
```

---

## 📞 技术支持

### 连接超时？
→ 检查 IP 地址（应该是 192.168.31.127，不是 localhost）

### 401 Unauthorized？
→ 先登录获取 token，检查 AuthManager 中是否有 token

### Feed 为空？
→ 确认数据库中有帖子数据，检查用户权限

### 完整排查
→ 见 Analysis §九（常见问题排查）

---

## 📚 相关文件

### 后端
- `/backend/migrations/003_posts_schema.sql` - posts 表定义
- `/backend/content-service/src/handlers/posts.rs` - posts handlers
- `/backend/feed-service/src/handlers/feed.rs` - feed handlers

### iOS
- `/ios/NovaSocial/Network/Core/APIClient.swift` - HTTP 客户端
- `/ios/NovaSocial/Network/Utils/AppConfig.swift` - 环境配置
- `/ios/NovaSocial/Network/Repositories/PostRepository.swift` - 帖子业务逻辑
- `/ios/NovaSocial/Network/Repositories/FeedRepository.swift` - Feed 业务逻辑

---

**最后更新：** 2025-11-03  
**维护者：** Nova 架构团队  
**许可证：** 项目许可证

