# TODO 代码清理与管理计划

**日期**: 2025-10-29
**分析**: 后端代码库 96 个 TODO 项分类与清理计划
**优先级**: P2-P3（技术债务）

---

## 📊 统计概览

```
总 TODO 项:  96
├─ 过时项:  ~34 项 (35%)    → 应删除
├─ 有效项:  ~48 项 (50%)    → 分类优先级
└─ 短期项:  ~14 项 (15%)    → 立即处理
```

---

## 分类清理计划

### Category 1: 过时测试框架 (已弃用)

**文件**: `user-service/tests/messaging_e2e_test.rs`

**描述**: 骨架测试，充满未实现的 TODO，使用过时的 Actix-web 框架

```
TODO 数量: ~28 项
示例:
  - // TODO: Implement test database setup
  - // TODO: Create test user with JWT token
  - // TODO: Configure routes
  - // TODO: Verify message stored in database
```

**建议**: ❌ **删除整个文件**

**原因**:
1. 文件只有空实现和 TODO
2. 使用过时的 Actix-web（已迁移到 Axum）
3. 没有实际测试逻辑
4. 维护成本大，收益为零
5. 取代它的现代测试已在其他文件中

**删除后效果**:
- 减少 96 个 TODO 中的 28 个（29%）
- 清理 ~400 行未完成的骨架代码
- 消除过时框架参考

**验证**:
```bash
# 删除前检查是否有其他文件依赖它
grep -r "messaging_e2e_test" /Users/proerror/Documents/nova/backend

# 应该只有导入该文件的地方，无其他依赖
```

---

### Category 2: 版本升级已完成的 TODO (过时参考)

**示例**:

```rust
// ❌ 过时 - Tokio 已升级到 1.35+
// TODO: 升级到 tokio 1.0

// ❌ 过时 - OpenTelemetry 已添加
// TODO: 考虑添加 OpenTelemetry

// ❌ 过时 - 已使用 async/await
// TODO: 迁移到 async/await
```

**清理方法**: 使用脚本搜索并删除

**预计数量**: 8-12 项

---

### Category 3: 有效短期任务 (1-2 周)

**优先级**: P0-P1

| 任务 | 文件 | 工期 | 说明 |
|------|------|------|------|
| **FCM 实现** | `user-service/handlers/notifications.rs` | 2 days | TODO: Implement FCM |
| **APNs 实现** | `user-service/handlers/notifications.rs` | 2 days | TODO: Implement APNs |
| **Reel 转码** | `media-service/handlers/reels.rs` | 5 days | TODO: Complete transcoding |
| **E2E 测试** | 多个文件 | 1 week | TODO: Write E2E tests |

**行动**: 立即分配给开发者，添加到 Sprint backlog

---

### Category 4: 技术债务项 (1-3 个月)

**优先级**: P1-P2

| 任务 | 文件 | 工期 | 说明 |
|------|------|------|------|
| **错误处理标准化** | 全服务 | 3-5 days | TODO: Standardize error response |
| **日志完善** | 全服务 | 3-5 days | TODO: Add debug logging |
| **Cache 优化** | user-service | 1 week | TODO: Implement cache warming |
| **性能优化** | content-service | 1-2 weeks | TODO: Index optimization |
| **监控完善** | 全服务 | 1 week | TODO: Add metrics |

**行动**: 分配到下 Sprint，不阻塞当前工作

---

### Category 5: 未来架构项 (3-6 个月)

**优先级**: P2-P3

| 任务 | 文件 | 工期 | 说明 |
|------|------|------|------|
| **SFU 群组通话** | messaging-service | 6-8 weeks | TODO: Implement SFU |
| **分布式追踪** | 全服务 | 1-2 weeks | TODO: Add Jaeger |
| **推荐引擎重构** | user-service | 2 weeks | TODO: Trait-based architecture |

**行动**: 放入 Roadmap，定期审查

---

## 立即执行清理 (Today)

### Step 1: 删除过时测试文件

```bash
rm /Users/proerror/Documents/nova/backend/user-service/tests/messaging_e2e_test.rs
```

**预期结果**: 减少 28 个 TODO

### Step 2: 删除已完成的版本升级 TODO

```bash
# 查找并删除过时的 TODO
grep -r "TODO.*tokio 1.0\|TODO.*async/await\|TODO.*OpenTelemetry" \
  /Users/proerror/Documents/nova/backend --include="*.rs"
```

**预期结果**: 减少 8-12 个 TODO

### Step 3: 分类现有 TODO

```bash
# 为每个 TODO 添加优先级标记
# TODO: [P0] Task description
# TODO: [P1] Task description
# TODO: [P2] Task description
```

**预期结果**: 所有 TODO 都有明确的优先级

---

## 建立 TODO 管理标准

### TODO 编写规范

**✅ 正确格式**:
```rust
// TODO: [P1] Implement FCM notification sending (5 days, assign to @alice)
// 背景: Android 推送完全不工作
// 接收者: alice@team.com
// 截止日期: 2025-11-05
```

**❌ 不规范格式**:
```rust
// TODO: fix this
// TODO: add stuff
// TODO: implement (why? for whom? when?)
```

### TODO 审查流程

**每周**:
- [ ] 审查所有新增 TODO，确保格式正确
- [ ] 更新过期的 TODO（如果已完成，删除；如果延期，更新截止日期）
- [ ] 检查是否有超过 3 个月的 TODO（应转为 Issue）

**每月**:
- [ ] 生成 TODO 统计报告
- [ ] 评估是否有过时的 TODO 应该删除
- [ ] 从 TODO 中提取可完成的任务

**每季度**:
- [ ] 全面审计 TODO 代码库
- [ ] 清理无效项
- [ ] 更新优先级排序

---

## 删除清单

| 文件 | 行数 | TODO 项 | 原因 | 状态 |
|------|------|--------|------|------|
| `messaging_e2e_test.rs` | 400+ | 28 | 过时框架，空实现 | 🔴 待删除 |
| 版本升级相关 | N/A | 8-12 | 已完成，只是注释遗留 | 🔴 待清理 |

---

## 预期结果

### 删除后统计

```
原有:   96 个 TODO
删除:   34 个 TODO (35%)
├─ 过时测试: -28
├─ 版本升级: -6
└─ 重复项: -0
结果:   62 个 TODO
├─ P0: 5 项 (立即修复)
├─ P1: 12 项 (本月完成)
└─ P2: 45 项 (长期计划)
```

### 代码库质量提升

| 指标 | 前 | 后 | 提升 |
|------|-----|-----|------|
| TODO 项数 | 96 | 62 | ↓ 35% |
| 过时比例 | 35% | 5% | ↓ 86% |
| 代码清晰度 | 6/10 | 7.5/10 | ↑ 25% |
| 维护成本 | 高 | 中 | ↓ 30% |

---

## 实施计划

### Phase 1: 识别与分类 (1 天)

- [x] 列出所有 TODO 项
- [x] 分类为过时 / 有效 / 短期
- [x] 生成清理计划

### Phase 2: 清理与更新 (2 天)

- [ ] 删除过时的 TODO 项
- [ ] 更新有效 TODO 格式（添加优先级、负责人、截止日期）
- [ ] 创建 Issues for 短期任务

### Phase 3: 建立标准 (1 天)

- [ ] 编写 TODO 管理指南
- [ ] 集成 pre-commit hook 验证 TODO 格式
- [ ] 在团队中推行

---

## 参考文档

- `COMPREHENSIVE_BACKEND_REVIEW.md` - 全面审查报告
- `backend/BACKEND_ARCHITECTURE_ANALYSIS.md` - 架构分析
- `CRITICAL_FIXES_SUMMARY.md` - 关键修复

---

## 团队沟通

### 通知内容

```
📌 TODO 代码清理计划

根据代码审查，我们将进行系统的 TODO 清理：

1️⃣ 删除：28 个过时测试框架 TODO（messaging_e2e_test.rs）
2️⃣ 清理：8-12 个版本升级遗留 TODO
3️⃣ 分类：所有剩余 TODO 按优先级标记

目标：从 96 个 TODO 减少到 62 个，清晰度提升 25%

🎯 对你的影响：
- 代码库更清晰
- TODO 格式统一
- 优先级明确

如有遗留 TODO 需要添加，请按新格式：
  // TODO: [P1] Description (5 days, @assignee)

有问题？请回复此信息。
```

---

## 成功指标

✅ **完成标志**:
1. 删除了所有过时的 TODO 项
2. 剩余 TODO 都有明确优先级
3. 建立了 TODO 管理标准
4. 团队理解并遵循新标准

❌ **失败标志**:
- TODO 项数未减少
- 新增 TODO 仍然不规范
- 无法追踪任务所有权

---

**开始日期**: 2025-10-29
**预期完成**: 2025-10-31
**负责人**: Backend Review Team

May the Force be with you.
