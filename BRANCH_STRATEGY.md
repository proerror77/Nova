# 分支管理策略 (Branch Management Strategy)

**最后更新**: 2025-10-21
**版本**: 1.0
**状态**: 🚀 Active

---

## 📋 概述

本文档定义了 Nova 项目的统一分支管理策略，适用于所有开发者。采用 **Feature Branch Model** 结合 **Task Tracking**，确保清晰的工作流和版本控制。

---

## 🌳 分支结构

```
main (生产环境主分支)
│
└─ develop/phase-7 (当前开发分支 - Phase 7A/7B/7C/7D)
   ├─ feature/T201-kafka-notifications (Week 2)
   ├─ feature/T202-fcm-apns-integration (Week 2)
   ├─ feature/T203-websocket-handler (Week 2)
   ├─ feature/T234-neo4j-social-graph (Week 3)
   ├─ feature/T235-redis-social-cache (Week 3)
   └─ feature/T236-social-graph-tests (Week 3)

发布分支（按需创建）:
├─ release/v1.0 (发布候选)
└─ hotfix/critical-bug (紧急补丁)
```

---

## 📝 分支命名约定

### 功能分支 (Feature Branches)
**格式**: `feature/T{ID}-{description}`

**说明**:
- `T{ID}`: 任务编号（从规划文档中取）
- `{description}`: 简洁的功能描述（英文，kebab-case）
- 长度: 不超过 50 字符

**示例**:
```
✅ feature/T201-kafka-notifications
✅ feature/T202-fcm-apns-integration
✅ feature/T234-neo4j-social-graph
❌ feature/kafka-integration (缺少 T ID)
❌ feature/T201-this-is-a-very-long-description-that-exceeds-limits (太长)
```

### 缺陷修复分支 (Bugfix Branches)
**格式**: `bugfix/T{ID}-{description}`

**示例**:
```
✅ bugfix/T206-notification-race-condition
✅ bugfix/T235-redis-timeout-issue
```

### 重构/维护分支 (Chore Branches)
**格式**: `chore/T{ID}-{description}`

**示例**:
```
✅ chore/T250-refactor-kafka-producer
✅ chore/T251-update-dependencies
```

### 发布分支 (Release Branches)
**格式**: `release/v{major}.{minor}`

**示例**:
```
✅ release/v1.0
✅ release/v1.1
```

### 紧急补丁 (Hotfix Branches)
**格式**: `hotfix/v{major}.{minor}.{patch}`

**示例**:
```
✅ hotfix/v1.0.1
✅ hotfix/critical-auth-bug
```

---

## 🔄 开发工作流

### 1️⃣ 开始新任务

```bash
# Step 1: 确保 develop/phase-7 是最新的
git checkout develop/phase-7
git pull origin develop/phase-7

# Step 2: 创建新分支（对标任务 T201）
git checkout -b feature/T201-kafka-notifications

# Step 3: 推送到远程（建立上游跟踪）
git push -u origin feature/T201-kafka-notifications
```

### 2️⃣ 开发实现

```bash
# 在分支上进行开发
git add .
git commit -m "feat(T201): implement Kafka consumer batching logic"
git commit -m "test(T201): add 30+ test cases for batch aggregation"
git push origin feature/T201-kafka-notifications
```

**提交消息约定**:
```
<type>(<scope>): <subject>

<type>: feat|fix|test|chore|docs|refactor
<scope>: T{ID} (任务号) 或功能名
<subject>: 简洁描述 (现在时，命令式)

示例:
✅ feat(T201): implement Kafka consumer with batch processing
✅ test(T201): add 30+ test cases for batch aggregation
✅ fix(T206): resolve race condition in notification queue
❌ feat: implement kafka stuff
❌ fixed the issue
```

### 3️⃣ 提交拉取请求 (PR)

```bash
# 创建 PR（推荐通过 GitHub CLI）
gh pr create \
  --title "feat(T201): Implement Kafka consumer batching" \
  --body "
## Summary
Implement Kafka consumer with batch processing for notifications.

## Changes
- [x] Kafka consumer initialization (src/kafka_consumer.rs)
- [x] Batch aggregation logic (src/batch_aggregator.rs)
- [x] 30+ unit tests
- [x] Integration test with local Kafka

## Testing
\`\`\`bash
cargo test --all
\`\`\`

## Performance
- Batch throughput: 10k msg/sec
- Latency (P95): <50ms
" \
  --base develop/phase-7
```

**PR 检查清单**:
- [ ] 代码通过 `cargo clippy` (无警告)
- [ ] 所有测试通过 (`cargo test --all`)
- [ ] 代码覆盖率 >85%
- [ ] 提交消息遵循约定
- [ ] 文档/注释已更新
- [ ] 无 merge conflicts

### 4️⃣ 代码审查与合并

```bash
# 审查者检查后，合并到 develop/phase-7
git checkout develop/phase-7
git pull origin develop/phase-7
git merge --squash feature/T201-kafka-notifications
git push origin develop/phase-7

# 删除已合并的分支
git push origin --delete feature/T201-kafka-notifications
git branch -d feature/T201-kafka-notifications
```

### 5️⃣ 周期性同步到 main

每周五 (发布日期):
```bash
# 1. 从 develop/phase-7 创建 release 分支
git checkout -b release/v1.0 develop/phase-7
git push -u origin release/v1.0

# 2. 版本号更新 + 发布笔记
# 编辑 Cargo.toml, CHANGELOG.md

# 3. 创建 PR 合并到 main
gh pr create \
  --title "release(v1.0): Phase 7A Week 2-3 release" \
  --base main \
  --head release/v1.0

# 4. 审批后合并到 main
# 5. 删除 release 分支
git push origin --delete release/v1.0
```

---

## 🚨 常见场景

### 场景 1: 在已有分支上继续开发

```bash
# 切换到任务分支
git checkout feature/T201-kafka-notifications

# 更新到最新
git pull origin feature/T201-kafka-notifications

# 继续开发
git add . && git commit -m "..." && git push
```

### 场景 2: 从主开发分支更新代码

```bash
# 在任务分支上，同步最新的 develop/phase-7 代码
git checkout feature/T201-kafka-notifications
git fetch origin
git rebase origin/develop/phase-7

# 如果有冲突，解决冲突后:
git add . && git rebase --continue && git push -f origin feature/T201-kafka-notifications
```

### 场景 3: 放弃任务或合并失败

```bash
# 删除本地分支
git branch -d feature/T201-kafka-notifications

# 删除远程分支
git push origin --delete feature/T201-kafka-notifications

# 如果要重新开始
git checkout develop/phase-7
git pull origin develop/phase-7
git checkout -b feature/T201-kafka-notifications
```

### 场景 4: 紧急修复 (Hotfix)

```bash
# 从 main 创建紧急修复分支
git checkout main
git pull origin main
git checkout -b hotfix/critical-auth-bug

# 开发修复
git add . && git commit -m "fix: resolve critical auth bug"
git push -u origin hotfix/critical-auth-bug

# 创建 PR 直接到 main（绕过 develop）
gh pr create --base main --head hotfix/critical-auth-bug

# 合并后，同步回 develop/phase-7
git checkout develop/phase-7
git pull origin main
git push origin develop/phase-7
```

---

## 📊 分支生命周期

```
创建
  │
  ├─ 推送到远程 (git push -u)
  │
  ├─ 开发 (git add/commit/push)
  │
  ├─ 创建 PR
  │
  ├─ 代码审查 (review)
  │
  ├─ 合并 (merge --squash)
  │
  └─ 删除 (git push origin --delete + git branch -d)
```

**分支存活周期**: 3-5 天 (单个任务通常 2-3 天，可根据任务规模调整)

---

## ✅ 检查清单

### 创建分支前
- [ ] 任务编号确认 (T###)
- [ ] 任务在规划文档中存在
- [ ] 基于最新的 `develop/phase-7`

### 开发过程中
- [ ] 每次提交都有清晰的消息
- [ ] 提交粒度合理 (不超过 500 行改动/commit)
- [ ] 代码自测通过
- [ ] 定期 push 到远程 (至少每天一次)

### 提交 PR 前
- [ ] `cargo clippy` 通过 (无警告)
- [ ] `cargo test --all` 通过
- [ ] 代码覆盖率 >85%
- [ ] 没有 merge conflicts
- [ ] PR 标题清晰，描述完整

### 合并前
- [ ] 获得至少 1 个批准 (code review)
- [ ] 所有 CI/CD 检查通过
- [ ] 解决了所有反馈

### 合并后
- [ ] 删除远程分支
- [ ] 删除本地分支
- [ ] 更新任务追踪系统 (标记为 Done)

---

## 🔐 分支保护规则

**main 分支**: ⛔ 受保护
- 必须通过 PR 合并（不能直接 push）
- 必须获得 1 个代码审查批准
- 必须通过所有 CI/CD 检查
- 禁止强制 push

**develop/phase-7 分支**: ⚠️ 部分受保护
- 推荐通过 PR 合并（便于追踪）
- 必须通过 CI/CD 检查
- 允许快进 (fast-forward) 提交

---

## 📈 分支统计与维护

### 每周检查清单

```bash
# 列出所有分支及其跟踪情况
git branch -a -v

# 删除已合并的本地分支
git branch -d $(git branch --merged develop/phase-7 | grep -v develop/phase-7)

# 清理远程跟踪分支
git remote prune origin

# 查看分支创建时间
git for-each-ref --sort=creatordate --format='%(refname) %(creatordate)' refs/heads/
```

### 月度清理

```bash
# 删除 2 周未更新的分支
git for-each-ref --sort='-authordate:iso8601' --format='%(refname) %(authordate:iso8601)' refs/heads/ | \
  awk '{print $1, $2, $3}' | \
  while read branch date; do
    # 比较日期，删除超过 14 天未更新的分支
  done
```

---

## 🎯 最佳实践

### DO ✅
- 分支名称简洁明确，包含任务 ID
- 每个分支对应一个清晰的功能/任务
- 定期推送到远程（至少每天一次）
- 提交消息描述改动的"为什么"而不只是"什么"
- 代码审查时要求修改会在审查前进行

### DON'T ❌
- 不要创建超过 1 周的长期分支（容易产生冲突）
- 不要在分支上进行多个不相关的功能开发
- 不要直接 push 到 main（必须通过 PR）
- 不要提交未测试的代码
- 不要忽视代码审查的反馈

---

## 📞 获取帮助

### 常见问题

**Q: 分支已经过时，如何更新?**
```bash
git fetch origin
git rebase origin/develop/phase-7
```

**Q: 误删了本地分支，如何恢复?**
```bash
git reflog  # 查看历史
git checkout -b branch-name <commit-hash>
```

**Q: 提交了错误的代码，如何撤销?**
```bash
git reset --soft HEAD~1  # 撤销最后一次提交，保留改动
git reset --hard HEAD~1  # 撤销最后一次提交，丢弃改动
```

---

## 📚 参考资源

- [Git Documentation](https://git-scm.com/doc)
- [GitHub Flow Guide](https://guides.github.com/introduction/flow/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Nova Phase 7 Planning](./specs/007-phase-7-notifications-social/)

---

**版本历史**:
- v1.0 (2025-10-21): 初始版本，定义 Phase 7 分支策略

