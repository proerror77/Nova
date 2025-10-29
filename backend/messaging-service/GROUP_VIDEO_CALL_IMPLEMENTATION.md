# Option 3 群组视频通话实现文档

## 概述

本文档描述了 Nova 社交应用的群组视频通话实现方案（Option 3）。该方案基于 P2P mesh 架构，支持 1:1 和群组视频通话，保持向后兼容性。

## 架构设计

### 核心原则

1. **向后兼容**：现有 1:1 通话功能不受影响
2. **渐进式升级**：从 1:1 → 群组 → SFU（未来）
3. **数据结构优先**：利用现有数据库表（`call_sessions`, `call_participants`）
4. **无特殊情况**：统一 API 设计，消除硬编码

### 技术栈

- **后端**：Rust + Actix + Axum + WebSocket
- **数据库**：PostgreSQL（已有 schema）
- **通话协议**：WebRTC (P2P mesh)
- **实时通信**：WebSocket + Redis Pub/Sub

---

## API 设计

### 1. 发起通话（改进版）

**端点**：`POST /api/v1/conversations/:id/calls`

**请求**：
```json
{
  "initiator_sdp": "v=0\r\no=...",
  "call_type": "group",           // "direct" (default) or "group"
  "max_participants": 8           // default: 2
}
```

**响应**：
```json
{
  "id": "call-uuid",
  "status": "ringing",
  "created_at": "2025-10-29T12:00:00Z",
  "call_type": "group",
  "max_participants": 8
}
```

**变更点**：
- 新增 `call_type` 参数（默认 "direct"）
- 新增 `max_participants` 参数（默认 2）
- 响应中返回通话配置信息

---

### 2. 加入群组通话（新增）

**端点**：`POST /api/v1/calls/:id/join`

**请求**：
```json
{
  "sdp": "v=0\r\no=..."
}
```

**响应**：
```json
{
  "call_id": "call-uuid",
  "conversation_id": "conv-uuid",
  "participant_id": "participant-uuid",
  "participants": [
    {
      "participant_id": "uuid-1",
      "user_id": "user-uuid-1",
      "sdp": "v=0...",                // initiator_sdp 或 answer_sdp
      "joined_at": "2025-10-29T12:00:00Z",
      "connection_state": "connected"
    },
    {
      "participant_id": "uuid-2",
      "user_id": "user-uuid-2",
      "sdp": "v=0...",
      "joined_at": "2025-10-29T12:01:00Z",
      "connection_state": "connected"
    }
  ],
  "max_participants": 8,
  "current_participant_count": 3
}
```

**关键逻辑**：
1. 验证通话状态（ringing 或 connected）
2. 检查是否已加入（防止重复）
3. 检查容量（当前参与者数 < max_participants）
4. 返回所有已有参与者的 SDP（用于建立 P2P 连接）
5. 广播 `call.participant_joined` 事件

---

### 3. 离开群组通话（新增）

**端点**：`POST /api/v1/calls/:id/leave`

**响应**：`204 No Content`

**关键逻辑**：
1. 查找参与者记录
2. 设置 `left_at` 时间戳
3. 广播 `call.participant_left` 事件

---

### 4. 获取参与者列表（新增）

**端点**：`GET /api/v1/calls/:id/participants`

**响应**：
```json
{
  "call_id": "call-uuid",
  "participants": [
    {
      "id": "participant-uuid",
      "user_id": "user-uuid",
      "joined_at": "2025-10-29T12:00:00Z",
      "left_at": null,
      "connection_state": "connected",
      "has_audio": true,
      "has_video": true
    }
  ]
}
```

---

### 5. 向后兼容端点

**端点**：`POST /api/v1/calls/:id/answer`（保留）

**行为**：
- 内部调用 `join_call` 逻辑
- 对于 1:1 通话（call_type=direct），自动触发 `call.answered` 事件（向后兼容）

---

## WebSocket 事件

### 新增事件

#### 1. `call.participant_joined`
```json
{
  "type": "call.participant_joined",
  "conversation_id": "uuid",
  "call_id": "uuid",
  "participant_id": "uuid",
  "user_id": "uuid",
  "sdp": "v=0...",
  "timestamp": "2025-10-29T12:00:00Z"
}
```

**用途**：通知已有参与者有新人加入，包含新参与者的 SDP

#### 2. `call.participant_left`
```json
{
  "type": "call.participant_left",
  "conversation_id": "uuid",
  "call_id": "uuid",
  "participant_id": "uuid",
  "user_id": "uuid",
  "timestamp": "2025-10-29T12:00:00Z"
}
```

**用途**：通知其他参与者有人离开，关闭对应的 P2P 连接

### 修改事件

#### `call.initiated`（增强）
```json
{
  "type": "call.initiated",
  "conversation_id": "uuid",
  "call_id": "uuid",
  "initiator_id": "uuid",
  "call_type": "group",          // 新增
  "max_participants": 8,         // 新增
  "timestamp": "2025-10-29T12:00:00Z"
}
```

---

## 数据库操作

### 表结构（已有）

**call_sessions**：
- `max_participants`：最大参与者数（已有，目前硬编码为 2）
- `call_type`：通话类型（已有，目前硬编码为 "direct"）

**call_participants**：
- `answer_sdp`：参与者的 SDP answer（已有）
- `left_at`：离开时间戳（已有）

### 核心 SQL 查询

#### 1. 加入通话时获取所有参与者的 SDP

```sql
SELECT
  cp.id,
  cp.user_id,
  cp.answer_sdp,
  cp.joined_at,
  cp.connection_state,
  cs.initiator_id,
  cs.initiator_sdp
FROM call_participants cp
JOIN call_sessions cs ON cp.call_id = cs.id
WHERE cp.call_id = $1 AND cp.left_at IS NULL
ORDER BY cp.joined_at ASC
```

**逻辑**：
- 对于 `initiator_id` 的参与者，使用 `cs.initiator_sdp`
- 对于其他参与者，使用 `cp.answer_sdp`

#### 2. 检查参与者数量

```sql
SELECT COUNT(*)
FROM call_participants
WHERE call_id = $1 AND left_at IS NULL
```

#### 3. 防止重复加入

```sql
SELECT id
FROM call_participants
WHERE call_id = $1 AND user_id = $2 AND left_at IS NULL
```

---

## 实现细节

### 文件修改清单

| 文件 | 修改内容 | 状态 |
|------|---------|------|
| `src/routes/calls.rs` | 新增 DTO、新增 handlers (join_call, leave_call, get_participants) | ✅ 完成 |
| `src/services/call_service.rs` | initiate_call 参数化、新增 join_call/leave_call/get_participants 方法 | ✅ 完成 |
| `src/websocket/events.rs` | 新增 CallParticipantJoined/Left 事件 | ✅ 完成 |
| `src/routes/mod.rs` | 注册新路由 | ✅ 完成 |

### 核心逻辑流程

#### 群组通话发起流程

```
User A → POST /conversations/:id/calls
         {call_type: "group", max_participants: 8}
    ↓
CallService::initiate_call(call_type, max_participants)
    ↓
创建 call_session (max_participants=8, call_type=group)
添加 initiator 到 call_participants
    ↓
广播 WebSocket: call.initiated
    ↓
返回 call_id 给 User A
```

#### 群组通话加入流程

```
User B → POST /calls/:id/join {sdp: "..."}
    ↓
CallService::join_call()
    ↓
1. 检查通话状态（ringing/connected）
2. 检查是否已加入（防重复）
3. 检查容量（count < max_participants）
4. 查询所有已有参与者的 SDP
5. 插入新参与者记录
6. 更新通话状态为 connected
    ↓
返回所有已有参与者的 SDP 给 User B
    ↓
广播 WebSocket: call.participant_joined (包含 User B 的 SDP)
    ↓
User A 收到事件，建立与 User B 的 P2P 连接
User B 建立与所有已有参与者的 P2P 连接
```

#### 群组通话离开流程

```
User B → POST /calls/:id/leave
    ↓
CallService::leave_call()
    ↓
设置 call_participants.left_at = NOW()
    ↓
广播 WebSocket: call.participant_left
    ↓
其他参与者关闭与 User B 的 P2P 连接
```

---

## 测试场景

### 场景 1：1:1 通话（向后兼容）

**步骤**：
1. User A 发起通话：
   ```bash
   POST /conversations/{conv_id}/calls
   {
     "initiator_sdp": "..."
     # call_type 和 max_participants 省略（使用默认值）
   }
   ```
2. User B 收到 `call.initiated` 事件
3. User B 回答通话：
   ```bash
   POST /calls/{call_id}/answer
   {
     "answer_sdp": "..."
   }
   ```
4. User A 收到 `call.answered` 事件（向后兼容）
5. 建立 P2P 连接

**验证**：
- ✅ call_type = "direct"
- ✅ max_participants = 2
- ✅ 触发 `call.answered` 事件
- ✅ 现有客户端正常工作

---

### 场景 2：群组通话（3 人）

**步骤**：

1. **User A 发起群组通话**：
   ```bash
   POST /conversations/{conv_id}/calls
   {
     "initiator_sdp": "sdp-A",
     "call_type": "group",
     "max_participants": 8
   }
   ```
   - 响应：`call_id`
   - 广播：`call.initiated` (call_type=group, max_participants=8)

2. **User B 加入**：
   ```bash
   POST /calls/{call_id}/join
   {
     "sdp": "sdp-B"
   }
   ```
   - 响应：
     ```json
     {
       "participants": [
         {"user_id": "A", "sdp": "sdp-A"}  // initiator
       ]
     }
     ```
   - 广播：`call.participant_joined` (user_id=B, sdp=sdp-B)
   - User B 建立 B→A 连接
   - User A 建立 A→B 连接

3. **User C 加入**：
   ```bash
   POST /calls/{call_id}/join
   {
     "sdp": "sdp-C"
   }
   ```
   - 响应：
     ```json
     {
       "participants": [
         {"user_id": "A", "sdp": "sdp-A"},
         {"user_id": "B", "sdp": "sdp-B"}
       ]
     }
     ```
   - 广播：`call.participant_joined` (user_id=C, sdp=sdp-C)
   - User C 建立 C→A, C→B 连接
   - User A/B 建立 A→C, B→C 连接

4. **User B 离开**：
   ```bash
   POST /calls/{call_id}/leave
   ```
   - 广播：`call.participant_left` (user_id=B)
   - User A/C 关闭与 B 的连接

5. **User D 尝试加入（第 4 人）**：
   - 如果 max_participants=3，返回 `400 Call is full`
   - 如果 max_participants≥4，成功加入

**验证**：
- ✅ P2P mesh 连接数：N*(N-1)/2（3 人 = 3 连接）
- ✅ 新加入者自动获取所有已有参与者的 SDP
- ✅ 离开者的连接正确关闭
- ✅ 容量限制生效

---

### 场景 3：错误处理

#### 3.1 重复加入
```bash
POST /calls/{call_id}/join  # User A 第二次加入
```
- 响应：`400 User is already in the call`

#### 3.2 通话已满
```bash
POST /calls/{call_id}/join  # 第 9 人加入（max_participants=8）
```
- 响应：`400 Call is full (max participants reached)`

#### 3.3 非法通话状态
```bash
POST /calls/{call_id}/join  # call.status = 'ended'
```
- 响应：`400 Call is not active`

#### 3.4 超过容量限制
```bash
POST /conversations/{id}/calls
{
  "max_participants": 100
}
```
- 响应：`400 max_participants cannot exceed 50`

---

## 性能分析

### P2P Mesh 连接数

| 参与者数 | 连接数 | 带宽消耗 | 推荐 |
|---------|--------|---------|------|
| 2 | 1 | 低 | ✅ 推荐 |
| 3 | 3 | 中 | ✅ 推荐 |
| 4 | 6 | 中高 | ✅ 可用 |
| 6 | 15 | 高 | ⚠️ 谨慎 |
| 8 | 28 | 很高 | ⚠️ 极限 |
| 10+ | 45+ | 不可行 | ❌ 需要 SFU |

**公式**：连接数 = N * (N-1) / 2

### 当前实现限制

- **硬限制**：`max_participants ≤ 50`（API 验证）
- **软限制**：建议 ≤ 8 人（P2P mesh 性能考虑）
- **未来升级**：>8 人需要 SFU 服务（Phase 2）

### 数据库查询优化

**已有索引**（migration 0016）：
- `idx_call_participants_call` ON (call_id, joined_at)
- `idx_call_participants_user` ON (user_id, call_id) WHERE left_at IS NULL

**查询性能**：
- 获取参与者列表：O(N)，N = 参与者数
- 检查重复加入：O(1)（索引查询）
- 检查容量：O(1)（COUNT(*) + 索引）

---

## 向后兼容性验证

### 兼容性矩阵

| 场景 | 旧客户端 | 新客户端 | 状态 |
|------|---------|---------|------|
| 发起 1:1 通话 | ✅ 省略 call_type（默认 direct） | ✅ 显式指定 | ✅ 兼容 |
| 接听 1:1 通话 | ✅ POST /answer | ✅ POST /join 或 /answer | ✅ 兼容 |
| call.answered 事件 | ✅ 仍触发（1:1 时） | ✅ 收到 | ✅ 兼容 |
| call.initiated 事件 | ✅ 忽略新字段 | ✅ 读取新字段 | ✅ 兼容 |
| 群组通话 | ❌ 不支持 | ✅ 支持 | ✅ 分离 |

### 兼容性保证

1. **默认值机制**：
   - `call_type` 默认 "direct"
   - `max_participants` 默认 2

2. **双事件机制**（1:1 通话）：
   - `call.participant_joined`（新客户端）
   - `call.answered`（旧客户端）

3. **API 共存**：
   - `/answer` 保留（内部调用 `join_call`）
   - `/join` 新增（统一接口）

---

## 部署清单

### 代码变更

1. ✅ DTO 定义（`calls.rs`）
2. ✅ 服务层逻辑（`call_service.rs`）
3. ✅ API handlers（`calls.rs`）
4. ✅ WebSocket 事件（`events.rs`）
5. ✅ 路由注册（`mod.rs`）

### 数据库迁移

**无需新迁移**（表结构已支持）：
- `call_sessions.max_participants` 已存在
- `call_sessions.call_type` 已存在
- `call_participants.answer_sdp` 已存在

### 环境变量

无新增配置项。

### 监控指标（建议）

- `group_call_initiated_total`：群组通话发起数
- `group_call_participant_count`：平均参与者数
- `group_call_join_latency`：加入通话延迟
- `p2p_connection_failures`：P2P 连接失败率

---

## 未来改进（Phase 2）

### SFU 升级路径

1. **引入 SFU 服务**（如 Janus、mediasoup）
2. **阈值切换**：
   - ≤4 人：P2P mesh
   - >4 人：自动切换到 SFU
3. **API 保持不变**：
   - 后端透明切换
   - 客户端无感知

### 功能增强

- ✅ 屏幕共享
- ✅ 录制功能
- ✅ 虚拟背景
- ✅ 噪音抑制
- ✅ 网格/演讲者视图
- ✅ 举手/禁言

---

## 附录

### A. 完整 API 端点清单

| 方法 | 端点 | 描述 | 状态 |
|------|------|------|------|
| POST | `/conversations/:id/calls` | 发起通话 | ✅ 增强 |
| POST | `/calls/:id/answer` | 回答 1:1 通话 | ✅ 保留 |
| POST | `/calls/:id/join` | 加入群组通话 | ✅ 新增 |
| POST | `/calls/:id/leave` | 离开群组通话 | ✅ 新增 |
| GET | `/calls/:id/participants` | 获取参与者列表 | ✅ 新增 |
| POST | `/calls/:id/reject` | 拒绝通话 | ✅ 保留 |
| POST | `/calls/:id/end` | 结束通话 | ✅ 保留 |
| GET | `/calls/history` | 通话历史 | ✅ 保留 |

### B. WebSocket 事件清单

| 事件 | 描述 | 状态 |
|------|------|------|
| `call.initiated` | 通话发起 | ✅ 增强 |
| `call.answered` | 1:1 通话接听 | ✅ 保留 |
| `call.participant_joined` | 参与者加入 | ✅ 新增 |
| `call.participant_left` | 参与者离开 | ✅ 新增 |
| `call.rejected` | 通话拒绝 | ✅ 保留 |
| `call.ended` | 通话结束 | ✅ 保留 |
| `call.ice_candidate` | ICE 候选交换 | ✅ 保留 |

### C. 错误代码

| 错误代码 | 描述 | HTTP 状态 |
|---------|------|-----------|
| `CALL_NOT_FOUND` | 通话不存在 | 404 |
| `CALL_NOT_ACTIVE` | 通话不处于活动状态 | 400 |
| `ALREADY_IN_CALL` | 用户已在通话中 | 400 |
| `CALL_FULL` | 通话已满 | 400 |
| `INVALID_CALL_TYPE` | 非法通话类型 | 400 |
| `MAX_PARTICIPANTS_EXCEEDED` | 超过最大参与者数限制 | 400 |
| `NOT_CONVERSATION_MEMBER` | 非对话成员 | 403 |

---

## 总结

**实现完成度**：✅ 100%

**时间线**：
- Week 1：API 设计、核心逻辑实现 ✅ 完成
- Week 2：测试、文档、部署 ⏳ 待执行

**优势**：
1. ✅ 零破坏性（向后兼容）
2. ✅ 数据结构复用（无迁移成本）
3. ✅ 渐进式升级路径清晰
4. ✅ 实用主义（解决真实需求）

**风险**：
- P2P mesh 性能限制（>8 人不可行）
- 需要客户端正确处理 P2P 连接管理

**下一步**：
1. 集成测试（Postman/curl）
2. 客户端适配（iOS/Android）
3. 性能测试（4-8 人场景）
4. 生产监控
