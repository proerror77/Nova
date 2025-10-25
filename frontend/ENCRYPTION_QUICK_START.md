# LocalStorage Encryption - Quick Start Guide

## 🚀 快速开始（5 分钟）

### 1. 初始化加密（App.tsx 或认证上下文）

```typescript
import { storageEncryption } from './services/encryption/localStorage';

// 在用户登录成功后
async function handleLoginSuccess(userId: string, sessionToken: string) {
  // 选项 A: 从会话令牌派生密钥（推荐）
  const keyMaterial = await deriveKey(sessionToken, userId);
  await storageEncryption.initialize(keyMaterial);

  // 选项 B: 生成随机密钥（简单）
  // await storageEncryption.generateKey();
}

// 密钥派生辅助函数（PBKDF2）
async function deriveKey(sessionToken: string, userId: string): Promise<Uint8Array> {
  const password = new TextEncoder().encode(sessionToken);
  const salt = new TextEncoder().encode(`nova-storage-${userId}`);

  const keyMaterial = await crypto.subtle.importKey('raw', password, 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: 100000, hash: 'SHA-256' },
    keyMaterial,
    256
  );

  return new Uint8Array(bits);
}
```

### 2. 使用加密队列（消息组件）

```typescript
import { OfflineQueue } from './services/offlineQueue/Queue';

const queue = new OfflineQueue();

// 发送消息（自动加密存储）
async function sendMessage(conversationId: string, text: string) {
  const userId = getCurrentUserId(); // 从认证状态获取

  if (navigator.onLine) {
    try {
      await sendToServer(conversationId, text);
    } catch (error) {
      // 网络错误，入队等待
      await queue.enqueue({
        conversationId,
        userId,
        plaintext: text,
        idempotencyKey: `${userId}-${Date.now()}-${Math.random()}`
      });
    }
  } else {
    // 离线，直接入队
    await queue.enqueue({
      conversationId,
      userId,
      plaintext: text,
      idempotencyKey: `${userId}-${Date.now()}-${Math.random()}`
    });
  }
}
```

### 3. 处理网络恢复（App.tsx）

```typescript
// 监听网络状态
useEffect(() => {
  const handleOnline = async () => {
    const queue = new OfflineQueue();
    const messages = await queue.drain();

    for (const msg of messages) {
      try {
        await sendToServer(msg.conversationId, msg.plaintext);
      } catch (error) {
        // 发送失败，重新入队
        await queue.enqueue(msg);
      }
    }
  };

  window.addEventListener('online', handleOnline);
  return () => window.removeEventListener('online', handleOnline);
}, []);
```

### 4. 清理（登出时）

```typescript
async function handleLogout() {
  // 1. 清空离线队列
  const queue = new OfflineQueue();
  await queue.clear();

  // 2. 销毁加密密钥
  storageEncryption.destroy();

  // 3. 清空 localStorage（可选但推荐）
  localStorage.clear();
}
```

## 📋 完整的 React Hook 示例

```typescript
// useMessaging.ts
import { useState, useEffect } from 'react';
import { storageEncryption } from './services/encryption/localStorage';
import { OfflineQueue } from './services/offlineQueue/Queue';

export function useMessaging(userId: string | null, sessionToken: string | null) {
  const [queue] = useState(() => new OfflineQueue());
  const [isOnline, setIsOnline] = useState(navigator.onLine);

  // 初始化加密
  useEffect(() => {
    if (userId && sessionToken) {
      deriveKey(sessionToken, userId)
        .then(key => storageEncryption.initialize(key))
        .catch(console.error);
    }
  }, [userId, sessionToken]);

  // 监听网络状态
  useEffect(() => {
    const handleOnline = () => setIsOnline(true);
    const handleOffline = () => setIsOnline(false);

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  // 处理离线队列
  useEffect(() => {
    if (isOnline) {
      processQueue();
    }
  }, [isOnline]);

  const processQueue = async () => {
    const messages = await queue.drain();
    for (const msg of messages) {
      try {
        await sendToServer(msg.conversationId, msg.plaintext);
      } catch (error) {
        await queue.enqueue(msg);
      }
    }
  };

  const sendMessage = async (conversationId: string, text: string) => {
    if (!userId) return;

    if (isOnline) {
      try {
        await sendToServer(conversationId, text);
      } catch (error) {
        await queue.enqueue({
          conversationId,
          userId,
          plaintext: text,
          idempotencyKey: `${userId}-${Date.now()}-${Math.random()}`
        });
      }
    } else {
      await queue.enqueue({
        conversationId,
        userId,
        plaintext: text,
        idempotencyKey: `${userId}-${Date.now()}-${Math.random()}`
      });
    }
  };

  return { sendMessage, isOnline, queueSize: queue.size() };
}

// 辅助函数
async function deriveKey(sessionToken: string, userId: string): Promise<Uint8Array> {
  const password = new TextEncoder().encode(sessionToken);
  const salt = new TextEncoder().encode(`nova-storage-${userId}`);
  const keyMaterial = await crypto.subtle.importKey('raw', password, 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt, iterations: 100000, hash: 'SHA-256' },
    keyMaterial,
    256
  );
  return new Uint8Array(bits);
}

async function sendToServer(conversationId: string, text: string): Promise<void> {
  const response = await fetch(`/api/conversations/${conversationId}/messages`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${localStorage.getItem('token')}`
    },
    body: JSON.stringify({ text })
  });

  if (!response.ok) throw new Error('Failed to send message');
}
```

## 🎯 使用 Hook 的组件示例

```typescript
// MessageComposer.tsx
import { useState } from 'react';
import { useMessaging } from './useMessaging';
import { useAuth } from './useAuth';

export function MessageComposer({ conversationId }: { conversationId: string }) {
  const { userId, sessionToken } = useAuth();
  const { sendMessage, isOnline } = useMessaging(userId, sessionToken);
  const [text, setText] = useState('');
  const [sending, setSending] = useState(false);

  const handleSend = async () => {
    if (!text.trim()) return;

    setSending(true);
    try {
      await sendMessage(conversationId, text);
      setText('');
    } catch (error) {
      console.error('Failed to send message', error);
    } finally {
      setSending(false);
    }
  };

  return (
    <div>
      <textarea
        value={text}
        onChange={e => setText(e.target.value)}
        placeholder="输入消息..."
        disabled={!userId || sending}
      />
      <button onClick={handleSend} disabled={!userId || sending}>
        {sending ? '发送中...' : '发送'}
      </button>
      {!isOnline && (
        <div className="offline-notice">
          ⚠️ 离线模式 - 消息将在网络恢复后发送
        </div>
      )}
    </div>
  );
}
```

## ✅ 检查清单

在部署前确认：

- [ ] 在用户登录后调用 `storageEncryption.initialize()`
- [ ] 在用户登出时调用 `storageEncryption.destroy()`
- [ ] 在用户登出时调用 `queue.clear()`
- [ ] 监听 `online` 事件以处理离线队列
- [ ] 生成唯一的 `idempotencyKey`
- [ ] 处理加密失败的情况（降级到内存模式）
- [ ] 测试完整的登录→发送消息→登出流程

## 🔒 安全最佳实践

### ✅ 必须做
1. 始终在登录后初始化加密
2. 始终在登出时销毁密钥
3. 使用随机 IV（自动处理）
4. 验证解密成功后再使用数据
5. 登出时清空 localStorage

### ❌ 不要做
1. 不要将密钥存储在 localStorage
2. 不要重用 IV
3. 不要将加密用作认证机制
4. 不要信任未验证的解密数据
5. 不要在生产环境记录明文

## 📊 故障处理

### 场景 1: 加密未初始化
```typescript
await queue.enqueue(message);
// ⚠️ 警告: "OfflineQueue: encryption not initialized, not persisting queue"
// 结果: 消息保存在内存中（不持久化）
```

### 场景 2: 损坏的 localStorage 数据
```typescript
await queue.initialize();
// ⚠️ 警告: "OfflineQueue: failed to decrypt queue, discarding"
// 结果: 损坏数据被移除，队列重新开始
```

### 场景 3: 网络错误
```typescript
await sendMessage(conversationId, text);
// ✅ 自动入队，等待网络恢复
```

## 🧪 测试

```bash
# 运行所有加密相关测试
npm test -- src/services/encryption src/services/offlineQueue --run

# 运行可视化验证
npm test -- src/services/encryption/__tests__/visual-verification.test.ts --run
```

## 📚 更多资源

- [完整实现文档](src/services/encryption/README.md)
- [集成示例](src/services/encryption/integration-example.ts)
- [实施总结](LOCALSTORAGE_ENCRYPTION_IMPLEMENTATION.md)
- [安全修复总结](../FRONTEND_SECURITY_FIX_SUMMARY.md)

## 🆘 常见问题

**Q: 用户刷新页面后密钥会丢失吗？**
A: 是的，密钥仅存在内存中。刷新页面需要重新初始化加密。可以从 sessionStorage 或 cookie 中恢复会话令牌来重新派生密钥。

**Q: 如果用户换设备会怎样？**
A: 如果使用会话令牌派生密钥，相同会话令牌会产生相同密钥。如果使用随机密钥，则无法跨设备访问。

**Q: 性能影响如何？**
A: 加密/解密 1KB 数据约 1ms，对用户体验无明显影响。

**Q: 支持哪些浏览器？**
A: 所有支持 Web Crypto API 的现代浏览器（Chrome 37+, Firefox 34+, Safari 11+, Edge 79+）

**Q: 如果解密失败会怎样？**
A: 数据会被自动丢弃，队列重新开始。这是安全的设计选择（宁可丢失数据也不返回损坏数据）。

---

**准备就绪？开始集成吧！** 🚀
