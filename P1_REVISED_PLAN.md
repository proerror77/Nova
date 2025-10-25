# 🔧 P1 任务修正计划 - 基于代码审查

**审查完成时间**: 2025-10-25
**计划生效**: 立即
**更新原因**: 代码审查发现 E2E 加密仍是占位符

---

## 📊 计划变更摘要

### 原计划 (6-8 工时)
```
P1: 消息加密完成
├── 前端: 消息加密实现 (TweetNaCl.js) - 2天
├── iOS: 视频上传 (分块+断点续传) - 2天
└── 集成测试 - 1天
总计: ~6-8天
```

### 修正计划 (12-15 工时)
```
P1: 前端 E2E 加密系统
├── CRITICAL: 实现真实 E2E 加密 - 3天 (新发现)
├── 消息加密集成 - 1天
├── 密钥管理 - 1.5天
├── 测试覆盖 - 1.5天
└── 安全审查 - 0.5天
小计: ~7.5天

P2: iOS 视频上传
├── 实现分块上传 - 1.5天
├── 断点续传 - 1天
└── 进度跟踪 - 0.5天
小计: ~3天

P2: 跨平台集成
├── 端到端加密验证 - 1天
├── 消息同步测试 - 1天
└── 性能测试 - 0.5天
小计: ~2.5天

总计: ~12.5天
```

---

## 🎯 P1A: 前端 E2E 加密系统 (7.5 天)

### 🔴 CRITICAL: E2E 加密实现 (3 天)

**问题根源**: `client.ts` 是占位符
```typescript
// ❌ 现在的代码 (不安全)
const ciphertext = Buffer.from(plaintext, 'utf8').toString('base64');
const nonce = Math.random().toString(36).slice(2);

// ✅ 需要的代码 (真实加密)
// 使用 TweetNaCl.js 或 libsodium.js
```

**工作项**:

#### 1. 库选择与集成 (4h)
- [ ] 评估 TweetNaCl.js vs libsodium.js
  - TweetNaCl: 简单、13KB、推荐
  - libsodium: 功能多、60KB
- [ ] 安装选定的库 `npm install tweetnacl-js`
- [ ] 验证浏览器兼容性
- [ ] 性能基准测试（加密 1KB 消息的耗时）

**决策**: **推荐 TweetNaCl.js**
- 理由：简单、专注、大小合适
- 缺点：功能不如 libsodium 多
- 如果需要更多功能后续可升级

#### 2. 密钥管理设计 (8h)

**关键问题**：密钥从何而来？

**Option A: 密码派生密钥** (推荐用于演示)
```typescript
// 使用用户密码派生加密密钥
// PBKDF2: 密码 + salt → 32 字节密钥
// 优点：无需额外基础设施
// 缺点：每个用户加密密钥不同，设备间不能共享
```

**Option B: 服务器分配密钥**
```typescript
// 后端生成密钥，通过安全通道发送给前端
// 优点：多设备支持
// 缺点：需要后端支持，增加复杂度
```

**Option C: 混合方案** (生产建议)
```typescript
// 用户主密钥 (从密码派生) + 服务器短期密钥
// 优点：兼顾安全和便利
// 缺点：最复杂
```

**建议进度**:
- Week 1: 实现 Option A（演示用）
- Week 2+: 规划 Option C（生产用）

**实现文件**: 新文件 `keyManagement.ts`
```typescript
export interface KeyMaterial {
  key: Uint8Array;           // 32 字节 NaCl 密钥
  salt: Uint8Array;          // PBKDF2 salt
  iterations: number;        // PBKDF2 迭代次数
}

export async function deriveKeyFromPassword(
  password: string,
  salt?: Uint8Array
): Promise<KeyMaterial> {
  // PBKDF2 with 100,000 iterations
  // 返回 KeyMaterial
}

export async function verifyPasswordWithKey(
  password: string,
  keyMaterial: KeyMaterial
): Promise<boolean> {
  // 验证密码是否匹配
}
```

#### 3. 消息加密/解密 API (6h)

**替换 `client.ts`**:
```typescript
import nacl from 'tweetnacl-js';

export async function encryptMessage(
  plaintext: string,
  sharedKey: Uint8Array
): Promise<EncryptedMessage> {
  // plaintext → NaCl box 加密
  // 返回 { ciphertext, nonce, ephemeralPublicKey }
}

export async function decryptMessage(
  encrypted: EncryptedMessage,
  sharedKey: Uint8Array
): Promise<string> {
  // 解密 ciphertext
  // 返回 plaintext
  // 失败时抛出异常 (fail hard)
}
```

**关键决策**:
- [ ] 使用 box 加密（共享秘密密钥）还是 secretbox（对称密钥）？
  - 推荐：secretbox（简单，适合聊天）
- [ ] 如何处理 nonce？
  - 推荐：每条消息随机生成新 nonce
- [ ] Ciphertext 格式？
  ```json
  {
    "v": 1,                          // 版本
    "ciphertext": "base64string",    // 加密数据
    "nonce": "base64string",         // NaCl nonce
    "algorithm": "nacl-box"          // 算法标识
  }
  ```

**错误处理** (Linus 原则: Fail Hard)
```typescript
export async function decryptMessage(encrypted, key) {
  try {
    // ... 解密逻辑
  } catch (error) {
    // 不要返回空字符串或 null
    // 直接抛出异常，让上层处理
    throw new DecryptionError('Failed to decrypt message', { cause: error });
  }
}

// 上层处理
try {
  const plaintext = await decryptMessage(encrypted, key);
} catch (error) {
  // 用户看到："无法解密此消息"
  // 不隐藏错误
}
```

### 📝 消息格式集成 (1 天)

**当前**:
```json
{
  "sender_id": "uuid",
  "plaintext": "hello",
  "idempotency_key": "uuid"
}
```

**修改为**:
```json
{
  "sender_id": "uuid",
  "encrypted": {
    "v": 1,
    "ciphertext": "...",
    "nonce": "...",
    "algorithm": "nacl-secretbox"
  },
  "idempotency_key": "uuid"
}
```

**修改的文件**:
- [ ] `messagingStore.ts` - `sendMessage()` 调用加密
- [ ] `messagingStore.ts` - `onMessage()` 调用解密
- [ ] 后端 API - 同时支持旧格式和新格式（兼容性）

**代码示例**:
```typescript
// messagingStore.ts - sendMessage
sendMessage: async (conversationId, userId, plaintext) => {
  const idempotencyKey = crypto.randomUUID();

  try {
    // ✅ 新增：加密消息
    const encrypted = await encryptMessage(plaintext, encryptionKey);

    const res = await fetch(`${base}/conversations/${conversationId}/messages`, {
      method: 'POST',
      body: JSON.stringify({
        sender_id: userId,
        encrypted,           // ✅ 发送加密数据而不是 plaintext
        idempotency_key: idempotencyKey,
      }),
    });
    // ... 后续逻辑
  }
}

// messagingStore.ts - onMessage (WebSocket)
onMessage: (payload) => {
  try {
    const m = payload?.message;
    if (!m) return;

    // ✅ 新增：解密消息
    let displayText = m.plaintext || ''; // 兼容旧消息
    if (m.encrypted) {
      displayText = await decryptMessage(m.encrypted, encryptionKey);
    }

    // 显示消息...
  }
}
```

### 🧪 测试覆盖 (1.5 天)

**单元测试** (0.5天):
```typescript
describe('加密系统', () => {
  it('加密后解密应恢复原文', async () => {
    const plaintext = '你好世界';
    const key = generateTestKey();

    const encrypted = await encryptMessage(plaintext, key);
    const decrypted = await decryptMessage(encrypted, key);

    expect(decrypted).toBe(plaintext);
  });

  it('错误的密钥应解密失败', async () => {
    const encrypted = await encryptMessage('secret', key1);

    expect(() => decryptMessage(encrypted, key2))
      .rejects.toThrow();
  });

  it('修改 ciphertext 应解密失败', async () => {
    const encrypted = await encryptMessage('secret', key);
    encrypted.ciphertext = encrypted.ciphertext.slice(0, -5) + 'xxxxx';

    expect(() => decryptMessage(encrypted, key))
      .rejects.toThrow();
  });
});
```

**集成测试** (1天):
- [ ] Web → iOS 消息加密互操作性
- [ ] 离线消息加密持久化
- [ ] 旧消息（未加密）的兼容性显示
- [ ] 性能：1000 条消息加密耗时 < 1s

### 🔍 安全审查 (0.5天)

**自检清单**:
- [ ] 没有硬编码密钥
- [ ] 密钥仅在内存存储
- [ ] 使用加密学安全的随机数生成
- [ ] 错误不泄露加密细节
- [ ] 向后兼容旧消息
- [ ] 没有时序攻击风险

**建议**: 如果可能，请安全专家审查（非阻塞）

---

## 📅 详细时间表

### Week 1 (本周) - 7 天

| 时段 | 任务 | 工时 | 状态 |
|------|------|------|------|
| Day 1 (今天) | ✅ 代码审查完成 | 1h | ✅ 完成 |
| Day 2 | 库选择 + 集成 TweetNaCl | 4h | 📅 今天开始 |
| Day 3-4 | 密钥管理实现 | 8h | 📅 周三 |
| Day 5 | 消息加密/解密 API | 6h | 📅 周四 |
| Day 6 | 消息格式修改 + 集成 | 4h | 📅 周五 |
| Day 7 | 单元测试 + 基本集成测试 | 4h | 📅 周六 |

**预期完成**: 本周日 (10月31日)

### Week 2 (下周) - 5 天

| 时段 | 任务 | 工时 | 状态 |
|------|------|------|------|
| Day 1 | E2E 集成测试 (Web+iOS) | 2h | 📅 |
| Day 2 | 安全审查 | 2h | 📅 |
| Day 3 | 缺陷修复 | 2h | 📅 |
| Day 4 | 性能优化 | 2h | 📅 |
| Day 5 | 文档 + 部署准备 | 2h | 📅 |

**预期完成**: 第二周五 (11月7日)

---

## 🔄 重新优先级排列 (P1 -> P2)

### 原 P1 项目变更

**维持 P1**: 前端消息加密系统 (本文档) ✅

**降级为 P2**: iOS 视频上传
- 原因：现有消息系统不依赖视频
- 建议：先完成消息加密，再做视频
- 预计：下下周 (11月15日之后)

**新增 P1B**: 推送通知基础
- 原因：用户需要看到新消息
- 优先级：在 E2E 加密之后
- 预计：11月10日开始

---

## 🎯 成功指标

### 功能指标
- [ ] Web 发送加密消息到后端
- [ ] iOS 显示加密消息
- [ ] 消息加密密钥正确派生
- [ ] 旧消息（未加密）仍能正常显示
- [ ] 离线消息正确加密存储

### 性能指标
- [ ] 加密 1KB 消息 < 100ms
- [ ] 加密 10,000 消息批处理 < 10s
- [ ] 内存增长 < 20MB

### 质量指标
- [ ] 单元测试覆盖率 > 80%
- [ ] 安全审查通过
- [ ] 零加密相关的 bug 报告（一周内）

---

## ⚠️ 风险分析

### 高风险
1. **密钥管理错误**
   - 后果：所有消息都不安全
   - 缓解：提前安全审查，从简单实现开始

2. **与 iOS 互操作性**
   - 后果：跨平台消息失败
   - 缓解：早期集成测试，iOS 同步实现加密

### 中风险
3. **向后兼容性破坏**
   - 后果：用户看不到旧消息
   - 缓解：同时支持加密和未加密格式

4. **性能下降**
   - 后果：UI 卡顿
   - 缓解：性能测试，必要时异步加密

### 低风险
5. **库依赖问题**
   - 后果：安全更新需要时间
   - 缓解：选择成熟的库（TweetNaCl 已被广泛使用）

---

## 💡 Linus 式总结

**问题**：代码给了虚假的安全感（占位符加密）

**解决**：用真实的加密替换

**原则**：
- 不要假装完成功能
- 从简单的 Option A 开始，不要过度工程
- 测试必不可少（加密是关键）
- 没有"密钥管理会很复杂"的借口（Option A 很简单）

**进度预期**：
- 实现 (3-4天)
- 测试 (2-3天)
- 审查 (0.5天)
- 修复 (1天)
- **总计**: 7天（虽然标题说 3 天，这是合理的预期）

---

## 📝 检查清单

### Day 1 (今天) - 计划确认
- [ ] 用户确认这个修正计划
- [ ] 选择密钥管理方案（推荐 Option A）
- [ ] 选择加密库（推荐 TweetNaCl）

### Day 2-3 - 实现
- [ ] 库集成完成
- [ ] 密钥管理 `keyManagement.ts` 完成
- [ ] 基础加密 API 完成

### Day 4-5 - 集成
- [ ] 消息发送加密集成
- [ ] 消息接收解密集成
- [ ] 离线队列支持

### Day 6-7 - 测试
- [ ] 单元测试通过 > 80% 覆盖率
- [ ] 集成测试通过
- [ ] Web + iOS 互操作性测试

### Week 2 - 最终化
- [ ] 安全审查通过
- [ ] 性能测试通过
- [ ] 文档完成

---

**由 Linus 制定 - 基于代码审查**
**关键原则**: "承认现状，然后解决它"

May the Force be with you.
