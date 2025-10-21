# 🚀 分支管理快速参考卡

**打印这张卡放在你的工作站旁边！**

---

## 快速命令

### 启动任务
```bash
git fetch origin
git checkout feature/T201-kafka-notifications
git pull origin feature/T201-kafka-notifications
```

### 日常开发
```bash
git add .
git commit -m "feat(T201): clear description"
git push origin feature/T201-kafka-notifications
```

### 提交 PR（任务完成）
```bash
cargo clippy              # 检查警告
cargo test --all          # 运行所有测试
gh pr create --base develop/phase-7
```

### 清理本地分支
```bash
git branch -d feature/T201-kafka-notifications
git push origin --delete feature/T201-kafka-notifications
```

---

## 任务分支列表

| 周 | 任务 | 分支名 | 工程师 | 状态 |
|----|------|--------|--------|------|
| W2 | T201 | `feature/T201-kafka-notifications` | [ ] | ⏳ |
| W2 | T202 | `feature/T202-fcm-apns-integration` | [ ] | ⏳ |
| W2 | T203 | `feature/T203-websocket-handler` | [ ] | ⏳ |
| W3 | T234 | `feature/T234-neo4j-social-graph` | [ ] | ⏳ |
| W3 | T235 | `feature/T235-redis-social-cache` | [ ] | ⏳ |
| W3 | T236 | `feature/T236-social-graph-tests` | [ ] | ⏳ |

---

## 提交消息格式

```
<type>(<scope>): <subject>

<type>: feat|fix|test|chore|docs|refactor
<scope>: T### (任务号)
<subject>: 简洁描述（现在时，命令式）

✅ feat(T201): implement Kafka consumer batching
❌ fixed the kafka thing
```

---

## PR 检查清单

- [ ] `cargo clippy` 通过
- [ ] `cargo test --all` 通过
- [ ] 代码覆盖率 >85%
- [ ] 无 merge conflicts
- [ ] 至少 1 个代码审查批准

---

## 常见问题速查

**Q: 分支过时了？**
```bash
git fetch origin
git rebase origin/develop/phase-7
```

**Q: 提交错了？**
```bash
git reset --soft HEAD~1    # 撤销但保留改动
git reset --hard HEAD~1    # 撤销并丢弃改动
```

**Q: 需要合并最新的 develop 代码？**
```bash
git fetch origin
git merge origin/develop/phase-7
```

---

## 分支生命周期

```
创建 → 推送 → 开发 → PR → 审查 → 合并 → 删除
```

**存活周期**: 3-5 天

---

## 关键日期

- **Oct 21**: Week 2 开始 (T201-T203)
- **Oct 24**: Week 2 完成 (所有分支合并到 main)
- **Oct 27**: Week 3 开始 (T234-T236)
- **Oct 31**: Week 3 完成 (发布就绪)
- **Nov 1**: Phase 7B 开始

---

## 获得帮助

📖 完整文档: 查看 `BRANCH_STRATEGY.md` 和 `TASK_TRACKING.md`

💬 提问: 描述你的问题，查看这两个文件的 FAQ 部分

🔧 Git 问题: 使用 `git reflog` 查看历史，可以恢复任何改动

---

**版本**: 1.0 | **最后更新**: 2025-10-21

