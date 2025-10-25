# Nova Social - 后端功能深度审查报告

**审查时间**: 2025-10-24  
**当前分支**: feature/US3-message-search-fulltext  
**主要框架**: Rust (Actix-web, Axum) + PostgreSQL + ClickHouse + Redis  

---

## 📊 核心数据

- **总Handler函数**: 80个
- **主API路由**: 66条
- **数据库迁移**: 27个 SQL文件
- **测试覆盖**: 4,370行测试代码
- **微服务分离**: user-service (8080) + messaging-service (8085) + search-service

---

## 一、现有功能映射

### 1.1 User-Service (端口 8080) - 核心业务服务

#### 已实现的核心功能模块

| 模块 | 对应Handler | 状态 | 覆盖度 |
|-----|----------|------|-------|
| **认证系统** | auth.rs | ✅ | 完整 |
| **用户管理** | users.rs | ⚠️ | 部分 |
| **关系图** | relationships.rs | ✅ | 完整 |
| **内容创建** | posts.rs | ✅ | 完整 |
| **视频系统** | videos.rs | ✅ | 完整 |
| **动态流** | feed.rs | ✅ | 完整 |
| **故事功能** | stories.rs | ✅ | 完整 |
| **直播系统** | streams.rs | ✅ | 完整 |
| **发现功能** | discover.rs | ⚠️ | 部分 |
| **OAuth集成** | oauth.rs | ✅ | 完整 |
| **密码重置** | password_reset.rs | ⚠️ | 部分 |
| **密钥管理** | jwks.rs | ✅ | 基础 |
| **事件系统** | events.rs | ✅ | 完整 |
| **Reels(短视频)** | reels.rs | ❌ | 已禁用 |

#### 认证和安全 (Auth Module)
- ✅ 邮箱/密码注册
- ✅ 邮箱/密码登录
- ✅ 邮箱验证
- ✅ Token刷新 (Refresh Token)
- ✅ 登出 (Token撤销)
- ✅ 两步验证 (TOTP + 备份码)
- ✅ OAuth2 (Google, Facebook, Apple)
- ✅ 忘记密码 (邮件重置)
- ⚠️ 密码历史验证 (TODO标记)
- ⚠️ 邮件发送服务 (TODO实现)

#### 用户管理 (Users Module)
- ✅ 获取用户信息 (`GET /api/v1/users/{id}`)
- ✅ 获取/更新用户公钥 (E2E加密)
- ❌ 缺失: 用户个人资料编辑 (display_name, bio, avatar, cover)
- ❌ 缺失: 用户隐私设置更新
- ❌ 缺失: 用户账户删除
- ❌ 缺失: 用户搜索

#### 关系图 (Relationships Module)
- ✅ 关注用户 (`POST /api/v1/users/{id}/follow`)
- ✅ 取消关注 (`DELETE /api/v1/users/{id}/follow`)
- ✅ 获取粉丝列表 (`GET /api/v1/users/{id}/followers`)
- ✅ 获取关注列表 (`GET /api/v1/users/{id}/following`)
- ❌ 缺失: 阻止/解除阻止用户 API
- ❌ 缺失: 静音/解除静音用户 API
- ❌ 缺失: 限制/解除限制用户 API 

#### 内容创建 (Posts Module) - 图文发布
- ✅ 创建帖子 (带图片/视频) (`POST /api/v1/posts`)
- ✅ 两阶段上传 (init + complete)
- ✅ 获取单个帖子 (`GET /api/v1/posts/{id}`)
- ❌ **重大缺失**: 没有Comment API (虽然数据库有comment表)
- ❌ **重大缺失**: 没有Like API for Posts (虽然数据库有likes表)
- ❌ **重大缺失**: 没有Share/Repost API
- ❌ **重大缺失**: 没有Save/Bookmark API
- ❌ **重大缺失**: 没有编辑帖子 API
- ❌ **重大缺失**: 没有删除帖子 API
- ❌ 缺失: 批量获取帖子 API (返回列表而非单个)
- ❌ 缺失: 搜索帖子 API

#### 视频系统 (Videos Module) - TikTok风格
- ✅ 视频上传初始化 (`POST /api/v1/videos/upload/init`)
- ✅ 完成上传 (`POST /api/v1/videos/upload/complete`)
- ✅ 创建视频记录 (`POST /api/v1/videos`)
- ✅ 获取视频 (`GET /api/v1/videos/{id}`)
- ✅ 更新视频元数据 (`PATCH /api/v1/videos/{id}`)
- ✅ 删除视频 (`DELETE /api/v1/videos/{id}`)
- ✅ 视频点赞 (`POST /api/v1/videos/{id}/like`)
- ✅ 视频分享 (`POST /api/v1/videos/{id}/share`)
- ✅ 获取相似视频 (`GET /api/v1/videos/{id}/similar`)
- ✅ 获取流媒体清单 (`GET /api/v1/videos/{id}/stream`)
- ✅ 进度跟踪 (`GET /api/v1/videos/{id}/progress`)
- ❌ **重大缺失**: 没有评论 API
- ❌ 缺失: 视频搜索 API (在reels中但已禁用)
- ❌ 缺失: 视频合拍 (Duet) API
- ❌ 缺失: 视频绿屏 (Stitch) API

#### 故事系统 (Stories Module) - 24小时内容
- ✅ 创建故事 (`POST /api/v1/stories`)
- ✅ 列表故事 (`GET /api/v1/stories`)
- ✅ 获取单个故事 (`GET /api/v1/stories/{id}`)
- ✅ 删除故事 (`DELETE /api/v1/stories/{id}`)
- ✅ 更新隐私级别 (`PATCH /api/v1/stories/{id}/privacy`)
- ✅ 获取用户故事 (`GET /api/v1/stories/user/{user_id}`)
- ✅ 亲密好友管理 (add/remove/list)
- ❌ **重大缺失**: 没有故事查看跟踪 API (虽然数据库有story_views表)
- ❌ **重大缺失**: 没有故事反应 API (如emoji反应)

#### 动态流 (Feed Module) - 内容推荐
- ✅ 获取个性化动态 (`GET /api/v1/feed`)
  - 支持2种算法: ClickHouse排序 vs 时间线
  - 可选的Recommendation V2重新排序
  - 支持分页 (cursor-based)
- ✅ 清空动态缓存 (`GET /api/v1/feed/invalidate`)
- ⚠️ **部分实现**: ClickHouse集成存在
- ⚠️ **部分实现**: Neo4j social graph缓存存在
- ❌ 缺失: 按内容类型筛选 (仅文本/仅视频/仅故事)
- ❌ 缺失: 本地化内容 (语言/位置)

#### 直播系统 (Streams Module)
- ✅ 创建直播流 (`POST /api/v1/streams`)
- ✅ 列表直播 (`GET /api/v1/streams`)
- ✅ 搜索直播 (`GET /api/v1/streams/search`)
- ✅ 获取流详情 (`GET /api/v1/streams/{id}`)
- ✅ 加入流 (`POST /api/v1/streams/{id}/join`)
- ✅ 离开流 (`POST /api/v1/streams/{id}/leave`)
- ✅ 流评论 (`GET/POST /api/v1/streams/{id}/comments`)
- ✅ 流分析 (`GET /api/v1/streams/{id}/analytics`)
- ✅ RTMP认证 (`POST /api/v1/streams/rtmp/auth`)
- ✅ RTMP完成 (`POST /api/v1/streams/rtmp/done`)
- ✅ WebSocket聊天 (`WS /ws/streams/{id}/chat`)
- ❌ **缺失**: 流的点赞 API
- ❌ **缺失**: 流的送礼物 API (互动变现)
- ❌ **缺失**: 流的截图/录制 API

#### 发现功能 (Discover Module)
- ✅ 推荐用户 (`GET /api/v1/discover/suggested-users`)
  - 基于Neo4j或Redis缓存
  - 显示互关数量
- ❌ **重大缺失**: 没有发现热门话题 API
- ❌ **重大缺失**: 没有发现热门内容 API
- ❌ **重大缺失**: 没有分类浏览 API
- ❌ **重大缺失**: 没有音乐/声音库 API

#### OAuth & 社交登录
- ✅ 授权流程 (`POST /api/v1/auth/oauth/authorize`)
- ✅ 绑定提供商 (`POST /api/v1/auth/oauth/link`)
- ✅ 解绑提供商 (`DELETE /api/v1/auth/oauth/link/{provider}`)
- ✅ 支持的提供商: Google, Facebook, Apple

### 1.2 Messaging-Service (端口 8085) - 消息系统

#### 消息核心功能
| 端点 | 方法 | 功能 | 状态 |
|-----|------|------|------|
| `/conversations` | POST | 创建对话 | ✅ |
| `/conversations/{id}` | GET | 获取对话 | ✅ |
| `/conversations/{id}/messages` | POST | 发送消息 | ✅ |
| `/conversations/{id}/messages` | GET | 消息历史 | ✅ |
| `/conversations/{id}/messages/search` | GET | 消息搜索 | ✅ |
| `/conversations/{id}/read` | POST | 标记已读 | ✅ |
| `/messages/{id}` | PUT | 编辑消息 | ✅ |
| `/messages/{id}` | DELETE | 删除消息 | ✅ |
| `/ws` | WS | WebSocket连接 | ✅ |

#### 消息功能
- ✅ 一对一对话 (direct)
- ✅ 群组对话 (group)
- ✅ 消息加密 (E2E with NaCl box)
- ✅ 消息查搜索 (全文搜索)
- ✅ 实时消息推送 (WebSocket)
- ✅ 消息编辑
- ✅ 消息软删除
- ✅ 未读计数
- ✅ 离线队列 (消息存储待传递)
- ❌ **缺失**: 消息已送达状态
- ❌ **缺失**: 消息已读回执
- ❌ **缺失**: 输入状态指示 (typing...)
- ❌ **缺失**: 语音消息 API
- ❌ **缺失**: 文件/图片消息 API (只支持纯文本)
- ❌ **缺失**: 消息反应 (emoji reactions)
- ❌ **缺失**: 消息引用/回复功能
- ❌ **缺失**: 对话头像/描述 API
- ❌ **缺失**: 成员添加/移除 API
- ❌ **缺失**: 对话静音 API
- ❌ **缺失**: 对话分组 API

### 1.3 Search-Service (独立服务)

#### 搜索功能
- ⚠️ **框架存在但功能不完整**
  - 仅实现了基础的用户/帖子/话题搜索框架
  - 返回JSON格式的搜索结果
- ❌ **缺失**: Elasticsearch集成 (代码中引用但未实现)
- ❌ **缺失**: 实时搜索索引更新
- ❌ **缺失**: 搜索过滤器 (日期范围、热度等)
- ❌ **缺失**: 搜索拼写纠正
- ❌ **缺失**: 自动补全 API

---

## 二、数据库功能分析

### 2.1 现有数据表 (27个迁移)

#### 用户和认证 (Migration 001-006, 010, 025)
| 表 | 目的 | 索引 | 触发器 |
|----|------|------|-------|
| `users` | 用户账户 | 5个 | 1个 (updated_at) |
| `sessions` | 活动会话 | 4个 | 无 |
| `refresh_tokens` | 刷新令牌 | 5个 | 无 |
| `email_verifications` | 邮件验证 | 3个 | 无 |
| `two_factor_secrets` | 2FA密钥 | 2个 | 无 |
| `backup_codes` | 备份码 | 1个 | 无 |
| `auth_logs` | 审计日志 | 2个 | 无 |
| `jwt_signing_keys` | JWT签名密钥 | 1个 | 无 |

#### 内容和社交 (Migration 003-004)
| 表 | 目的 | 索引 | 触发器 |
|----|------|------|-------|
| `posts` | 用户发布的内容 | 4个 | 2个 |
| `post_images` | 图片变体 (thumbnail/medium/original) | 3个 | 1个 |
| `post_metadata` | 点赞/评论/浏览计数 | 2个 | 1个 |
| `upload_sessions` | 上传跟踪 | 4个 | 无 |
| `follows` | 用户关注关系 | 3个 | 1个 (触发更新follower_count) |
| `likes` | 帖子点赞 | 3个 | 1个 (触发计数) |
| `comments` | 帖子评论 (支持嵌套) | 4个 | 1个 (触发计数) |
| `social_metadata` | 社交指标 (follow/like/comment/share) | 2个 | 无 |

#### 故事系统 (Migration 019)
| 表 | 目的 | 索引 | 触发器 |
|----|------|------|-------|
| `stories` | 24小时内容 | 3个 | 无 |
| `story_views` | 故事查看 | 无 (2字段PK) | 无 |
| `story_close_friends` | 亲密好友列表 | 无 (2字段PK) | 无 |

#### 视频系统 (Migration 007, 011, 020-022)
| 表 | 目的 | 索引 | 触发器 |
|----|------|------|-------|
| `videos` | 视频元数据 | 4个 | 1个 (updated_at) |
| `video_encodings` | 视频编码状态 | 2个 | 无 |
| `video_embeddings` | pgvector 相似度搜索 | 1个 (HNSW索引) | 无 |
| `video_engagement` | 点赞/分享计数 | 2个 | 无 |
| `video_pipeline_state` | 处理状态跟踪 | 1个 | 无 |

#### 直播系统 (Migration 012-017)
| 表 | 目的 | 索引 | 触发器 |
|----|------|------|-------|
| `streams` | 直播流信息 | 2个 | 无 |
| `stream_keys` | RTMP流密钥 | 2个 | 无 |
| `stream_metrics` | 直播统计 | 1个 | 无 |
| `stream_viewers` | 观看者会话 | 2个 | 无 |
| `stream_quality_levels` | 清晰度配置 | 无 | 无 |

#### 消息系统 (Migration 018, 023)
| 表 | 目的 | 索引 | 触发器 |
|----|------|------|-------|
| `conversations` | 对话容器 | 2个 | 1个 (updated_at) |
| `conversation_members` | 对话成员 | 3个 | 无 |
| `messages` | 加密消息 | 3个 | 1个 (timestamp) |
| `message_search_index` | 消息搜索索引 | 3个 | 无 |

#### 隐私和其他 (Migration 024, 026-027)
| 表 | 目的 | 索引 | 触发器 |
|----|------|------|-------|
| `privacy_settings` | 用户隐私配置 | 1个 | 无 |
| `post_video_association` | 帖子-视频关联 | 2个 | 无 |

### 2.2 关键缺失的数据表

#### 1. 没有Bookmark/Save表 
```
需要表: saved_posts, saved_videos, saved_streams
对应功能: "我的收藏" 功能
```

#### 2. 没有Block表
```
需要表: blocked_users
包含字段: blocker_id, blocked_id, created_at
```

#### 3. 没有Notification表
```
需要表: notifications
包含字段: user_id, actor_id, type, target_id, is_read, created_at
```

#### 4. 没有Report/举报表
```
需要表: reports
包含字段: reporter_id, reported_id/post_id, reason, status, created_at
```

#### 5. 没有Hashtag表 (虽然posts中有JSON字段)
```
需要表: hashtags, post_hashtags, video_hashtags
用于: 点击话题 → 查看相关内容
```

#### 6. 没有Trending表
```
需要表: trending_hashtags, trending_sounds, trending_creators
包含字段: tag/sound, count, timestamp, region
```

#### 7. 没有Message Reaction表
```
需要表: message_reactions
对应功能: 消息emoji反应
```

#### 8. 没有Content Moderation表
```
需要表: content_flags, flagged_content
对应功能: 内容审核和合规
```

---

## 三、API完整性分析

### 3.1 缺失的关键API端点

#### A. 帖子相关 (CRITICAL - 社交平台核心)
```
缺失的GET /api/v1/posts
  - 应该返回用户的帖子列表 (个人资料)
  - 应该支持分页

缺失的POST /api/v1/posts/{id}/like
  - 给帖子点赞

缺失的DELETE /api/v1/posts/{id}/like
  - 取消点赞

缺失的POST /api/v1/posts/{id}/comments
  - 发表评论

缺失的GET /api/v1/posts/{id}/comments
  - 获取评论列表 (虽然数据库有comments表)

缺失的PATCH /api/v1/posts/{id}/comments/{comment_id}
  - 编辑评论

缺失的DELETE /api/v1/posts/{id}/comments/{comment_id}
  - 删除评论

缺失的DELETE /api/v1/posts/{id}
  - 删除帖子

缺失的PATCH /api/v1/posts/{id}
  - 编辑帖子 (如更改标题)

缺失的POST /api/v1/posts/{id}/save
  - 保存帖子到"我的收藏"

缺失的DELETE /api/v1/posts/{id}/save
  - 移除收藏

缺失的POST /api/v1/posts/{id}/report
  - 举报帖子
```

#### B. 用户管理 (HIGH - 个人资料完整性)
```
缺失的PATCH /api/v1/users/me
  - 更新用户信息 (display_name, bio, avatar, cover_photo, location, etc.)

缺失的GET /api/v1/users/me
  - 获取当前用户的完整信息

缺失的DELETE /api/v1/users/me
  - 账户注销

缺失的POST /api/v1/users/{id}/block
  - 阻止用户

缺失的DELETE /api/v1/users/{id}/block
  - 解除阻止

缺失的POST /api/v1/users/{id}/mute
  - 静音用户 (隐藏其内容但不取消关注)

缺失的DELETE /api/v1/users/{id}/mute
  - 解除静音

缺失的GET /api/v1/users/{id}/posts
  - 获取用户的所有帖子 (个人资料页)

缺失的GET /api/v1/users/{id}/videos
  - 获取用户的所有视频

缺失的GET /api/v1/users/search
  - 搜索用户
```

#### C. 发现和浏览 (HIGH - 内容发现)
```
缺失的GET /api/v1/discover/trending/hashtags
  - 热门话题

缺失的GET /api/v1/discover/trending/sounds
  - 热门音乐

缺失的GET /api/v1/discover/trending/creators
  - 热门创作者

缺失的GET /api/v1/discover/hashtag/{tag}
  - 查看话题下的内容

缺失的GET /api/v1/discover/sound/{sound_id}
  - 使用该音乐的视频

缺失的GET /api/v1/discover/categories
  - 内容分类浏览 (如: 舞蹈、搞笑、教育等)

缺失的GET /api/v1/discover/for-you
  - 推荐内容 (与/feed可能不同)
```

#### D. 通知系统 (MEDIUM - 用户参与度)
```
缺失的GET /api/v1/notifications
  - 获取通知列表

缺失的POST /api/v1/notifications/{id}/read
  - 标记通知为已读

缺失的DELETE /api/v1/notifications/{id}
  - 删除通知

缺失的PATCH /api/v1/notifications/settings
  - 通知偏好设置
```

#### E. 内容审核和举报 (MEDIUM - 合规)
```
缺失的POST /api/v1/reports
  - 举报内容

缺失的GET /api/v1/reports/{id}
  - 查看举报状态
```

#### F. 视频高级功能 (MEDIUM - 特色功能)
```
缺失的POST /api/v1/videos/{id}/duet
  - 视频合拍

缺失的POST /api/v1/videos/{id}/stitch
  - 视频拼贴

缺失的POST /api/v1/videos/{id}/comment
  - 视频评论 (不同于Like)

缺失的GET /api/v1/videos/{id}/comments
  - 获取视频评论列表
```

#### G. 直播高级功能 (MEDIUM)
```
缺失的POST /api/v1/streams/{id}/gift
  - 送礼物

缺失的POST /api/v1/streams/{id}/follow
  - 关注直播主

缺失的POST /api/v1/streams/{id}/like
  - 给直播点赞
```

#### H. 消息高级功能 (MEDIUM)
```
缺失的POST /api/v1/conversations/{id}/members
  - 添加成员到群组

缺失的DELETE /api/v1/conversations/{id}/members/{user_id}
  - 从群组移除成员

缺失的PATCH /api/v1/conversations/{id}
  - 更新群组信息 (名称、头像等)

缺失的POST /api/v1/conversations/{id}/mute
  - 对话静音

缺失的POST /api/v1/messages/{id}/react
  - 消息emoji反应
```

### 3.2 API验证和错误处理问题

#### 问题1: 帖子创建缺少验证
```rust
// posts.rs - 创建帖子
// ❌ 缺失: caption长度验证 (定义了MAX_CAPTION_LENGTH = 2200但未验证)
// ❌ 缺失: 空帖子检查 (必须至少有caption或image_ids或video_ids)
// ✅ 有: 文件大小验证
```

#### 问题2: 用户创建缺少速率限制
```rust
// auth.rs - 注册
// ❌ 缺失: 防暴力破解 (同一IP多次失败注册)
// ❌ 缺失: 邮箱重复检查
// ✅ 有: 用户名格式验证
```

#### 问题3: 消息发送缺少权限检查完整性
```rust
// messages.rs - 发送消息
// ✅ 有: 成员身份检查
// ❌ 缺失: 被屏蔽用户检查
// ❌ 缺失: 对话成员静音检查
```

#### 问题4: 错误响应格式不一致
```
有些使用: {"error": "...", "details": "..."}
有些使用: {"error": "..."}
有些使用: serde_json::json!({...})
```

---

## 四、数据一致性问题

### 4.1 跨服务数据同步问题

#### 问题1: 消息服务和用户服务分离
```
现象:
- messaging-service (port 8085) 独立运行
- 用户关系在user-service中
- 用户信息更新时，messaging-service无法实时获取

影响:
- 用户更新display_name，消息中显示的还是旧名字
- 用户删除账户，消息无法实时清理

解决方案需要:
- 订阅用户变更事件 (Kafka)
- 异步同步用户信息缓存
```

#### 问题2: 社交元数据和实际数据不同步
```
数据库有两套计数:
1. post_metadata.like_count (触发器维护)
2. likes表的实际行数

问题:
- 触发器失败但transaction成功，造成不一致
- 并发更新可能导致计数跳跃

现象:
- 显示99个赞，但实际likes表只有98条

修复需要:
- 定期对账任务
- 幂等的触发器逻辑
```

#### 问题3: 视频搜索索引和实际视频不同步
```
有video_embeddings表用于pgvector搜索
但没有:
- 何时触发embedding生成的明确流程
- embedding重建机制
- 搜索结果验证 (是否video_id存在)
```

### 4.2 缺失的对账机制
```
需要实现:
1. 点赞计数核对 (COUNT(likes) vs post_metadata.like_count)
2. 关注计数核对 (COUNT(follows where following_id=X) vs users.follower_count)
3. 评论计数核对 (COUNT(comments) vs post_metadata.comment_count)
4. 消息送达验证 (确保offline_queue中的消息最终被送达)

定期运行:
- 每日凌晨运行对账脚本
- 不一致时自动修复或发出告警
```

---

## 五、性能和扩展性问题

### 5.1 N+1查询问题

#### 问题1: 获取动态时的N+1
```rust
// 假设get_feed返回100个post_ids
// 然后为每个post:
//   - 查询post详情
//   - 查询post_metadata (like_count, comment_count)
//   - 查询creator信息
//   - 查询当前用户是否点赞过
//   - 查询当前用户是否收藏过

// 结果: 1 + (100 * 5) = 501次查询！

解决方案:
- 使用ClickHouse JOIN查询获取完整的post数据
- 使用Redis缓存热点用户信息
```

#### 问题2: 获取关注者时的N+1
```rust
// relationships.rs - get_followers
// 获取follower_id列表后，为每个user查询其信息

解决方案:
- 使用IN子句的单次查询
- 缓存follower列表 (带过期时间)
```

### 5.2 缺失的索引

#### posts表缺失的索引
```sql
-- 缺失: 通过content_type和created_at的复合索引
-- 影响: 按内容类型过滤动态会全表扫描
CREATE INDEX idx_posts_content_type_created ON posts(content_type, created_at DESC) 
WHERE soft_delete IS NULL;

-- 缺失: 通过status和user_id的复合索引
-- 影响: 查询用户发布中的帖子时慢
CREATE INDEX idx_posts_user_status ON posts(user_id, status);
```

#### videos表缺失的索引
```sql
-- 缺失: 通过visibility和created_at
-- 影响: 首页推荐视频查询慢
CREATE INDEX idx_videos_visibility_created ON videos(visibility, created_at DESC)
WHERE deleted_at IS NULL;

-- 缺失: 通过hashtag (GIN索引)
-- 影响: 搜索视频by hashtag慢
CREATE INDEX idx_videos_hashtags ON videos USING GIN(hashtags);
```

#### conversations表缺失的索引
```sql
-- 缺失: 通过最后消息时间的索引
-- 影响: 列表对话时排序慢
CREATE INDEX idx_conversations_last_message ON conversations(updated_at DESC);
```

### 5.3 缺失的缓存

#### 热点数据未缓存
```
1. 用户公开信息 (avatar, username, bio)
   - 每次评论都要查询
   - 应该缓存30分钟

2. 粉丝/关注列表
   - 频繁查询但变化不频繁
   - 应该缓存1小时，用户关注/取消关注时清除

3. 热点帖子 (热赞、热评)
   - 应该缓存5分钟

4. 视频元数据 (duration, thumbnail_url)
   - 应该缓存1小时
```

#### Redis使用不足
```
现有:
- feed_cache (120秒)
- suggested_users缓存
- email_verification缓存

缺失:
- 点赞关系缓存 (布隆过滤器检查是否已点赞)
- 关注关系缓存
- 用户信息缓存
- 流行话题缓存
```

### 5.4 长连接和实时性问题

#### WebSocket可靠性
```
现有:
- Stream chat WebSocket
- Messaging WebSocket

问题:
1. 没有heartbeat/ping-pong心跳检测
2. 连接断开时，消费者不知道 (可能导致消息堆积)
3. 没有自动重连机制

需要:
- 实现心跳协议
- 连接断开时的优雅降级
- 客户端重连指数退避
```

---

## 六、安全性问题

### 6.1 权限检查问题

#### 问题1: 帖子操作权限不完整
```
✅ 有: 获取帖子 (public check)
❌ 缺失: 删除帖子只检查owner
❌ 缺失: 编辑帖子 (功能本身就缺失)
❌ 缺失: 删除评论时检查是否为owner或post owner
```

#### 问题2: 消息权限检查不完整
```rust
// messaging-service - send_message
✅ 有: 检查sender是否是成员
❌ 缺失: 检查receiver是否被发送者屏蔽
❌ 缺失: 检查sender是否被receiver屏蔽
❌ 缺失: 检查对话是否被禁用
```

#### 问题3: 隐私权限检查
```
posts/videos:
❌ 缺失: 私有账户的内容权限检查
❌ 缺失: 被屏蔽用户不应该看到内容

stories:
✅ 有: privacy_level检查 (public/followers/close_friends)
❌ 缺失: 被屏蔽用户看不到故事
❌ 缺失: 私有账户的故事限制
```

### 6.2 输入验证不完整

#### 问题1: SQL注入风险
```
// 使用了sqlx所以基本安全
✅ 参数化查询

// 但有风险的是:
❌ 搜索端点可能有模糊匹配注入
❌ 排序参数 (如果使用user输入直接构建SQL)
```

#### 问题2: 业务逻辑验证
```
// posts.rs - create_post
// ✅ 文件大小验证
// ❌ caption验证不足
//    - 没有检查最小长度 (可以提交空caption + 无image)
//    - 没有检查禁止词汇
//    - 没有检查URL数量 (防止垃圾链接)

// ❌ image_ids/video_ids验证
//    - 没有检查数量上限
//    - 没有验证资源所有权 (用户A可能上传B的视频?)
```

### 6.3 速率限制

#### 问题1: API没有速率限制
```
高风险的API:
- POST /auth/register (应该限制: 5次/IP/小时)
- POST /auth/login (应该限制: 10次/IP/小时)
- POST /api/v1/posts (应该限制: 30次/用户/天)
- POST /api/v1/messages (应该限制: 100次/用户/分钟)
- POST /api/v1/streams/rtmp/auth (应该限制: 防止暴力破解)

现状:
❌ 没有全局速率限制
❌ 没有per-user速率限制
❌ 没有per-IP速率限制
```

### 6.4 身份验证问题

#### 问题1: JWT处理
```
✅ 有: JWT签名和验证
✅ 有: Token轮换机制
✅ 有: Token撤销 (黑名单)

❌ 缺失: JWT过期检查的一致性
❌ 缺失: 刷新token的限制
   - 应该限制同一用户只能有N个有效的refresh_token
   - 否则用户可能有数千个token同时有效
```

#### 问题2: 会话管理
```
❌ 没有会话表的清理 (过期的session会永久存储)
❌ 没有并发会话限制 (用户可以同时在1000台设备上登录)
❌ 没有新登录通知 (用户账号被盗窃无法察觉)
```

### 6.5 HTTPS和传输安全

```
❌ 代码中没有强制HTTPS的配置
❌ CORS配置允许任何origin (allow_any_origin)
   - 这是配置错误，应该只允许特定的frontend域名
```

---

## 七、测试覆盖分析

### 7.1 已有的测试

| 测试文件 | 行数 | 覆盖范围 |
|---------|-----|---------|
| 2fa_test.rs | 368 | 两步验证 |
| auth_password_reset_test.rs | 464 | 认证和密码重置 |
| feed_ranking_test.rs | 515 | 动态排序 |
| image_processing_integration_test.rs | 288 | 图片处理 |
| job_test.rs | 165 | 后台任务队列 |
| messaging_e2e_test.rs | 459 | 消息系统端到端 |
| oauth_test.rs | 702 | OAuth认证 |
| oauth_token_verification_test.rs | 256 | OAuth令牌验证 |
| posts_test.rs | 476 | 帖子创建和管理 |
| recommendation_v2_e2e_test.rs | 129 | 推荐系统 |
| stories_videos_integration_test.rs | 180 | 故事和视频 |
| streaming_integration_test.rs | 368 | 直播系统 |

**总计**: 4,370行测试代码，12个测试文件

### 7.2 缺失的测试

#### 高优先级缺失测试
```
❌ 没有帖子点赞API测试 (API本身就不存在)
❌ 没有评论API测试 (API本身就不存在)
❌ 没有用户资料编辑测试
❌ 没有关注/粉丝列表测试
❌ 没有权限检查测试
❌ 没有速率限制测试
❌ 没有并发上传测试 (可能造成重复计费)
❌ 没有长连接断线恢复测试
```

#### 中优先级缺失测试
```
❌ 没有搜索功能测试
❌ 没有发现功能测试
❌ 没有视频转码进度测试
❌ 没有消息离线队列测试
❌ 没有ClickHouse同步测试
❌ 没有Neo4j图查询测试
```

#### 安全性测试缺失
```
❌ 没有SQL注入测试
❌ 没有CSRF防护测试
❌ 没有XSS防护测试
❌ 没有认证绕过测试
❌ 没有权限提升测试
```

---

## 八、架构问题

### 8.1 微服务分离的问题

#### 问题1: 数据库共享
```
现状:
- user-service和messaging-service都访问同一个PostgreSQL
- 没有API边界隔离
- 直接的数据库访问导致紧耦合

影响:
- 消息服务无法独立扩展
- 用户表修改会影响消息服务
```

#### 问题2: 事件驱动不完整
```
现有:
- Kafka producer用于发布事件
- Events consumer消费到ClickHouse

缺失:
- 没有用户信息变更事件 (用户名改变, 头像改变)
- 没有内容删除事件 (删除帖子时，应该发出事件)
- 没有权限变更事件 (屏蔽用户时应该通知消息服务)

导致:
- 消息服务无法实时更新用户信息
```

### 8.2 存储选择问题

#### 问题1: ClickHouse但查询不完整
```
使用ClickHouse用于:
- 动态排序
- 事件分析

但:
❌ 搜索功能没有使用ClickHouse (应该用于全文搜索)
❌ 没有Elasticsearch (应该用于实时搜索)
❌ 没有使用ClickHouse做热点数据统计

导致:
- 搜索性能差
- 实时排序需要ClickHouse但搜索不支持
```

#### 问题2: Milvus向量数据库
```
为视频相似度搜索创建了:
- video_embeddings表 (pgvector)
- Milvus collection (向量存储)

问题:
- 两个系统存储相同数据，维护成本高
- 没有清楚的同步机制

选择:
- 要么用pgvector (性能可能不足)
- 要么用Milvus (但要保证数据同步)
```

### 8.3 缓存策略不完整

#### 问题1: 缓存失效问题
```
如果用户A的信息改变:
- 缓存键: nova:cache:user:{user_id}:info
- 但没有清除相关的:
  - nova:cache:post:{post_id}:creator_info
  - nova:cache:comment:{comment_id}:author_info

导致:
- 用户修改头像，旧内容仍显示旧头像
```

#### 问题2: 缓存预热不足
```
现有:
- feed_cache预热机制

缺失:
- 用户信息预热
- 粉丝列表预热
- 热门内容预热
- 推荐内容预热

导致:
- 冷启动时响应慢
```

---

## 九、运维和监控问题

### 9.1 健康检查不完整

```rust
// handlers/health.rs

✅ 有: 基础健康检查 (HTTP 200)
✅ 有: Readiness检查 (数据库连接)
✅ 有: Liveness检查 (服务是否活着)

❌ 缺失: Redis连接检查 (TODO标记)
❌ 缺失: ClickHouse连接检查 (TODO标记)
❌ 缺失: Kafka broker检查 (TODO标记)
❌ 缺失: Neo4j连接检查
❌ 缺失: 消息服务依赖检查
❌ 缺失: Milvus连接检查
```

### 9.2 指标和监控

```
✅ 有: Prometheus metrics端点 (/metrics)
✅ 有: 自定义指标 (social_follow_event, etc.)

❌ 缺失: 数据库查询性能指标
❌ 缺失: API延迟分布
❌ 缺失: 缓存命中率
❌ 缺失: WebSocket连接数
❌ 缺失: 消息队列延迟
❌ 缺失: 错误率告警
```

### 9.3 日志记录

```
✅ 有: Tracing日志
✅ 有: 结构化日志 (JSON)

❌ 缺失: 审计日志 (谁修改了什么)
❌ 缺失: 敏感操作日志 (删除内容、屏蔽用户等)
❌ 缺失: API调用日志 (用于调试)
```

---

## 十、优先级缺失功能清单

### 🔴 CRITICAL - 影响核心功能

| # | 功能 | API | DB | 优先级原因 |
|---|-----|-----|----|----------|
| 1 | 评论系统 | POST/GET/DELETE /posts/{id}/comments | comments表存在 | 社交媒体核心，缺少会导致用户无法互动 |
| 2 | 帖子点赞 | POST/DELETE /posts/{id}/like | likes表存在 | 无法点赞会导致engagement极低 |
| 3 | 帖子列表 | GET /posts (with filters) | posts表 | 用户无法浏览自己的帖子 |
| 4 | 用户资料编辑 | PATCH /users/me | users表 | 新用户无法完善资料 |
| 5 | 个人资料页 | GET /users/{id}/posts | posts表 | 无法查看他人动态 |
| 6 | 搜索功能 | GET /search /* | - | 无法发现内容 |
| 7 | 消息功能完整性 | 群组管理、反应、文件 | conversations, messages表 | 现有消息功能不完整 |

### 🟠 HIGH - 重要功能缺失

| # | 功能 | API | DB | 备注 |
|---|-----|-----|----|------|
| 1 | 保存/收藏 | POST/DELETE /posts/{id}/save | saved_posts表 | 用户收藏管理 |
| 2 | 屏蔽用户 | POST/DELETE /users/{id}/block | blocked_users表 | 隐私和安全 |
| 3 | 通知系统 | GET /notifications | notifications表 | 用户参与度 |
| 4 | 热门话题 | GET /discover/trending/hashtags | hashtags表 | 发现功能 |
| 5 | 举报系统 | POST /reports | reports表 | 内容审核 |
| 6 | 视频评论 | POST/GET /videos/{id}/comments | - | 视频互动 |
| 7 | 消息反应 | POST /messages/{id}/react | message_reactions表 | 消息互动 |
| 8 | 速率限制 | 全局中间件 | - | 安全防护 |

### 🟡 MEDIUM - 增强功能

| # | 功能 | API | 备注 |
|---|-----|-----|----|
| 1 | 视频合拍(Duet) | POST /videos/{id}/duet | TikTok特色 |
| 2 | 消息输入状态 | WS message | 实时通信增强 |
| 3 | 推荐改进 | ML排序 | 已有框架，可优化 |
| 4 | 音乐库 | GET /sounds | 视频创作功能 |
| 5 | 直播礼物 | POST /streams/{id}/gift | 变现功能 |
| 6 | 分析统计 | GET /analytics | 创作者工具 |

### 🟢 LOW - 优化项

| # | 功能 | 优先级原因 |
|---|-----|----------|
| 1 | 搜索拼写纠正 | 增强搜索体验 |
| 2 | 内容本地化 | 国际化支持 |
| 3 | 数据导出 | GDPR合规 |
| 4 | 活动导入 | 数据迁移 |

---

## 十一、建议修复清单

### Phase 1: 启动关键功能 (1-2周)

```
1. 实现评论API
   - POST /api/v1/posts/{id}/comments (发表)
   - GET /api/v1/posts/{id}/comments (列表)
   - PATCH /api/v1/posts/{id}/comments/{comment_id} (编辑)
   - DELETE /api/v1/posts/{id}/comments/{comment_id} (删除)
   
2. 实现帖子点赞API
   - POST /api/v1/posts/{id}/like
   - DELETE /api/v1/posts/{id}/like
   - GET /api/v1/posts/{id}/likes (列表)

3. 实现个人资料编辑
   - PATCH /api/v1/users/me (display_name, bio, avatar)

4. 修复速率限制
   - 在中间件添加全局速率限制
   - 注册和登录端点需要严格限制
```

### Phase 2: 内容发现 (1周)

```
1. 完善搜索功能
   - 实现Elasticsearch集成
   - 搜索用户、帖子、话题
   - 添加自动补全

2. 实现热门话题API
   - GET /api/v1/discover/trending/hashtags

3. 实现话题浏览API
   - GET /api/v1/discover/hashtag/{tag}
```

### Phase 3: 隐私和安全 (1周)

```
1. 屏蔽系统
   - POST /api/v1/users/{id}/block
   - DELETE /api/v1/users/{id}/block
   - 在查询动态时过滤屏蔽用户

2. 权限检查加固
   - 所有内容操作都检查权限
   - 私有账户限制

3. 举报系统
   - POST /api/v1/reports
   - 集成内容审核
```

### Phase 4: 通知系统 (1周)

```
1. 实现通知表
   - POST /api/v1/notifications
   - GET /api/v1/notifications

2. 触发器
   - 收到消息时创建通知
   - 帖子被赞时创建通知
   - 有人评论时创建通知
```

### Phase 5: 性能优化 (2周)

```
1. 添加缺失的数据库索引
2. 实现N+1查询修复
3. 完善缓存策略
4. 添加健康检查
```

---

## 十二、技术债清单

| 项目 | 优先级 | 工作量 | 风险 |
|-----|--------|--------|------|
| 修复跨服务数据一致性 | HIGH | 5天 | 中 |
| 添加权限检查 | HIGH | 3天 | 高 |
| 实现速率限制 | HIGH | 2天 | 低 |
| 添加缺失索引 | MEDIUM | 1天 | 低 |
| 修复N+1查询 | MEDIUM | 3天 | 中 |
| 完善错误处理 | MEDIUM | 2天 | 低 |
| 添加安全测试 | MEDIUM | 4天 | 低 |
| 修复消息功能 | LOW | 3天 | 中 |
| 迁移到Elasticsearch | LOW | 7天 | 高 |

---

## 十三、关键数据

### 代码规模
- **总行数**: ~50,000行Rust代码
- **Handler函数**: 80个
- **数据库表**: 35个
- **测试代码**: 4,370行

### 服务架构
```
Frontend (Web/Mobile)
        ↓
  API Gateway / Load Balancer
        ↓
    ┌─────────────────────────────────────┐
    │     User-Service (8080)              │
    │  - Auth, Users, Posts, Videos,      │
    │  - Feed, Stories, Streams, Discover │
    └─────────────────────────────────────┘
        ↓
  ┌─────────────────┬──────────────────┐
  ↓                 ↓                  ↓
PostgreSQL      Redis            ClickHouse
(OLTP)        (Cache)         (Analytics)
              
  Messaging-Service (8085)
  - Conversations, Messages
  - WebSocket, Encryption
  
  Search-Service
  - Elasticsearch (planned)
  - Full-text search
```

### 依赖关键库
- **Web框架**: Actix-web, Axum
- **数据库**: sqlx, sqlx-postgres
- **搜索**: Milvus (向量), pgvector
- **消息队列**: Kafka, Redis
- **缓存**: Redis
- **分析**: ClickHouse
- **图数据库**: Neo4j
- **加密**: NaCl, JWT

---

## 总结

### 当前状态
Nova Social已经实现了一个相对完整的社交媒体后端框架，包括用户认证、内容创建、直播系统和消息传递。但从实际可用性角度，**缺少了核心的社交互动功能**。

### 最严重的问题
1. **没有评论API** - 社交媒体的核心互动方式完全缺失
2. **没有帖子点赞API** - 参与度测量无法进行
3. **用户资料不完整** - 用户无法编辑个人信息
4. **没有用户搜索** - 内容发现困难
5. **权限检查不完整** - 存在安全隐患

### 建议优先级
如果要让这个系统能真正运营：
1. **必须** (这周): 评论、点赞、用户资料编辑
2. **必须** (第二周): 搜索、发现、权限修复
3. **应该** (第三周): 通知、屏蔽、举报
4. **优化** (之后): 性能、缓存、分析

### 整体设计评价
从架构角度：✅ 设计合理，微服务分离恰当，使用了现代技术栈
从完整性角度：❌ 核心功能不完整，缺少太多用户交互功能
从质量角度：⚠️ 有测试但不完整，权限检查不足，缺少安全防护
