# Nova 数据库架构 - 快速参考

## 一句话总结
所有 92 个表都在 `nova` 数据库中。代码按微服务组织，但数据库没有分解。这在初期是正确的，现在需要清晰的所有权文档。

## 表的逻辑所有权（按服务）

### auth-service (10 个表)
```
users                       ← 核心用户表（所有服务共享）
sessions                    ← 活跃会话
refresh_tokens              ← 刷新令牌
email_verifications         ← 邮箱验证
password_resets             ← 密码重置
auth_logs                   ← 认证日志
jwt_signing_keys            ← JWT 密钥轮换
token_revocations           ← 令牌撤销
two_fa_backup_codes         ← 2FA 备用码
two_fa_sessions             ← 2FA 会话
```

### user-service (5 个表)
```
user_permissions            ← 用户权限
user_feed_preferences       ← 订阅偏好
blocked_users               ← 黑名单
follows                     ← 社交图（谁关注谁）
social_metadata             ← 关注关系的计数
```

### content-service (35+ 个表)
```
# Posts (7)
posts                       ← 用户发布的文章
post_images                 ← 转码的图像变体
post_metadata               ← 点赞/评论计数
post_videos                 ← 文章关联的视频
post_shares                 ← 分享追踪
comments                    ← 评论
likes                       ← 点赞

# Stories (3)
stories                     ← 限时故事
story_close_friends         ← 特别关注列表
story_views                 ← 故事浏览记录

# Trending (3)
trending_scores             ← 热度计算缓存
trending_metadata           ← 热度计算元数据
engagement_events           ← 参与度事件
```

### media-service (15+ 个表)
```
# Uploads (3)
uploads                     ← 上传元数据
upload_sessions             ← 上传会话（进度追踪）
upload_chunks               ← 分片上传进度

# Videos (7)
videos                      ← 视频元数据
video_embeddings            ← 视频向量嵌入（搜索用）
video_engagement            ← 视频的观看/点赞
video_pipeline_state        ← 转码进度
reels                       ← 短视频
reel_transcode_jobs         ← 短视频转码任务
reel_variants               ← 短视频的分辨率变体
```

### messaging-service (14 个表)
```
conversations               ← 聊天会话（直聊/群聊）
conversation_members        ← 会话成员和权限
conversation_counters       ← 消息计数缓存
messages                    ← 加密消息内容
message_attachments         ← 消息附件（图像、文件）
message_edit_history        ← 消息编辑历史
message_reactions           ← 消息反应（emoji）
message_recalls             ← 消息撤回记录
message_search_index        ← 全文搜索索引
device_keys                 ← 加密设备密钥
key_exchanges               ← 密钥交换协议
encryption_keys             ← 消息加密密钥
encryption_audit_log        ← 加密操作审计日志
```

### streaming-service (5 个表)
```
streams                     ← 直播流信息
stream_keys                 ← RTMP 推流密钥
stream_metrics              ← 直播流量指标（时间序列）
viewer_sessions             ← 观众会话
quality_levels              ← 视频质量等级
```

### notification-service (5 个表)
```
notifications               ← 站内通知
push_tokens                 ← 设备推送 token
push_delivery_logs          ← 推送投递日志
notification_preferences    ← 通知偏好
notification_dedup          ← 通知去重窗口
```

### outbox (per-service)
```
outbox_events               ← 事件可靠发布（每个服务独立 outbox）
```

### shared (1 个表)
```
schema_migrations_log        ← migration 日志
```

## 关键外键关系（跨服务依赖）

```
auth-service
  ↓ 提供 users 给所有其他服务
  
  ├─→ user-service
  │    ├─ user_permissions.user_id → users.id
  │    ├─ blocked_users.(blocker|blocked)_id → users.id
  │    └─ follows.(follower|followee)_id → users.id
  │
  ├─→ content-service
  │    ├─ posts.user_id → users.id
  │    ├─ comments.user_id → users.id
  │    └─ likes.user_id → users.id
  │
  ├─→ media-service
  │    ├─ uploads.user_id → users.id
  │    └─ videos.creator_id → users.id
  │
  ├─→ messaging-service
  │    ├─ conversations.created_by → users.id
  │    ├─ conversation_members.user_id → users.id
  │    └─ messages.sender_id → users.id
  │
  ├─→ streaming-service
  │    ├─ streams.broadcaster_id → users.id
  │    └─ viewer_sessions.viewer_id → users.id
  │
  └─→ notification-service
       └─ notifications.user_id (no FK; stored as UUID)
```

## 数据大小预测（生产环境）

| 表 | 预期大小 | 增长速度 | 优化策略 |
|---|---|---|---|
| users | 10MB | 慢 | 索引：email, username |
| sessions | 50MB | 快 | 定期清理过期 session |
| posts | 500MB | 快 | 分片（按 user_id） |
| videos | 1GB | 很快 | 外部存储（S3） |
| stream_metrics | 10GB+ | 极快 | 时间序列分区 |
| messages | 100GB+ | 很快 | 归档旧消息 |
| comments, likes | 1TB+ | 极快 | 缓存计数，不直接查询 |

## 立即行动清单

- [ ] 为每个 migration 文件添加 SERVICE 头注释
- [ ] 创建 `/backend/TABLES.md` 列出所有 92 个表的所有权
- [ ] 标记所有跨服务外键（搜索 "REFERENCES users" → 35 个）
- [ ] 在 README 中添加"数据库架构"章节
- [ ] 设定规则：新表必须标记所有权（代码审查强制）

## 何时考虑分库（6+ 个月后）

只有在以下情况下才分库：
- [ ] stream_metrics 表超过 100GB（需要专用 IOPS）
- [ ] messaging-service 消息数超过 1000 亿（需要独立分片）
- [ ] 多个服务竞争 connection pool

分库前：
- 所有外键约束已文档化
- 所有服务都通过 gRPC 查询用户（不直接 SQL）
- 迁移顺序已定义

## 不建议现在做的事

❌ 创建 5 个分离的 RDS 实例（成本增加 5 倍，没有性能收益）
❌ 将表 MOVE 到不同数据库（有 35 个外键依赖，会全部失败）
❌ 创建物理视图隐藏 users（增加复杂性，性能没有收益）

✓ 做好的事：清晰的文档 + 规则 + 测试
