# 分支管理指南

## 核心原则

### 1. 分支模式：简洁且可扩展

我们采用**简化的Git Flow**模式：

```
main
  ├── feat/*              (新功能分支)
  ├── fix/*               (bug修复分支)
  ├── chore/*             (维护、配置、依赖)
  └── docs/*              (文档更新)
```

**为什么不用develop分支？**
- 项目规模还不需要（当前<50人）
- PR制度足够确保质量
- 减少分支数量降低维护复杂度

### 2. 命名规则（强制）

#### ✅ 正确的命名
```
feat/recommendation-engine     ← 新特性（清晰、简洁）
fix/jwt-token-expiry          ← bug修复（具体问题）
chore/update-dependencies      ← 维护任务（作用明确）
docs/api-endpoints            ← 文档（内容描述）
```

#### ❌ 错误的命名
```
001-feature                    ← ❌ 编号前缀（语义不明）
feature-branch-1              ← ❌ 通用编号（不可识别）
WIP_something                  ← ❌ 混合大小写（维护困难）
007-personalized-feed-ranking  ← ❌ 混合编号规则（过时做法）
```

### 3. 分支生命周期

```
1. 创建 ─→ 2. 开发 ─→ 3. PR ─→ 4. Review ─→ 5. 合并 ─→ 6. 删除
```

#### 步骤详解

**1️⃣ 创建分支（从main开始）**
```bash
git checkout main
git pull origin main
git checkout -b feat/your-feature-name
```

**2️⃣ 开发并提交**
```bash
# 遵循提交规范
git add .
git commit -m "feat(module): clear description"
git push origin feat/your-feature-name
```

**3️⃣ 创建Pull Request**
- 标题：`[FEAT] 功能描述` 或 `[FIX] 问题修复`
- 描述：1-2句核心改动说明
- 关联Issue（如果有）

**4️⃣ Code Review**
- 至少1名审核者批准
- 所有CI检查通过
- 无merge conflicts

**5️⃣ 合并到main**
```bash
git checkout main
git pull origin main
git merge --no-ff feat/your-feature-name
git push origin main
```

**6️⃣ 删除本地和远程分支**
```bash
git branch -d feat/your-feature-name
git push origin --delete feat/your-feature-name
```

## 常见命令速查

### 查看分支状态
```bash
# 查看所有分支
git branch -a

# 查看本地分支与main的差异
git branch -vv

# 查看分支上未提交的commit
git log main..YOUR_BRANCH --oneline
```

### 保持分支最新
```bash
# 方法1：Rebase（线性历史，推荐）
git checkout YOUR_BRANCH
git rebase main

# 方法2：Merge（保留历史，有冲突时使用）
git checkout YOUR_BRANCH
git merge main
```

### 处理冲突
```bash
# 1. 手动解决文件冲突
# 2. 标记为已解决
git add .

# 3a. 如果是rebase中的冲突
git rebase --continue

# 3b. 如果是merge中的冲突
git commit -m "Merge branch 'main' into YOUR_BRANCH"
```

### 清理工作空间
```bash
# 删除本地已merged的分支
git branch --merged main | grep -v main | xargs git branch -d

# 同步远程分支状态
git remote prune origin

# 清理所有已删除的远程分支
git fetch origin --prune
```

## 分支架构审查清单

定期检查（每周一次）：

- [ ] 本地branch数量 < 10个
- [ ] 没有超过1周未更新的活跃分支
- [ ] 所有分支都按命名规则命名
- [ ] 没有旧的/已merged的分支残留
- [ ] main分支永远可部署
- [ ] 所有remote stale分支已清理

## 当前（2025-10-21）分支快照

### 活跃分支
```
✓ chore/ios-local-docker      本地开发配置优化
✓ feat/api-v1-routing          API v1路由标准化
✓ fix/jwt-base64-decode        JWT认证修复
✓ chore/docs-cleanup           文档整理
✓ 007-personalized-feed-ranking 排名系统（待rebase）
```

### 清理历史
- ✅ 已删除的merged分支（4个）
  - 001-rtmp-hls-streaming
  - 008-feed-timeline-mvp
  - 008-streaming-system
  - 009-cdn-integration

## 问题排查

### Q: 我的分支diverged了怎么办？
**A:** 三个步骤解决：
```bash
git checkout YOUR_BRANCH
git fetch origin main
git rebase origin/main
# 如果有冲突，手动解决后 git rebase --continue
```

### Q: 我不小心删除了本地分支？
**A:** 在30天内可以恢复：
```bash
git reflog  # 找到分支的SHA
git checkout -b BRANCH_NAME <SHA>
```

### Q: 多个分支需要同样的修复？
**A:** 使用cherry-pick：
```bash
git log main --oneline          # 找到commit SHA
git checkout TARGET_BRANCH
git cherry-pick <SHA>
```

### Q: 如何整理杂乱的commit历史？
**A:** 使用交互式rebase：
```bash
git rebase -i main
# 编辑器中选择: pick, squash, reword等
```

## 最佳实践

### 1. 提交粒度要合理
```
❌ 太粗糙: "fix all bugs"
✅ 合理的: "fix: handle null pointer in user auth"
```

### 2. 保持分支短命
```
❌ 长期分支（>2周）导致冲突增加
✅ 短期分支（<1周）更易维护
```

### 3. 频繁同步main
```bash
# 每天至少一次
git fetch origin
git rebase origin/main
```

### 4. 提交前自我检查
```bash
git diff HEAD~1          # 检查改动
git log HEAD~3 --oneline # 检查最近的提交
npm run lint             # 代码质量检查
npm test                 # 运行测试
```

## 团队协作规则

### PR Review标准
- ✅ 代码风格一致
- ✅ 所有测试通过
- ✅ 有适当的注释
- ✅ commit信息清晰
- ✅ 没有破坏性变更

### 不要做这些
- ❌ 直接push到main
- ❌ Force push到main或develop
- ❌ 让分支超过30天未同步
- ❌ 在PR中混合多个功能
- ❌ 合并有unresolved冲突的分支

## 参考

- [Conventional Commits](https://www.conventionalcommits.org/)
- [Git Branching Model](https://nvie.com/posts/a-successful-git-branching-model/)
- [GitHub Flow](https://guides.github.com/introduction/flow/)
