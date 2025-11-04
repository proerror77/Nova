# ⚡ Nova 架构重构 - 快速参考

**版本**: 2.0 (修订版，基于实际经验)
**状态**: 准备执行

---

## 🎯 一句话总结

> 不是"先拆数据库再改代码"，而是"先改代码让它们解耦，数据库自然分离"

---

## 📋 修订前 vs 修订后

| 方面 | 修订前 | 修订后 ✅ |
|------|--------|---------|
| **第一步** | 分离数据库 | 实施 gRPC |
| **问题** | ❌ 外键约束阻止分离 | ✅ 逻辑解耦，约束自动消失 |
| **时间线** | 无法完成 | 12-16 周应用层改造 |
| **风险** | 高（数据库级别改动） | 中（应用级别改动） |
| **回滚** | 困难 | 容易（代码级别回滚） |

---

## 🚀 3 个阶段（简化版）

### Phase 1: 应用层解耦 (12-16 周) ⭐ 最重要

```
核心改动: SQL 查询 → gRPC 调用

auth-service:
  ❌ SELECT * FROM users WHERE id = $1
  ✅ grpc_client.get_user(user_id)

messaging-service:
  ❌ SELECT * FROM users WHERE id = sender_id
  ✅ auth_service_client.get_user(sender_id)

结果:
  ✅ 服务之间没有 SQL 依赖
  ✅ 外键约束问题消失
  ✅ 可以自由改动表结构（只要 gRPC API 不变）
```

### Phase 2: 事件驱动 (4-6 周)

```
核心改动: 直接更新 → Outbox + Kafka

当用户更新时:
  1. 更新 users 表
  2. 同时插入 outbox_events
  3. Kafka 异步发送 user.updated 事件
  4. 其他服务订阅并处理

结果:
  ✅ 多服务更新同一个表时保证一致性
  ✅ 事件驱动（"我做了什么"而不是"去查数据"）
  ✅ 自然支持基于事件的缓存失效
```

### Phase 3: 数据库分离 (可选，4-8 周)

```
前提: Phase 1-2 已完成

此时分离很容易，因为:
  ❌ 没有 SQL JOIN 跨数据库
  ✅ 通过 gRPC 调用（不关心数据库在哪里）

分离步骤:
  1. 为每个服务创建独立数据库
  2. 复制数据
  3. 改数据库连接字符串
  4. 应用代码完全不变（已通过 gRPC 通信）

结果:
  ✅ 独立扩展（auth-service DB 独立扩展）
  ✅ 独立备份恢复
  ✅ 更好的隔离（一个 DB 宕机不影响其他）
```

---

## 💡 为什么这样做？

你已经学到的教训：

```
❌ 直接分离数据库
   问题: 56+ 外键约束难以处理
   结果: 失败，必须回退

✅ 先应用层改造
   优势:
     1. 外键约束自动消失（不再 SQL JOIN）
     2. 可以逐个服务改造（不是全局改动）
     3. 每个服务改完了再改下一个
     4. 随时可以回滚（只是代码）
```

---

## 📊 工作量估计

| 阶段 | 持续时间 | 人数 | 难度 |
|------|--------|------|------|
| **Phase 0** | 1 周 | 2-3 | 低 |
| **Phase 1** | 12-16 周 | 4-5 | 中 |
| **Phase 2** | 4-6 周 | 2-3 | 低 |
| **Phase 3** | 4-8 周 (可选) | 2-3 | 低 |
| **总计** | 21-31 周 | - | - |

**成本**: $100k-$150k
**ROI**: 年度故障成本减少 $300k-$600k

---

## 🎯 Phase 0 具体任务 (1 周)

实际可执行的任务：

### Task 1: 设计 gRPC API (2 天)

```protobuf
// 为 8 个服务定义 gRPC 接口
// 示例: auth-service
service AuthService {
  rpc GetUser(GetUserRequest) returns (GetUserResponse);
  rpc VerifyToken(VerifyTokenRequest) returns (VerifyTokenResponse);
  rpc ListUsers(ListUsersRequest) returns (ListUsersResponse);
}

// 其他 7 个服务类似
```

**输出**: 8 个 `.proto` 文件

### Task 2: 列出数据所有权 (1 天)

```
auth-service:
  ✓ 拥有: users, user_credentials, tokens
  ✓ 被读取: messaging-service, content-service, ...
  ✗ 被写入: 无（好！）

messaging-service:
  ✓ 拥有: messages, conversations
  ✓ 被读取: feed-service, search-service
  ✗ 被写入: 无（好！）

content-service:
  ...
```

**输出**: `docs/SERVICE_DATA_OWNERSHIP.md`

### Task 3: Kafka 事件清单 (1 天)

```
事件列表:
  - user.created → auth-service
  - user.updated → auth-service
  - user.deleted → auth-service
  - message.sent → messaging-service
  - message.deleted → messaging-service
  - post.created → content-service
  - post.deleted → content-service

每个事件:
  - 所有者服务
  - 数据结构 (schema)
  - 消费方列表
```

**输出**: `docs/KAFKA_EVENT_CONTRACTS.md`

### Task 4: Phase 1 详细计划 (1 天)

```
Week 1-2:  auth-service gRPC 实现
Week 3-4:  messaging-service gRPC 实现
Week 5-6:  content-service gRPC 实现
Week 7-8:  其他 5 个服务 gRPC
Week 9-10: 缓存层实现
Week 11-12: 集成测试
Week 13-16: 灰度发布 + 性能验证
```

**输出**: `docs/PHASE_1_WEEKLY_SCHEDULE.md`

---

## ✅ Phase 1 成功标准

```
完成后应该达到:
  ✅ 0 个直接跨数据库 SQL 查询
  ✅ 100% 服务间通信通过 gRPC
  ✅ gRPC P95 延迟 < 200ms
  ✅ 缓存 hit rate > 80%
  ✅ 故障隔离能力改进（某个服务宕机影响最小化）
  ✅ 独立部署能力 (不需要全部协调)
```

---

## 📅 建议的启动计划

```
2025-11-04 (今天):
  - 你确认这个修订版方案可行吗？
  - 确认后启动 Phase 0

2025-11-05:
  - 分配 2-3 名工程师
  - 创建 feature/architecture-phase-0-revised 分支
  - 启动 Phase 0 任务

2025-11-05 ~ 11-11 (第 1 周):
  - Task 1: gRPC API 设计
  - Task 2: 数据所有权清单
  - Task 3: Kafka 事件定义
  - Task 4: Phase 1 详细计划

2025-11-12 开始: Phase 1 执行

2026-01-20: Phase 1 完成

2026-02-28: Phase 2 完成 (可选)
```

---

## 🚨 关键风险 & 缓解

| 风险 | 可能性 | 缓解 |
|------|--------|------|
| gRPC 性能不足 | 中 | Week 7 基准测试，多级缓存 |
| 缓存一致性 | 低 | 通过 Kafka 事件清除缓存 |
| 灰度发布问题 | 低 | 金丝雀部署，快速回滚 |

---

## 📖 相关文档

- **详细方案**: `ARCHITECTURE_REVISED_STRATEGY.md` (完整的 Phase 0-3 规划)
- **决策框架**: `ARCHITECTURE_DECISION_FRAMEWORK.md` (成本效益分析)
- **执行摘要**: `ARCHITECTURE_EXECUTIVE_SUMMARY.md` (高级概览)
- **快速参考**: 你在看这个文件！

---

## ❓ 常见问题

**Q: Phase 0 真的只需要 1 周？**
A: 是的。主要是设计和文档，没有代码改动。

**Q: Phase 1 什么时候开始看到收益？**
A: Week 8-12（当 gRPC 基础完成）。此后部署和扩展会明显改进。

**Q: 数据库何时分离？**
A: Phase 3，但这是**可选的**。Phase 1 完成后已经解决了主要问题。

**Q: 如果 Phase 1 中途失败？**
A: 容易回滚。只是代码改动，原数据库保持不变。

**Q: 需要停机吗？**
A: 没有。gRPC 改造可以在运行中进行（灰度发布）。

---

## 🎬 Next Step

**现在就读 `ARCHITECTURE_REVISED_STRATEGY.md`**

这是完整的修订版方案，包含所有细节。

然后决定:
- ✅ 同意这个方向，启动 Phase 0？
- ❓ 需要我解释更多？
- ❌ 有其他想法？

---

**May the Force be with you.** 🚀

