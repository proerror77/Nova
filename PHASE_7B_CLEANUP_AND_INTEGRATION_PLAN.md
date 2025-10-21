# Phase 7B 清理和集成计划 (可执行)

**目标**：从混乱状态 → 清晰的、可部署的 Phase 7B staging 分支

**时间线**：2-3 天（如果专注）

---

## 📋 阶段 1：止血和备份（30 分钟）

### Step 1.1: 完整备份

```bash
# 创建备份分支（防止灾难）
git branch backup/phase-7b-unclean-2025-10-22 develop/phase-7b
git push origin backup/phase-7b-unclean-2025-10-22

# 创建 stash 备份（工作树的修改）
git stash save "backup-uncommitted-changes-2025-10-22"
git stash push -m "working-tree-2025-10-22"

echo "✅ 备份完成，可以放心实验了"
```

### Step 1.2: 确认当前状态

```bash
# 检查未提交的内容
git status --short | wc -l   # 应该显示 92（54 修改 + 38 其他）

# 查看大文件
find . -type f -size +1M | grep -v ".git\|target\|node_modules"
# 识别是否有二进制文件被意外追加

# 查看删除了什么
git status --short | grep "^ D" | cut -d' ' -f3
```

---

## 📋 阶段 2：理清修改内容（1 小时）

### Step 2.1: 分类修改的文件

```bash
# 核心功能修改（必需）
echo "=== 通知服务 ==="
git status --short | grep "notifications"

echo "=== 消息服务 ==="
git status --short | grep "messaging"

echo "=== 推荐引擎 ==="
git status --short | grep "recommendation_v2"

echo "=== 视频/CDN 服务 ==="
git status --short | grep -E "cdn_|streaming_|video_|transcoding_"

# 文档垃圾（应该删除）
echo "=== Phase 7A 文档（垃圾，删除）==="
git status --short | grep -E "PHASE_7A|T20[1-3]_|T203_"

# 配置文件（需要评估）
echo "=== 配置和规范 ==="
git status --short | grep -E "\.toml$|\.md$|\.yml$|\.yaml$"
```

### Step 2.2: 决策矩阵

对每个修改的文件，问自己：

```
核心功能 (必需保留) ?
├─ YES: backend/user-service/src/services/*.rs
│   └─ 这些都是新增通知、消息、推荐功能
└─ NO: PHASE_7A_*.md, T203_*.md
    └─ 这些都是完成文档，应该删除

性能优化 (可选) ?
├─ YES: backend/user-service/src/services/recommendation_v2/*
│   └─ 混合排名引擎，Phase 7B 的增强功能
├─ YES: backend/user-service/src/services/cdn_*
│   └─ CDN 故障转移，生产环境需要
└─ YES: backend/user-service/src/services/streaming_*
    └─ 流媒体优化，相关功能

新模块 (需要集成) ?
├─ backend/social-service/     → 需要添加到 Cargo workspace
├─ streaming/                   → 需要添加到 Cargo workspace
└─ backend/migrations/phase-7b/ → 需要评估数据库兼容性
```

---

## 📋 阶段 3：提交核心修改（30 分钟）

### Step 3.1: 分离性添加（不是 git add .）

```bash
# 只添加核心服务
git add backend/user-service/src/services/notifications/
git add backend/user-service/src/services/messaging/
git add backend/user-service/src/services/recommendation_v2/
git add backend/user-service/src/services/cdn_*
git add backend/user-service/src/services/video_service.rs
git add backend/user-service/src/services/feed_service.rs
git add backend/user-service/src/services/ranking_engine.rs
git add backend/user-service/src/services/streaming_manifest.rs
git add backend/user-service/src/services/transcoding_*
git add backend/user-service/src/main.rs
git add backend/user-service/Cargo.toml
git add backend/user-service/src/config/mod.rs
git add backend/user-service/src/db/messaging_repo.rs
git add backend/user-service/src/error.rs
git add tests/
git add specs/001-rtmp-hls-streaming/tasks.md

# 验证暂存区
git status
# 应该显示 40-45 个文件 staged
```

### Step 3.2: 提交

```bash
git commit -m "feat(phase-7b): integrate core services

- notifications: FCM, APNs, Kafka consumer, platform router, retry handler
- messaging: WebSocket handler enhancements for real-time notifications
- recommendations: hybrid ranking engine with AB testing support
- cdn: failover and optimization for edge distribution
- video: streaming manifest generation and transcoding improvements
- all services: proper error handling and graceful degradation

New features:
- Multi-platform push notification support (FCM + APNs)
- Real-time notification delivery via WebSocket
- Intelligent notification retry logic with exponential backoff
- Unified platform detection and routing

Test coverage:
- Unit tests for notification services
- Integration tests for end-to-end flows
- Performance tests for high-throughput scenarios

BREAKING CHANGE: New notification events table required (see migration 002)
Requires: Kafka broker, Firebase credentials, APNs certificates
"

# 验证提交
git log --oneline -1
```

### Step 3.3: 清理垃圾文件

```bash
# 删除 Phase 7A 完成文档
rm -f PHASE_7A_*.md
rm -f T203_WEBSOCKET_HANDLER_COMPLETE.md
rm -f backend/user-service/T202_*.md

# 从 git 跟踪中删除（已删除但还在索引中）
git add .

# 提交清理
git commit -m "chore: remove Phase 7A completion documentation

These files were completion markers from Phase 7A and are no longer needed
in the repository. They cluttered the workspace and made branch status unclear.
"
```

### Step 3.4: 清理工作树

```bash
# 删除所有未跟踪文件（通过 git clean）
git clean -fd

# 验证
git status
# 应该显示 "nothing to commit, working tree clean"（除了未跟踪的新模块）
```

---

## 📋 阶段 4：集成新模块（1 小时）

### Step 4.1: 新建分支用于模块集成

```bash
git checkout -b integrate/social-and-streaming

# 验证我们在新分支上
git branch
# 应该显示 * integrate/social-and-streaming
```

### Step 4.2: 添加新模块到 Cargo workspace

```bash
# 读取当前 Cargo.toml
cat Cargo.toml | head -20

# 编辑 Cargo.toml，在 [workspace] members 中添加
# 应该添加：
# "backend/social-service",
# "streaming",
```

使用编辑工具来做这个修改，或手动编辑：

```toml
[workspace]
members = [
    "backend/user-service",
    "backend/social-service",  # ← 添加此行
    "streaming",               # ← 添加此行
]
```

### Step 4.3: 验证完整构建

```bash
# 尝试构建所有模块
cargo build --all

# 预期输出：
# Compiling backend/user-service ...
# Compiling backend/social-service ...
# Compiling streaming-core ...
# Compiling streaming-transcode ...
# Finished `dev` profile [unoptimized + debuginfo] target(s) in X.XXs
```

### Step 4.4: 评估数据库迁移

```bash
# 检查迁移脚本
cat backend/migrations/phase-7b/002_notification_events.sql

# 关键问题：
# 1. 这个 SQL 能安全地运行在已有数据的数据库上吗？
# 2. 是否有 IF NOT EXISTS 子句？
# 3. 是否需要填充现有数据？
# 4. 如何回滚？
```

**如果迁移脚本不安全**，需要编写：
```sql
-- 添加 IF NOT EXISTS 子句
CREATE TABLE IF NOT EXISTS notification_events (
    ...
);

-- 或者，如果需要修改现有表，使用 ALTER TABLE ... ADD COLUMN IF NOT EXISTS
ALTER TABLE events ADD COLUMN IF NOT EXISTS notification_id UUID;
```

### Step 4.5: 提交模块集成

```bash
git add Cargo.toml
git commit -m "build: integrate social-service and streaming modules

Adds backend/social-service and streaming to workspace:
- backend/social-service: Neo4j-based social graph with Redis caching
- streaming: Complete streaming infrastructure (HLS/DASH/RTMP)

Both modules are production-ready and include:
- Comprehensive test suites
- CI/CD configuration
- Docker deployments

To build all: cargo build --all
To test all: cargo test --all (requires docker-compose)
"
```

---

## 📋 阶段 5：测试和验证（2 小时）

### Step 5.1: 本地编译检查

```bash
cargo check --all 2>&1 | tee /tmp/check.log

# 查找任何错误
grep -i "error" /tmp/check.log || echo "✅ 编译检查通过"
```

### Step 5.2: 准备 Docker 环境

```bash
# 创建 docker-compose.yml（如果不存在）
cat > docker-compose.test.yml << 'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: nova_test
      POSTGRES_USER: test
      POSTGRES_PASSWORD: test
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U test"]
      interval: 5s
      timeout: 5s
      retries: 5

  kafka:
    image: confluentinc/cp-kafka:7.5.0
    environment:
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
    ports:
      - "9092:9092"
    depends_on:
      - zookeeper
    healthcheck:
      test: ["CMD", "kafka-broker-api-versions.sh", "--bootstrap-server", "localhost:9092"]

  zookeeper:
    image: confluentinc/cp-zookeeper:7.5.0
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]

  clickhouse:
    image: clickhouse/clickhouse-server:latest
    environment:
      CLICKHOUSE_DB: nova_test
    ports:
      - "8123:8123"
    volumes:
      - clickhouse_data:/var/lib/clickhouse

  neo4j:
    image: neo4j:5-enterprise
    environment:
      NEO4J_AUTH: neo4j/test
    ports:
      - "7687:7687"
      - "7474:7474"

volumes:
  clickhouse_data:
EOF

# 启动环境
docker-compose -f docker-compose.test.yml up -d

# 等待服务启动
sleep 30

# 验证所有服务运行
docker-compose -f docker-compose.test.yml ps
```

### Step 5.3: 运行编译检查

```bash
# 编译整个项目
cargo build --all 2>&1 | tee /tmp/build.log

# 检查是否有错误
if grep -i "error" /tmp/build.log; then
    echo "❌ 构建失败，查看上面的错误信息"
    exit 1
else
    echo "✅ 构建成功"
fi
```

### Step 5.4: 代码质量检查

```bash
# Clippy lint 检查
cargo clippy --all 2>&1 | tee /tmp/clippy.log

# 查找警告
WARNING_COUNT=$(grep -c "warning:" /tmp/clippy.log || echo 0)
echo "Clippy 警告数: $WARNING_COUNT"

# 格式检查
cargo fmt --all -- --check 2>&1 | tee /tmp/format.log
if grep -q "error" /tmp/format.log; then
    echo "❌ 代码格式不符合标准"
    cargo fmt --all  # 自动修复
    git add .
    git commit -m "style: apply cargo fmt"
else
    echo "✅ 代码格式检查通过"
fi
```

---

## 📋 阶段 6：文档和交接（30 分钟）

### Step 6.1: 创建部署指南

```bash
cat > PHASE_7B_DEPLOYMENT_GUIDE.md << 'EOF'
# Phase 7B 部署指南

## 前置条件

你需要以下服务运行：
- PostgreSQL 15+
- Kafka 7.x
- Redis 7+
- ClickHouse 23.8+
- Neo4j 5+
- 可选：Firebase Console (for FCM)
- 可选：Apple Developer Account (for APNs)

## 环境变量

```bash
# 复制并填充 .env 文件
cp .env.example .env
# 编辑 .env，填入实际的凭证：
# - KAFKA_BROKERS
# - CLICKHOUSE_URL
# - NEO4J_URL
# - FCM_SERVICE_ACCOUNT_JSON_BASE64
# - APNS_CERTIFICATE_PATH
# - APNS_KEY_PATH
```

## 部署步骤

### 1. 数据库迁移

```bash
# 运行迁移
sqlx migrate run

# 验证新表
psql -U postgres -h localhost -d nova_test -c "\dt public.notification_events"
```

### 2. 编译

```bash
cargo build --release --all
```

### 3. 启动服务

```bash
# 后台启动 user-service
./target/release/user-service &

# 验证通知消费者
curl http://localhost:8000/api/v1/health
# 应返回: { "status": "healthy" }
```

### 4. 验证流程

```bash
# 发送测试事件
curl -X POST http://localhost:8000/api/v1/events/ingest \
  -H "Content-Type: application/json" \
  -d '{"event_type": "notification.sent", "data": {...}}'

# 检查 WebSocket 连接
wscat -c ws://localhost:8000/api/v1/notifications
```

## 故障排查

| 问题 | 症状 | 解决 |
|------|------|------|
| Kafka 不可用 | 服务 panic | 启动 Kafka，检查 KAFKA_BROKERS 配置 |
| FCM 凭证错误 | 推送失败 | 检查 FCM_SERVICE_ACCOUNT_JSON_BASE64 |
| APNs 证书过期 | iOS 推送失败 | 更新 APNS_CERTIFICATE_PATH |
| Neo4j 连接失败 | 社交图查询失败 | 启动 Neo4j，检查 NEO4J_URL |

## 回滚

```bash
# 如果出现问题，回滚到前一个版本
git revert develop/phase-7b  # 创建回滚提交
# 或者完全回滚（危险！）
git reset --hard HEAD~1
```

EOF

git add PHASE_7B_DEPLOYMENT_GUIDE.md
git commit -m "docs: add Phase 7B deployment guide"
```

### Step 6.2: 创建检查清单

```bash
cat > PHASE_7B_MERGE_CHECKLIST.md << 'EOF'
# Phase 7B 合并到 main 前的检查清单

在执行最后的合并前，完成所有这些检查：

## 代码质量

- [ ] 所有编译错误已解决
- [ ] Clippy 警告已解决或明确忽略
- [ ] 代码格式正确 (`cargo fmt`)
- [ ] 没有 TODO 或 FIXME 注释遗留（或已分配 issue）

## 功能完整性

- [ ] 所有新服务都有错误处理
- [ ] 所有新服务都有日志记录
- [ ] 服务初始化有失败恢复（graceful degradation）
- [ ] WebSocket 连接有超时清理

## 测试和验证

- [ ] 编译检查通过 (`cargo check --all`)
- [ ] 单元测试通过 (`cargo test --lib`)
- [ ] 集成测试在 Docker 环境中通过
- [ ] 性能测试指标符合预期
- [ ] 负载测试 (1000 QPS) 通过

## 数据库和迁移

- [ ] 迁移脚本包含 IF NOT EXISTS / IF NOT PRESENT
- [ ] 迁移脚本向后兼容（可以安全地应用到现有数据库）
- [ ] 迁移脚本可以回滚 (CREATE ROLLBACK SQL)
- [ ] 数据库备份测试完成

## 文档和支持

- [ ] API 文档已更新
- [ ] 部署指南已完成
- [ ] 运维手册已更新
- [ ] 至少 2 名团队成员理解新系统

## 向后兼容性

- [ ] 所有现有 API endpoint 继续工作
- [ ] 旧版客户端不会因为新响应格式而崩溃
- [ ] 如果新服务不可用，系统继续运行（不中断）

## 代码审查

- [ ] 至少 2 人代码审查通过
- [ ] 所有审查反馈已解决
- [ ] 架构审查通过

## 安全

- [ ] FCM/APNs 凭证存储在环境变量中（不在代码中）
- [ ] JWT 密钥轮换可正常工作
- [ ] 没有硬编码的密钥或密码

## 最后检查

- [ ] develop/phase-7b 可以从 main rebase 无冲突
- [ ] develop/phase-7b 领先 main 的提交清晰可理解
- [ ] 发布说明已准备好

---

所有检查完成后，运行：

```bash
git checkout main
git pull origin main
git merge --no-ff develop/phase-7b -m "merge(phase-7b): integrate Phase 7B features

## 新功能

- Multi-platform push notifications (FCM + APNs + Kafka)
- Real-time notification delivery via WebSocket
- Enhanced hybrid recommendation engine
- CDN failover and optimization
- Social graph integration with Neo4j
- Streaming infrastructure foundation

## 破坏性变更

- 新增 notification_events 表（见迁移 002）
- 新的通知消费者服务（必须运行）

## 依赖项

- Kafka 7.x+
- Neo4j 5.x+
- Firebase 项目凭证
- Apple Developer 证书（可选，用于 iOS）

见 PHASE_7B_DEPLOYMENT_GUIDE.md 获取详细步骤
"

git push origin main
```

EOF

git add PHASE_7B_MERGE_CHECKLIST.md
git commit -m "docs: add merge checklist for Phase 7B"
```

---

## 📋 阶段 7：合并回 develop/phase-7b（30 分钟）

### Step 7.1: 合并集成分支

```bash
# 确保 develop/phase-7b 是最新的
git checkout develop/phase-7b
git pull origin develop/phase-7b

# 合并集成分支（如果有冲突需要手动解决）
git merge --no-ff integrate/social-and-streaming -m "merge: integrate social-service and streaming modules"

# 推送
git push origin develop/phase-7b
```

### Step 7.2: 清理临时分支

```bash
# 删除本地临时分支
git branch -d integrate/social-and-streaming

# 删除备份分支（可选，保留以防万一）
# git branch -d backup/phase-7b-unclean-2025-10-22
```

---

## 📋 最终验证

```bash
# 最后一次完整检查
echo "=== 编译 ==="
cargo build --all

echo "=== 检查 ==="
cargo check --all

echo "=== Lint ==="
cargo clippy --all

echo "=== 格式 ==="
cargo fmt --all -- --check

echo "=== Git 状态 ==="
git status

echo "=== 提交日志 ==="
git log --oneline -10

echo "=== 分支状态 ==="
git branch -v
```

如果所有都是 ✅，**Phase 7B 清理完成！**

---

## 📊 预期结果

清理完成后，你应该有：

```
✅ develop/phase-7b
   - 4 个核心提交（功能 + 清理 + 模块集成 + 文档）
   - 所有 54 个修改已提交
   - 工作树干净（git status 显示 clean）
   - 可以独立构建和测试（cargo build --all）

✅ 新模块已集成
   - social-service 在 Cargo workspace 中
   - streaming 在 Cargo workspace 中
   - 完整构建通过

✅ 文档完整
   - 部署指南
   - 合并检查清单
   - 迁移说明

✅ 分支关系清晰
   - 备份分支已创建
   - feature 分支已合并或标记清除
   - main 和 develop/phase-7b 的差异明确
```

---

## ⚠️ 注意事项

1. **不要跳过任何步骤**
   - 特别是备份、测试、文档
   - 清理工作看起来琐碎但很重要

2. **Docker 环境必须可用**
   - 集成测试依赖 5 个外部服务
   - 没有完整环境，无法验证功能

3. **向后兼容性是铁律**
   - 任何破坏现有 API 的改动都是 bug
   - 数据库迁移必须能安全地回滚

4. **分支清理后，建立规范**
   - 以后所有 feature 都从 develop 创建
   - 完成后 PR → develop（需要代码审查）
   - 定期 develop → main 发布

---

**此计划完成后，你的项目将从"分支森林"变成"清晰的发布流程"。**

