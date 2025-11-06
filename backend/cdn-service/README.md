# CDN Service

Phase 1B Week 4 - Asset Management & URL Signing

## 架构概述

采用 **实用主义架构**（Linus 哲学）：
- **数据结构优先**：`asset_id` + `storage_key`（S3 键）是核心
- **零特殊情况**：统一 Result<T> 错误处理，无 Option 混淆
- **简单至上**：HMAC-SHA256 签名，不用复杂加密
- **零破坏性**：所有新功能隔离，proto 兼容现有接口

## 核心组件

### 1. AssetManager (资产管理)
**文件**: `src/services/asset_manager.rs` (250 行)

**职责**:
- 上传资产到 S3（带配额检查）
- 软删除资产（异步清理 S3）
- 查询资产元数据
- 分页列出用户资产

**关键方法**:
```rust
pub async fn upload_asset(user_id, content, content_type, filename) -> Result<AssetInfo>
pub async fn delete_asset(asset_id, user_id) -> Result<()>
pub async fn get_asset_info(asset_id) -> Result<AssetInfo>
pub async fn list_user_assets(user_id, limit, offset) -> Result<Vec<AssetInfo>>
```

**数据流**:
```
Upload: 检查配额 → 上传 S3 → 生成签名 URL → 插入数据库 → 更新配额
Delete: 验证权限 → 软删除（is_deleted=TRUE）→ 触发器更新配额
```

### 2. UrlSigner (URL 签名)
**文件**: `src/services/url_signer.rs` (100 行，纯函数）

**职责**:
- 生成带过期时间的签名 URL
- 验证签名和过期时间
- 提取过期时间戳

**签名格式**:
```
https://cdn.nova.dev/{storage_key}?exp={timestamp}&sig={hmac_sha256}

Payload: storage_key:expiration
Signature: HMAC-SHA256(payload, secret_key)
```

**安全特性**:
- 常数时间比较防止时序攻击
- 先检查过期（快速失败）
- 签名包含过期时间（防止重放）

### 3. CacheInvalidator (缓存失效)
**文件**: `src/services/cache_invalidator.rs` (150 行)

**职责**:
- 单资产缓存失效（Redis + 数据库记录）
- 批量失效用户所有资产
- 缓存统计（24h 窗口）
- 资产元数据缓存（24h TTL）

**缓存策略**:
```
Key 格式: cdn:asset:{asset_id}
TTL: 86400 秒（24 小时）
失效: 删除 Redis key + 记录到数据库
```

### 4. gRPC 服务层
**文件**: `src/grpc.rs` (345 行，薄适配层）

**实现方法** (12 个):
- ✅ `generate_cdn_url` - 生成签名 URL
- ✅ `get_cdn_asset` - 获取资产配置
- ✅ `register_cdn_asset` - 注册资产（元数据）
- ✅ `update_cdn_asset` - 更新配置
- ✅ `invalidate_cache` - 失效缓存
- ✅ `invalidate_cache_pattern` - 模式失效（占位）
- ✅ `get_cache_invalidation_status` - 查询失效状态
- ✅ `get_cdn_usage_stats` - 使用统计
- ⚠️ `get_edge_locations` - 边缘节点（未实现）
- ⚠️ `prewarm_cache` - 预热缓存（未实现）
- ⚠️ `get_deployment_status` - 部署状态（未实现）
- ⚠️ `get_cdn_metrics` - 详细指标（未实现）

**实现策略**:
- 核心功能：完全实现（资产管理 + URL 签名 + 缓存失效）
- 高级功能：返回占位响应（边缘节点等）
- 理由：Proto 定义的是"理论完美"的 CDN，我们实现的是"实际需要"的简单版本

## 数据库设计

### Tables

**assets** (资产元数据)
```sql
- asset_id: UUID (主键)
- user_id: UUID (所有者)
- original_filename: VARCHAR(256)
- file_size: BIGINT
- content_type: VARCHAR(100)
- storage_key: VARCHAR(512) UNIQUE (S3 键)
- cdn_url: VARCHAR(1024) (签名 URL)
- upload_timestamp: TIMESTAMP
- access_count: BIGINT
- is_deleted: BOOLEAN
```

**cache_invalidations** (失效记录)
```sql
- invalidation_id: UUID (主键)
- asset_id: UUID (外键)
- invalidation_reason: VARCHAR(256)
- status: VARCHAR(50) (pending/in_progress/completed/failed)
- created_at: TIMESTAMP
- resolved_at: TIMESTAMP
```

**cdn_quota** (配额管理)
```sql
- user_id: UUID (主键)
- total_quota_bytes: BIGINT (默认 10GB)
- used_bytes: BIGINT
- last_updated: TIMESTAMP
```

**触发器**:
- `trigger_update_cdn_quota` - 自动更新配额（INSERT/UPDATE/DELETE assets）

## 性能优化

### 数据库索引
```sql
-- 用户资产查询（最常用）
idx_assets_user_upload (user_id, upload_timestamp DESC) WHERE is_deleted = FALSE

-- S3 键查找
idx_assets_storage_key (storage_key) WHERE is_deleted = FALSE

-- 缓存失效查询
idx_cache_inv_asset (asset_id, created_at DESC)
idx_cache_inv_status (status, created_at) WHERE status != 'completed'
```

### 缓存策略
```
资产元数据 → Redis (24h TTL)
签名 URL → 每次请求重新生成（< 10ms）
配额信息 → 数据库（触发器自动维护）
```

### 预期性能
| 操作 | 目标延迟 | 实际瓶颈 |
|------|---------|---------|
| URL 生成 | < 10ms | HMAC 计算（纯 CPU） |
| 元数据查询 | < 50ms | PostgreSQL 索引查询 |
| 上传资产 | < 2s | S3 网络延迟 |
| 缓存失效 | < 500ms | Redis 删除 + DB 插入 |

## 环境变量

```bash
# 数据库
DATABASE_URL=postgres://user:pass@localhost/nova

# AWS S3
S3_BUCKET=nova-cdn
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-west-2

# Redis
REDIS_URL=redis://localhost:6379

# CDN 配置
CDN_DOMAIN=cdn.nova.dev
CDN_SECRET_KEY=your-secret-key-here  # 生产环境必须修改！

# 服务端口
PORT=8000  # HTTP 端口
# gRPC 端口自动为 PORT+1000 (9000)
```

## 运行服务

```bash
# 开发环境
cargo run -p cdn-service

# 生产构建
cargo build --release -p cdn-service

# 测试
cargo test -p cdn-service

# Clippy 检查
cargo clippy -p cdn-service
```

## 未实现功能（预留）

以下功能在 proto 中定义，但当前未实现（返回占位响应）：

1. **边缘节点管理** (`get_edge_locations`)
   - 理由：当前是单区域 S3，无需边缘节点
   - 预留字段：`edge_locations: vec![]`

2. **缓存预热** (`prewarm_cache`)
   - 理由：S3 + CloudFront 自动处理
   - 可选实现：定时任务预取热门资源

3. **部署状态追踪** (`get_deployment_status`)
   - 理由：静态资产无部署过程
   - 可选实现：S3 同步状态追踪

4. **详细 CDN 指标** (`get_cdn_metrics`)
   - 理由：需要 CloudWatch/Prometheus 集成
   - 可选实现：连接监控系统

## 技术债务

1. **S3 删除异步化** - 当前是软删除，需要定时任务硬删除 S3 对象
2. **Redis 降级策略** - Redis 失败时应降级到数据库（不阻断主流程）
3. **配额超限处理** - 需要更细粒度的配额策略（每日上传限制等）
4. **S3 上传失败回滚** - 当前未处理 DB 插入成功但 S3 失败的情况

## Linus 视角总结

**✅ 好品味 (Good Taste)**:
- URL 签名是纯函数，无状态，无特殊情况
- 数据库触发器自动维护配额，消除了手动维护的复杂性
- 统一 Result<T> 错误处理，零 unwrap()

**✅ 实用主义 (Pragmatism)**:
- 没有实现不存在的问题（边缘节点、缓存预热）
- S3 是真正的存储层，我们只管理元数据
- 签名 URL 解决了访问控制，不需要复杂的权限系统

**✅ 简洁执行 (Simplicity)**:
- AssetManager: 4 个核心方法，职责单一
- UrlSigner: 纯函数，100 行搞定
- gRPC: 最薄的适配层，不含业务逻辑

**⚠️ 需要改进**:
- Proto 定义过于复杂（12 个方法，只有 8 个实际需要）
- 建议：下一版本 proto 简化为 6 个核心方法

## 测试覆盖

**已有测试** (内嵌在服务代码中):
- UrlSigner: 8 个单元测试（签名、验证、过期、篡改）
- AssetManager: 2 个单元测试（storage_key 格式、配额常量）
- CacheInvalidator: 2 个单元测试（cache key 格式、TTL）

**需要补充**:
- AssetManager 集成测试（需要数据库 + S3）
- CacheInvalidator 集成测试（需要 Redis）
- gRPC 端到端测试

总行数：~1000 行（不含测试），符合预期（12 小时工期）
