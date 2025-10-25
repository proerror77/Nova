# Database Migration Cleanup Plan

**Date**: October 25, 2025
**Status**: Analysis Complete
**Action**: 需要用户确认前再执行

## 问题分析

### 1. 编号冲突（严重）

**4个文件都想要编号031**：
```
031_experiments_schema.sql          ← A/B Testing Framework (完整)
031_fix_messages_schema_consistency.sql  ← 搜索索引修复 (我们刚创建)
031_resumable_uploads.sql           ← 可恢复上传 (功能性)
031_trending_system.sql             ← 趋势系统 (发现功能)
```

**影响**：
- ❌ 任何迁移运行系统都会失败或跳过某些迁移
- ❌ 生产数据库状态会不一致
- ❌ 难以追踪哪些迁移已应用

### 2. 编号间隙

```
001-012, 013-017, 018-030
031 (4个文件冲突)
032, 040 (跳过了033-039)
```

### 3. 非SQL文件混入迁移目录

```
027_EXECUTIVE_SUMMARY.md        ❌ 应该移到 docs/ 或删除
027_POST_VIDEO_ASSOCIATION_README.md  ❌ 应该移到 docs/
027_erd_diagram.md              ❌ 应该移到 docs/diagrams/
```

### 4. 重复定义

```
040_resumable_uploads.sql       ← 与 031_resumable_uploads.sql 重复？
```

---

## 核心表分析

### 必须保留（核心功能）

| Category | Tables |
|----------|--------|
| **Auth** | users, sessions, refresh_tokens, password_resets, email_verifications |
| **2FA** | two_fa_backup_codes, two_fa_sessions |
| **Social** | follows, likes, comments |
| **Posts** | posts, post_images, post_metadata, post_videos |
| **Messaging** | conversations, conversation_members, messages, message_attachments, message_reactions, message_search_index |
| **Video** | videos, video_embeddings, video_pipeline_state, video_engagement |
| **Streaming** | streams, stream_keys, stream_metrics, viewer_sessions |
| **Stories** | stories, story_views, story_close_friends |
| **Auth Logs** | auth_logs |

### 可选/功能性（可保留但非核心）

| Feature | Tables | Status |
|---------|--------|--------|
| **A/B Testing** | experiments, experiment_assignments, experiment_variants, experiment_metrics, experiment_results_cache | ✅ Complete |
| **Resumable Upload** | uploads, upload_chunks, upload_sessions | ✅ Complete |
| **Trending** | trending_scores, trending_metadata | ✅ Complete |
| **Webhook** | video_webhooks, webhook_deliveries | ✅ Complete |

### 不应该有的

| Table | Issue |
|-------|-------|
| quality_levels | Seems to be related to video streaming, might be referenced by streams or video_pipeline_state |
| social_metadata | Generic metadata table, unclear purpose |

---

## 清理策略

### Phase 1: 重新编号冲突的031迁移（必须做）

按照项目优先级重新编号：

```
当前状态                          目标状态
─────────────────────────────────────────────────

031_experiments_schema.sql        → 033_experiments_schema.sql (A/B测试)
031_fix_messages_schema_consistency.sql → 031_fix_messages_schema_consistency.sql (保留)
031_resumable_uploads.sql         → 034_resumable_uploads.sql (上传)
031_trending_system.sql           → 035_trending_system.sql (发现)
040_resumable_uploads.sql         → 删除 (重复)
```

**理由**：
1. 031_fix_messages 保留因为搜索功能是当前项目的一部分
2. 其他按创建时间顺序递增
3. 消除间隙，保持连续性

### Phase 2: 移动非SQL文件（可选但推荐）

```
迁移目录                    → 文档目录
─────────────────────────────────────────────
027_EXECUTIVE_SUMMARY.md   → docs/migration_027_summary.md
027_POST_VIDEO_ASSOCIATION_README.md → docs/database/post_video_association.md
027_erd_diagram.md → docs/diagrams/erd_2025_01_15.md
```

### Phase 3: 文档化（推荐）

创建 `MIGRATIONS.md` 文档说明：
- 每个迁移的目的
- 哪些迁移是核心的，哪些是可选的
- 升级路径（如何跳过可选迁移）

---

## 建议的迁移编号方案

### 最终序列（Phase 1 + 2后）

```
核心认证和用户
001_initial_schema.sql
002_add_auth_logs.sql
005_add_deleted_at_to_users.sql
006_add_two_factor_auth.sql
010_jwt_key_rotation.sql
025_jwt_signing_keys_pg.sql

社交功能
003_posts_schema.sql
004_social_graph_schema.sql

消息和协作
018_messaging_schema.sql
019_stories_schema.sql
023_message_search_index.sql
029_message_reactions.sql
031_fix_messages_schema_consistency.sql ✅ (搜索修复)

视频
007_video_schema_postgres.sql
011_videos_table.sql
020_video_pipeline_state.sql
021_video_embeddings_pgvector.sql
022_video_schema_postgres_fix.sql
028_add_user_profile_fields.sql
032_transcoding_progress_enhancements.sql

流媒体
012_streaming_extensions.sql
013_streaming_stream_table.sql
014_streaming_stream_key_table.sql
015_streaming_viewer_session_table.sql
016_streaming_metrics_table.sql
017_streaming_quality_level_table.sql

隐私和优化
024_add_privacy_mode.sql
026_graph_optimizations.sql
030_database_optimization.sql

可选功能性迁移
027_post_video_association.sql (重命名为032?)
033_experiments_schema.sql (A/B测试)
034_resumable_uploads.sql (可恢复上传)
035_trending_system.sql (趋势系统)
```

---

## 风险评估

### 低风险项目

- 移动Markdown文件（完全无损）
- 重新编号未应用的迁移（如果数据库是全新的）

### 中等风险项目

- 重新编号已应用的迁移（需要在迁移历史表中更新）

### 建议行动

**如果这是一个新项目**（未部署到生产）：
- ✅ 安全地删除或重新编号所有冲突文件
- ✅ 立即执行所有更改

**如果这是现有项目**（已部署到生产）：
- ⚠️ 首先备份数据库
- ⚠️ 在staging环境测试迁移
- ⚠️ 根据迁移历史表确定已应用的迁移

---

## 建议：仅Phase 1（最小风险）

鉴于当前是开发阶段，建议仅执行：

1. ✅ 重新编号冲突的031文件
2. ✅ 删除重复的040_resumable_uploads.sql
3. ⏳ 留下Markdown文件（不影响功能）

这样做的好处：
- 解决了关键的编号冲突问题
- 最小化风险
- 保留了所有功能

---

## 下一步

需要用户确认：
1. 项目是否已部署到生产？（影响迁移策略）
2. 是否要立即执行清理？
3. 是否要移动Markdown文件？

