# Nova 数据库架构分析 - 执行摘要

**日期**: 2025-11-11
**分析师**: Database Architect
**状态**: 🔴 CRITICAL - 需要立即关注

---

## TL;DR - 3 分钟摘要

### 核心问题

**Nova 平台采用了微服务架构，但数据库层面仍是单体应用。**

```
❌ 当前状态: 11 个微服务 → 2 个共享数据库
✅ 推荐状态: 11 个微服务 → 11 个独立数据库
```

### 三大致命缺陷

1. **数据重复无同步** 🔴
   - `users` 表在 `nova_auth` 和 `nova_staging` 两个数据库中重复
   - 无同步机制，导致数据不一致

2. **跨服务外键约束** 🔴
   - 9 个外键约束跨越服务边界
   - 破坏微服务的独立性和可扩展性

3. **缺失数据库表** 🔴
   - 6+ 个服务的数据库表不存在
   - messaging、media、content 等核心服务无数据存储

### 影响

| 影响类型 | 描述 | 严重性 |
|---------|------|--------|
| **数据一致性** | 用户信息更新后不同步 | 🔴 CRITICAL |
| **服务独立性** | 无法独立部署和扩展服务 | 🔴 CRITICAL |
| **删除用户风险** | CASCADE 删除触发跨服务数据丢失 | 🔴 CRITICAL |
| **开发效率** | 多团队修改同一数据库导致冲突 | 🟡 HIGH |
| **可维护性** | 数据库成为单点故障 | 🟡 HIGH |

---

## Linus Torvalds 的诊断

> **"You've built a distributed monolith."**
>
> "Your microservices architecture is a facade. The shared database creates tight coupling that defeats the entire purpose of microservices. This is worse than a monolith - you have all the complexity of distributed systems with none of the benefits."

### 根本原因

**数据结构设计错误** → 代码修复无法解决

```
错误的思维顺序:
1. 先拆分服务 ❌
2. 再考虑数据 ❌

正确的思维顺序:
1. 先定义数据所有权 ✅
2. 再拆分服务 ✅
```

---

## 数据库现状快照

### 物理架构

```
PostgreSQL 实例 (单点)
├── nova_auth (5 tables)
│   ├── users (18 列) ← 认证数据
│   ├── sessions
│   ├── oauth_connections
│   └── token_revocation
│
└── nova_staging (21 tables) ← 问题所在
    ├── users (10 列) ← 重复!
    ├── user_profiles + settings + relationships (user-service)
    ├── reports + moderation_* (moderation-service)
    ├── search_* (search-service)
    ├── activity_logs (audit-service)
    └── domain_events + outbox_events (events-service)
```

### 服务架构 vs 数据库架构

| 服务 | 推荐数据库 | 实际数据库 | 状态 |
|------|-----------|-----------|------|
| auth-service | nova_auth | nova_auth | ✅ 正确 |
| user-service | nova_user | nova_staging | ❌ 共享 |
| messaging-service | nova_messaging | **缺失** | ❌ 无表 |
| media-service | nova_media | **缺失** | ❌ 无表 |
| content-service | nova_content | **缺失** | ❌ 无表 |
| search-service | nova_search | nova_staging | ❌ 共享 |
| notification-service | nova_notifications | **缺失** | ❌ 无表 |
| moderation-service | nova_moderation | nova_staging | ❌ 共享 |
| events-service | nova_events | nova_staging | ❌ 共享 |
| audit-service | nova_audit | nova_staging | ❌ 共享 |

**结论**: 仅 1/10 服务拥有独立数据库

---

## 跨服务外键依赖图 (简化)

```
          ┌──────────────┐
          │ STAGING_USERS│ ← 跨服务依赖的根源
          └───────┬──────┘
                  │
      ┌───────────┴───────────────────────────┐
      │                                       │
┌─────▼────────┐                  ┌──────────▼──────┐
│user-service  │                  │moderation-service│
├──────────────┤                  ├─────────────────┤
│user_profiles │ CASCADE          │reports          │ CASCADE
│user_settings │ CASCADE          │mod_queue        │ NO ACTION
│relationships │ CASCADE          │mod_actions      │ NO ACTION
└──────────────┘                  │mod_appeals      │ CASCADE
                                   └─────────────────┘
      │                                       │
┌─────▼────────┐                  ┌──────────▼──────┐
│search-service│                  │audit-service    │
├──────────────┤                  ├─────────────────┤
│search_history│ CASCADE          │activity_logs    │ CASCADE
│suggestions   │ CASCADE          └─────────────────┘
└──────────────┘
```

**问题**: 删除 `STAGING_USERS` 中的用户会触发 4 个服务的级联删除

---

## 业务风险场景

### 场景 1: 用户更新邮箱

```
用户操作: 修改邮箱 old@email.com → new@email.com

后端处理:
1. auth-service: UPDATE nova_auth.users SET email = 'new@email.com' ✅
2. user-service: (无同步机制) ❌
3. 结果:
   - nova_auth.users.email = 'new@email.com'
   - nova_staging.users.email = 'old@email.com'  ← 不一致!

用户体验:
- 用户使用新邮箱登录 ✅
- 但搜索、审核系统显示旧邮箱 ❌
- 用户收到两个邮箱地址的通知 ❌
```

### 场景 2: 用户注销账号

```
用户操作: 删除账号

后端处理:
1. user-service: DELETE FROM nova_staging.users WHERE id = '...' ✅
2. 触发 CASCADE 删除:
   - user_profiles ✅
   - user_settings ✅
   - user_relationships ✅
   - activity_logs ✅ (审核服务无感知)
   - reports ✅ (举报历史丢失)
   - search_history ✅ (搜索历史丢失)
3. 但 nova_auth.users 仍然存在 ❌

结果:
- 用户数据部分删除 (数据孤岛)
- 审核日志丢失 (合规风险)
- 用户仍可登录但无 profile (系统错误)
```

### 场景 3: 搜索服务宕机

```
场景: search-service 宕机 30 分钟

后端处理:
1. user-service: 用户删除账号
2. DELETE FROM nova_staging.users 触发 CASCADE
3. search_history 表无法访问 (search-service 宕机)
4. 数据库尝试删除 search_history 行
5. 结果:
   - 如果数据库锁定: 用户删除操作超时 ❌
   - 如果延迟删除: 产生孤儿记录 ❌
```

---

## 推荐解决方案 (3 阶段)

### 阶段 1: 消除数据重复 (Week 1-2)

**目标**: 解决 `users` 表重复问题

```
步骤:
1. 在 auth-service 实现 gRPC API:
   - GetUser(user_id) → UserInfo
   - CheckUserExists(user_id) → bool
   - GetUserBatch(user_ids[]) → UserInfo[]

2. 在 nova_staging 创建 user_cache 表:
   - 仅存储必要的用户基本信息
   - 通过事件同步更新

3. auth-service 发布事件:
   - UserCreated
   - UserUpdated
   - UserDeleted

4. 所有服务订阅事件,更新本地缓存

5. 删除 nova_staging.users 表
```

**影响**:
- 代码修改: 中等 (每个服务需修改用户查询逻辑)
- 性能影响: 低 (通过缓存抵消 gRPC 调用开销)
- 风险: 中 (需要大量测试)

### 阶段 2: 拆分数据库 (Week 3-6)

**目标**: Database-per-Service 模式

```
迁移计划:
├── Week 3: 创建 6 个新数据库
│   ├── nova_user
│   ├── nova_moderation
│   ├── nova_search
│   ├── nova_audit
│   ├── nova_events
│   └── nova_messaging (新建)
│
├── Week 4: 使用 Expand-Contract 模式迁移表
│   ├── 复制表结构和数据
│   ├── 应用层双写 (旧表 + 新表)
│   └── 验证数据一致性
│
├── Week 5: 切换读流量
│   ├── 10% 流量到新数据库
│   ├── 50% 流量到新数据库
│   └── 100% 流量到新数据库
│
└── Week 6: 清理
    ├── 停止双写
    ├── 删除旧表 (保留备份)
    └── 性能验证
```

**影响**:
- 成本增加: +$715/月 (6 个独立数据库)
- 性能提升: 预计 30-50% (减少锁竞争)
- 可维护性: 大幅提升 (独立部署)

### 阶段 3: 消除外键 + Saga 模式 (Week 7-8)

**目标**: 保证跨服务操作的最终一致性

```
实现:
1. 删除所有跨服务外键约束
2. 应用层验证用户存在性 (gRPC API)
3. 实现 Saga 协调器处理跨服务事务
4. 补偿机制处理失败场景

示例 - 用户删除 Saga:
├── Step 1: 软删除用户资料
├── Step 2: 通知审核服务归档数据
├── Step 3: 通知搜索服务删除历史
├── Step 4: 通知认证服务删除账户
└── 失败时: 自动执行补偿操作
```

**影响**:
- 代码复杂度: 增加 (但提升可靠性)
- 性能: 无明显影响
- 数据一致性: 大幅提升

---

## 成本分析

### 当前成本

```
配置: AWS RDS db.t3.medium (单实例)
├── 计算: $100/月
├── 存储: 100GB SSD @ $0.23/GB = $23/月
└── 总计: $123/月

问题:
- 单点故障
- 无读副本
- 连接数限制 (200)
```

### 推荐配置成本

```
方案 A: Database-per-Service (推荐)
├── nova_auth: db.t3.small ($75/月)
├── nova_user: db.t3.medium ($150/月)
├── nova_moderation: db.t3.small ($75/月)
├── nova_search: db.t3.medium ($150/月)
├── nova_messaging: db.t3.medium ($150/月)
├── nova_events: db.t3.small ($75/月)
├── 其他服务: 3 x db.t3.small ($225/月)
├── 存储: 500GB ($115/月)
└── 总计: $1,015/月 (增加 $892/月)

优势:
- 故障隔离 (一个服务宕机不影响其他)
- 独立扩展 (按需增加数据库规格)
- 开发效率提升 (无数据库冲突)
- 清晰的所有权边界

ROI 分析:
- 开发效率提升: 30% (2-3 人月节省)
- 停机风险降低: 99.9% → 99.95% (成本收益 > $10K/年)
- 技术债减少: 预计节省 50+ 工程小时
```

### 成本优化策略

```
1. Reserved Instances (1 年期)
   - 节省 ~40% ($362/月)
   - 最终成本: $653/月

2. Aurora Serverless v2 (长期)
   - 根据负载自动扩缩容
   - 低峰期成本降低 60%
   - 预计平均成本: $700/月

3. 数据归档
   - 90 天数据迁移到 S3
   - 存储成本降低 70% ($80/月节省)
```

---

## 执行时间表

| 周 | 重点 | 交付物 | 负责团队 |
|---|------|--------|---------|
| 1 | 问题验证 | 数据一致性测试报告 | Backend |
| 2 | API 设计 | auth-service gRPC API | Backend |
| 3 | 事件系统 | Kafka 事件发布/订阅 | Backend |
| 4 | 数据库创建 | 6 个新数据库 + 迁移脚本 | DevOps |
| 5 | 双写实现 | 应用层双写逻辑 | Backend |
| 6 | 流量切换 | 逐步迁移读流量 | Backend + QA |
| 7 | 外键移除 | 删除跨服务外键 | Backend |
| 8 | Saga 实现 | 用户删除 Saga 协调器 | Backend |

**总工作量**: 8 人周 (2 位 Backend + 1 位 DevOps)

---

## 风险评估

### 高风险项 (需要缓解策略)

| 风险 | 概率 | 影响 | 缓解措施 |
|-----|-----|-----|---------|
| 数据迁移失败 | 中 | 高 | 分批迁移 + 完整回滚计划 |
| 双写期间数据不一致 | 中 | 高 | 实时对账脚本 + 告警 |
| 性能下降 | 低 | 中 | 压力测试 + Redis 缓存 |
| 成本超支 | 低 | 低 | 使用 Reserved Instances |

### 回滚策略

```
触发条件:
├── 数据不一致率 > 1%
├── 错误率 > 0.1%
├── P95 延迟增加 > 50%
└── 用户投诉 > 10/hour

回滚步骤:
1. 切换特性开关 (< 1 分钟)
2. 恢复旧数据库读流量
3. 暂停新数据库写入
4. 分析失败原因
5. 数据对账修复
```

---

## 成功标准

### 技术指标

- [ ] 每个服务独立拥有数据库
- [ ] 零跨服务外键约束
- [ ] 事件同步延迟 < 1s (p95)
- [ ] 查询性能 < 100ms (p95)
- [ ] 数据一致性 > 99.99%

### 业务指标

- [ ] 零数据丢失
- [ ] 零停机迁移
- [ ] 用户体验无降级
- [ ] 成本增加 < $1000/月

### 团队效率

- [ ] 独立部署周期缩短 50%
- [ ] 数据库冲突减少 100%
- [ ] 新功能开发速度提升 30%

---

## 立即行动项

### 本周需完成

1. **获得管理层批准** (优先级 P0)
   - 成本增加预算: $1000/月
   - 工程资源: 2 Backend + 1 DevOps (8 周)
   - 风险接受: 中等风险的数据库迁移

2. **数据一致性测试** (优先级 P0)
   - 验证 `nova_auth.users` vs `nova_staging.users` 不一致率
   - 测试用户删除场景的数据完整性
   - 分析孤儿记录数量

3. **技术方案评审** (优先级 P1)
   - Backend 团队: API 设计
   - DevOps 团队: 数据库迁移方案
   - QA 团队: 测试策略

### 下周启动

1. **auth-service API 开发**
   - GetUser gRPC 接口
   - 事件发布机制

2. **数据库环境准备**
   - 创建 nova_user 数据库 (测试环境)
   - 迁移脚本编写

---

## 相关文档

- **详细分析**: [DATABASE_ARCHITECTURE_ANALYSIS.md](DATABASE_ARCHITECTURE_ANALYSIS.md) (20,000+ 字)
- **ERD 图**: [DATABASE_ERD.md](DATABASE_ERD.md)
- **阶段规划**: [PHASE_4_PLANNING.md](../PHASE_4_PLANNING.md)

---

## 附录：Linus 的最终建议

> **"Start with the data. Everything else is just code."**
>
> 修复顺序:
> 1. ✅ 定义数据所有权 (谁拥有哪些表)
> 2. ✅ 消除数据重复 (单一真相源)
> 3. ✅ 删除跨服务外键 (服务独立性)
> 4. ✅ 实现事件驱动同步 (最终一致性)
> 5. ✅ 重构代码适配新架构
>
> 不要反过来做。数据结构正确了,代码自然就简单了。

---

**报告生成时间**: 2025-11-11 05:45:00 UTC
**下次审查**: Week 2 (用户表重复问题解决后)

**联系方式**:
- 数据库架构组: [email]
- Phase 4 项目经理: [email]
