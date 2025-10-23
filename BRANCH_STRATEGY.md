# 分支管理策略 (Branch Management Strategy)

**最后更新**: 2025-10-23
**版本**: 2.0 (重写，与 Phase 7B 合并后的实际状态一致)
**状态**: ✅ 生产就绪

---

## 📋 概述

本文档定义了 Nova 项目的分支管理策略。采用 **Simplified Feature Branch Model**（经 Phase 7B 分支整合优化），确保清晰的工作流、版本控制和极简的分支维护。

### 当前状态 (2025-10-23)
- ✅ Phase 7B 已完全合并到 main
- ✅ 所有开发分支已整合，仅保留 2 个活跃分支
- 🔄 Phase 7C 开发准备启动

---

## 🌳 分支结构

```
main (生产环境 - Phase 7B 已完全集成)
│
│  (长期开发分支)
└─ develop/phase-7c (Phase 7C 开发 - Message Search + Stories)

发布/修复分支（按需创建，临时）:
├─ feature/US{ID}-{description} (功能开发)
├─ bugfix/US{ID}-{description} (缺陷修复)
└─ hotfix/critical-{issue} (紧急补丁)
```

**关键变化**:
- ✅ 43 个分支 → 2 个分支 (来自 PR #20-#23 的清理)
- ✅ `develop/phase-7b` 已合并到 main (完成 PR #21)
- ✅ 新创建 `develop/phase-7c` 用于 Phase 7C 开发

---

## 📝 分支命名约定

### 功能分支 (Feature Branches)
**格式**: `feature/US{ID}-{description}`

**说明**:
- `US{ID}`: User Story 编号（从规范文档 specs/ 中取，例如 US1, US2, US3）
- `{description}`: 简洁的功能描述（英文，kebab-case）
- 长度: 不超过 50 字符
- 基于分支: `develop/phase-7c`

**示例** (Phase 7C 示例):
```
✅ feature/US3-message-search-fulltext
✅ feature/US4-stories-api-create
✅ feature/US5-notification-db-storage
❌ feature/message-search (缺少 US ID)
❌ feature/US3-this-is-a-very-long-description-exceeding-limits (太长)
```

### 缺陷修复分支 (Bugfix Branches)
**格式**: `bugfix/US{ID}-{description}`

**说明**:
- 针对已知的 bug，引用对应的 User Story ID
- 存活周期: 3-5 天
- 基于分支: `develop/phase-7c` 或 `main`（紧急）

**示例**:
```
✅ bugfix/US1-message-encryption-race-condition
✅ bugfix/US2-websocket-reconnection-timeout
```

### 清理/维护分支 (Chore Branches)
**格式**: `chore/{scope}-{description}`

**说明**:
- 不涉及新功能或缺陷修复
- 例: 依赖更新、文档更新、测试改进

**示例**:
```
✅ chore/docs-cleanup
✅ chore/dependencies-update-2025-10
✅ chore/test-coverage-improvements
```

### 发布分支 (Release Branches)
**格式**: `release/v{major}.{minor}` (临时，合并后删除)

**说明**:
- 从 main 创建发布候选
- 包含版本号更新、CHANGELOG 等
- 合并后立即删除

**示例**:
```
✅ release/v1.0
✅ release/v1.1-phase-7b
```

### 紧急补丁 (Hotfix Branches)
**格式**: `hotfix/critical-{issue}`

**说明**:
- 仅用于生产级别的紧急修复
- 直接从 main 创建，合并回 main 和 develop
- 合并后立即删除

**示例**:
```
✅ hotfix/critical-auth-bypass
✅ hotfix/critical-data-corruption
```

---

## 🔄 开发工作流 (Phase 7C 示例)

### 1️⃣ 开始新任务

```bash
# Step 1: 确保 develop/phase-7c 是最新的
git checkout develop/phase-7c
git pull origin develop/phase-7c

# Step 2: 创建新分支（对标 User Story，例如 US3-Message Search）
git checkout -b feature/US3-message-search-fulltext

# Step 3: 推送到远程（建立上游跟踪）
git push -u origin feature/US3-message-search-fulltext
```

### 2️⃣ 开发实现

```bash
# 在分支上进行开发（遵循 TDD）
git add .
git commit -m "feat(US3): implement Elasticsearch integration"
git commit -m "test(US3): add full-text search test cases"
git commit -m "docs(US3): document search API endpoints"
git push origin feature/US3-message-search-fulltext
```

**提交消息约定** (Conventional Commits):
```
<type>(<scope>): <subject>

<type>: feat|fix|test|chore|docs|refactor|perf
<scope>: US{ID} (User Story 号) 或功能名
<subject>: 简洁描述 (现在时，命令式)

示例:
✅ feat(US3): implement Elasticsearch full-text search
✅ test(US3): add search ranking algorithm tests
✅ fix(US2): resolve WebSocket reconnection timeout
✅ docs(US4): document Stories API schema
❌ feat: add search stuff
❌ fixed the bug
```

### 3️⃣ 提交拉取请求 (PR)

```bash
# 创建 PR（推荐通过 GitHub CLI）
gh pr create \
  --title "feat(US3): Implement message full-text search with Elasticsearch" \
  --body "
## Summary
Implement full-text search for messages using Elasticsearch integration.

## Changes
- [x] Elasticsearch client setup (backend/search-service/src/elastic/)
- [x] CDC pipeline for message indexing
- [x] Search API endpoint with ranking
- [x] 25+ test cases for search accuracy

## Testing
\`\`\`bash
cargo test --all
# 或运行特定测试
cargo test --package search-service
\`\`\`

## Performance
- Search latency (P95): <200ms
- Index update delay: <5 seconds

## Related
- Spec: specs/002-messaging-stories-system/spec.md
- Checklist: See tasks.md US3 section
" \
  --base develop/phase-7c
```

**PR 检查清单**:
- [ ] 代码通过 `cargo clippy` (无警告)
- [ ] 所有测试通过 (`cargo test --all`)
- [ ] 代码覆盖率 >85% (新增代码)
- [ ] 提交消息遵循约定
- [ ] 文档/注释已更新
- [ ] 无 merge conflicts
- [ ] 性能指标已验证

### 4️⃣ 代码审查与合并

```bash
# 审查者审查后，使用 GitHub UI 合并（推荐 squash or rebase）
# 或使用 GitHub CLI 合并
gh pr merge <PR_NUMBER> --merge

# 本地清理
git checkout develop/phase-7c
git pull origin develop/phase-7c
git branch -d feature/US3-message-search-fulltext
```

### 5️⃣ 定期同步到 main

**时机**: Phase 完成时（不是每周，而是按 Phase 周期）

```bash
# 1. 确保 develop/phase-7c 已充分测试
git checkout develop/phase-7c
git pull origin develop/phase-7c

# 2. 创建 PR 合并到 main
gh pr create \
  --title "merge: integrate Phase 7C features to main" \
  --body "Phase 7C development cycle complete. Ready for production." \
  --base main \
  --head develop/phase-7c

# 3. 经过审查和测试后，合并到 main
gh pr merge <PR_NUMBER> --merge

# 4. 验证 main 已更新
git checkout main
git pull origin main
```

---

## 🚨 常见场景

### 场景 1: 在已有分支上继续开发

```bash
# 切换到功能分支（例如 US3-message-search）
git checkout feature/US3-message-search-fulltext

# 更新到最新
git pull origin feature/US3-message-search-fulltext

# 继续开发
git add . && git commit -m "feat(US3): add search ranking" && git push
```

### 场景 2: 从主开发分支更新代码

```bash
# 在功能分支上，同步最新的 develop/phase-7c 代码
git checkout feature/US3-message-search-fulltext
git fetch origin
git rebase origin/develop/phase-7c

# 如果有冲突，解决冲突后:
git add . && git rebase --continue && git push -f origin feature/US3-message-search-fulltext
```

### 场景 3: 放弃任务或重新开始

```bash
# 删除本地分支
git branch -d feature/US3-message-search-fulltext

# 删除远程分支
git push origin --delete feature/US3-message-search-fulltext

# 如果要重新开始
git checkout develop/phase-7c
git pull origin develop/phase-7c
git checkout -b feature/US3-message-search-fulltext
```

### 场景 4: 紧急修复 (Hotfix - 仅用于生产级别 bug)

```bash
# 从 main 创建紧急修复分支（仅针对生产级别问题）
git checkout main
git pull origin main
git checkout -b hotfix/critical-data-corruption

# 开发最小化修复
git add . && git commit -m "fix(critical): resolve data corruption in messages table"
git push -u origin hotfix/critical-data-corruption

# 创建 PR 直接到 main（绕过 develop）
gh pr create --base main --head hotfix/critical-data-corruption

# 审查和合并后，同步回 develop/phase-7c
git checkout develop/phase-7c
git pull origin main
git push origin develop/phase-7c

# 删除 hotfix 分支
git push origin --delete hotfix/critical-data-corruption
```

### 场景 5: 合并多个 PR 到 develop 后同步到 main

```bash
# 当 Phase 开发完成，多个 PR 已合并到 develop/phase-7c
git checkout develop/phase-7c
git pull origin develop/phase-7c

# 验证所有测试通过
cargo test --all

# 创建一个统一的 PR 合并到 main
gh pr create \
  --title "merge(phase-7c): integrate completed features to main" \
  --body "Phase 7C development complete. All tests passing." \
  --base main \
  --head develop/phase-7c

# 合并
gh pr merge <PR_NUMBER> --merge
```

---

## 📊 分支生命周期

### 短期功能分支 (Feature/Bugfix)

```
创建 (从 develop/phase-7c)
  │
  ├─ 推送到远程 (git push -u origin)
  │
  ├─ 开发实现 (TDD: Red → Green → Refactor)
  │
  ├─ 定期同步 develop (git rebase)
  │
  ├─ 创建 PR (标题: feat/fix(US#): ...)
  │
  ├─ 代码审查 (至少 1 个批准)
  │
  ├─ 合并到 develop (GitHub UI: squash 推荐)
  │
  └─ 删除 (自动或手动删除)
```

**存活周期**: 3-7 天
- 短期任务: 2-3 天
- 中等任务: 3-5 天
- 大型任务: 5-7 天
- 超过 1 周: 重新评估设计或分解任务

### 长期开发分支 (develop/phase-7c)

```
创建于 Phase 7C 启动
  │
  ├─ 接收多个 feature/bugfix PR
  │
  ├─ 定期集成测试 (每个 PR 合并后)
  │
  ├─ 当 Phase 完成
  │
  ├─ 创建 Phase 完成 PR (merge 到 main)
  │
  └─ 保留至下一 Phase
```

**存活周期**: 4-8 周 (单个 Phase 周期)

---

## ✅  检查清单

### 创建分支前
- [ ] User Story 编号确认 (US#)
- [ ] US 在规范文档 `specs/002-messaging-stories-system/` 中存在
- [ ] 基于最新的 `develop/phase-7c` (运行 `git pull origin develop/phase-7c`)
- [ ] 分支名符合命名约定 (`feature/US#-description`)

### 开发过程中 (TDD 循环)
- [ ] 每次提交都有清晰的 Conventional Commit 消息
- [ ] 提交粒度合理 (不超过 500 行改动/commit)
- [ ] 测试驱动: 先写测试，再实现功能
- [ ] 定期 push 到远程 (至少每天一次)
- [ ] 代码能在本地通过所有测试

### 提交 PR 前
- [ ] `cargo clippy --all` 通过 (零警告)
- [ ] `cargo test --all` 通过 (所有测试)
- [ ] 新代码覆盖率 >85%
- [ ] 没有 merge conflicts (运行 `git rebase origin/develop/phase-7c`)
- [ ] PR 标题按约定: `feat(US#): description` 或 `fix(US#): description`
- [ ] PR 描述包含: Summary, Changes, Testing, Performance

### 合并前
- [ ] 至少获得 1 个代码审查批准
- [ ] 所有 CI/CD 检查通过 (GitHub Actions)
- [ ] 解决了所有审查反馈
- [ ] PR 创建者确认已修复所有问题

### 合并后
- [ ] 使用 GitHub UI 合并 (推荐 squash 方式)
- [ ] 删除远程分支 (GitHub UI 会提示)
- [ ] 本地删除分支: `git branch -d feature/US#-...`
- [ ] 在规范文档中标记 US 为完成

---

## 🔐 分支保护规则

### main 分支 ⛔ 严格受保护
- **必须**: 通过 PR 合并（禁止直接 push）
- **必须**: 获得至少 1 个代码审查批准
- **必须**: 所有 CI/CD 检查通过
- **必须**: 禁止强制 push (`--force` 或 `--force-with-lease`)
- **用途**: 生产环境，Phase 完成时整合

### develop/phase-7c 分支 ⚠️ 建议受保护
- **推荐**: 通过 PR 合并（便于追踪）
- **推荐**: 简单改动可直接 push (快进提交)
- **必须**: 通过 CI/CD 检查
- **禁止**: 强制 push
- **用途**: Phase 开发，接收多个 feature PR

### 临时分支 (feature/bugfix/hotfix) ✅ 无保护
- **允许**: 直接 push (个人工作空间)
- **允许**: 强制 push (重新整理历史)
- **必须**: 代码审查后才能合并到 develop 或 main

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

**Nova 项目规范**:
- [`specs/002-messaging-stories-system/spec.md`](./specs/002-messaging-stories-system/spec.md) - Phase 7C User Stories
- [`specs/002-messaging-stories-system/tasks.md`](./specs/002-messaging-stories-system/tasks.md) - 具体任务清单
- [`BRANCH_CLEANUP_SUMMARY.md`](./docs/BRANCH_CLEANUP_SUMMARY.md) - 分支整合历史 (Phase 7B)
- [`PHASE_7B_KICKOFF.md`](./PHASE_7B_KICKOFF.md) - Phase 7B 实现指南

**Git/GitHub 最佳实践**:
- [Git Documentation](https://git-scm.com/doc)
- [GitHub Flow Guide](https://guides.github.com/introduction/flow/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [GitHub CLI Documentation](https://cli.github.com/manual/)

---

## 📋 版本历史

- **v2.0** (2025-10-23): 重写，适应 Phase 7B 合并后的简化分支结构
  - 从 43 分支简化为 2 分支
  - 更新 User Story 编号约定 (T## → US#)
  - 新增 `develop/phase-7c` 长期开发分支
  - 优化 Phase 级别的整合策略

- **v1.0** (2025-10-21): 初始版本，定义 Phase 7 分支策略（已过时）

