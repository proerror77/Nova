# Nova 前端与iOS API 集成规划

**制定日期**: 2025-10-25
**状态**: 执行阶段
**优先级**: P0 (立即开始)

---

## 📊 执行概览

### 核心问题 (Linus 的三个问题)

1. **"这是个真问题还是臆想出来的?"**
   - ✅ **真实问题**: 前端 60% 完成, iOS 65% 完成, 但关键功能缺失
   - 前端: Like/Comment 未实现, 加密存根, 无路由
   - iOS: 视频上传 0%, Stories 0%, 推送通知 0%, 硬编码 IP 地址

2. **"有更简单的方法吗?"**
   - ✅ **最简方案**: 集中实现关键 API 客户端库
   - 前端使用统一的 `ApiClient` + 特化的 service
   - iOS 统一使用 `NetworkManager` + Repository 模式

3. **"会破坏什么吗?"**
   - ✅ **向后兼容**: 现有 API 保持不变
   - 仅扩展现有层, 不删除任何功能
   - 消息加密可选(现有消息保持兼容)

---

## 🎯 优先级矩阵

| 优先级 | 前端 | iOS | 工作量 | 阻碍 | 完成时间 |
|--------|------|-----|--------|------|---------|
| **P0** | Like/Comment | 修复硬编码IP + Post Creation | 16h | 无 | 2天 |
| **P0** | 认证修复 | 离线队列 + WebSocket修复 | 8h | 无 | 1天 |
| **P1** | 消息加密完成 | 视频上传 | 20h | 无 | 3天 |
| **P1** | 通知系统 | Push通知集成 | 12h | 无 | 2天 |
| **P2** | 故事(Stories) | 故事实现 | 24h | P0完成 | 4天 |
| **P3** | 直播流 | 直播流播放 | 16h | P1完成 | 3天 |

**总计**: ~96小时 = 2-3周 (2人团队)

---

## 🏗️ 分层架构

```
┌─────────────────────────────────────────┐
│           UI Layer (React/SwiftUI)      │
├─────────────────────────────────────────┤
│   Service/ViewModel Layer (API Logic)   │
├─────────────────────────────────────────┤
│    API Client Layer (HTTP + WebSocket)  │
├─────────────────────────────────────────┤
│  Network Layer (Axios/URLSession)       │
├─────────────────────────────────────────┤
│    Backend Services (Port 8080/8085)    │
└─────────────────────────────────────────┘
```

**关键原则**:
- 每层职责单一
- API 客户端完全独立于 UI
- 错误处理集中在 API 层
- 加密/解密在 Service 层处理

---

## P0: 关键修复 (2天, 16h)

### 前端: Like/Comment 实现

**当前问题**:
```tsx
// FeedView.tsx - 当前代码 (垃圾)
const handleLike = () => alert("Coming soon");  // ❌ 这是占位符
```

**应该做**:
```tsx
// services/api/postService.ts - 添加这个
export async function likePost(postId: string) {
  return apiClient.post(`/posts/${postId}/like`, {});
}

export async function unlikePost(postId: string) {
  return apiClient.delete(`/posts/${postId}/like`);
}

export async function createComment(postId: string, content: string) {
  return apiClient.post(`/posts/${postId}/comments`, { content });
}
```

**前端修复清单**:
- [ ] 修复 `AuthContext` token 字段名 (token → accessToken)
- [ ] 实现 `likePost()` 和 `unlikePost()` API 调用
- [ ] 实现 `createComment()` API 调用
- [ ] 添加 Like/Comment 按钮的加载状态
- [ ] 添加错误处理和用户反馈
- [ ] 更新 store 以立即反映 UI 更新
- [ ] 编写测试 (至少 5 个测试用例)

**测试用例**:
1. 点赞成功 → 数字+1, 按钮变色
2. 点赞已存在 → 变为取消赞
3. 网络错误 → 显示重试按钮
4. 评论成功 → 立即显示在列表中
5. 评论失败 → 显示错误提示

---

### iOS: 修复硬编码IP + Post Creation 完成

**当前问题**:
```swift
// AppConfig.swift - 硬编码 IP (不可接受!)
let baseURL = "http://192.168.31.154:8001"  // ❌ 只有一个人能用!
```

**应该做**:
```swift
// AppConfig.swift - 从配置读取
let baseURL = {
  #if DEBUG
    return ProcessInfo.processInfo.environment["API_BASE_URL"] ??
           "http://localhost:8080"
  #else
    return "https://api.nova.social"
  #endif
}()

// 或更好的方法: Info.plist 配置
```

**iOS Post Creation 修复**:
- [ ] 支持视频上传 (当前仅支持图片)
- [ ] 完成 `PostRepository.createPost()` 实现
- [ ] 添加离线队列 (网络失败时保存草稿)
- [ ] 实现图片/视频压缩
- [ ] 添加上传进度条

---

## P0: 认证修复 (1天, 8h)

### 前端: Token 管理修复

**问题**: 多个地方使用不同的字段名
```tsx
// 不一致的命名!
authContext.token          // ❌
useStore().accessToken     // ❌
localStorage.getItem("token")  // ✅

// 应该统一为:
authContext.accessToken    // ✅
refreshToken 分开存储
```

**修复清单**:
- [ ] 统一 token 字段名为 `accessToken`
- [ ] 分离 `refreshToken` 存储
- [ ] 实现自动刷新逻辑 (当 401 时)
- [ ] 使用 Keychain 存储敏感信息 (iOS)
- [ ] 清除登出时的所有 token

---

### iOS: 离线队列 + WebSocket 修复

**问题**: 消息失败时丢失, WebSocket 无心跳

**修复**:
```swift
// 添加离线队列
class OfflineMessageQueue {
  func addMessage(_ msg: Message)
  func syncWhenOnline()
}

// 添加 WebSocket 心跳
class WebSocketManager {
  private var heartbeatTimer: Timer?

  func startHeartbeat() {
    heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
      self.send({"type": "ping"})
    }
  }
}
```

---

## P1: 功能完成 (3-4天, 20-32h)

### 前端: 消息加密完成

**当前**: 加密 API 是存根 (返回原文!)

```tsx
// services/encryption/client.ts - 当前代码
export async function encrypt(plaintext: string) {
  // 返回原文!!! 这是安全漏洞
  return plaintext;
}
```

**应该做** - 使用 TweetNaCl.js 或 libsodium.js

```tsx
import * as nacl from 'tweetnacl';
import { box } from 'tweetnacl-util';

export function encryptMessage(plaintext: string, publicKey: string) {
  const encrypted = nacl.box(
    nacl.util.decodeUTF8(plaintext),
    nacl.util.decodeBase64(publicKey),
    myKeyPair
  );
  return nacl.util.encodeBase64(encrypted);
}
```

**修复清单**:
- [ ] 实现真实 NaCl 加密 (不是存根)
- [ ] 密钥管理 (生成, 交换, 存储)
- [ ] 向后兼容 (旧消息可能未加密)
- [ ] 性能优化 (不要为每条消息加密两次)
- [ ] 编写安全测试

---

### iOS: 视频上传

**新建** `VideoUploadService.swift`:
```swift
class VideoUploadService {
  func uploadVideo(
    _ url: URL,
    title: String,
    description: String,
    progress: @escaping (Double) -> Void
  ) async throws -> Video

  // 分块上传 (支持断点续传)
  private func uploadChunk(_ data: Data, offset: Int) async throws
}
```

**修复清单**:
- [ ] 实现分块上传 (支持断点续传)
- [ ] 添加进度回调
- [ ] 实现重试逻辑
- [ ] 处理网络中断恢复
- [ ] 添加视频压缩选项

---

## P2: 新功能 (4-5天, 24-30h)

### 前端 + iOS: Stories 系统

**数据模型**:
```rust
pub struct Story {
  pub id: Uuid,
  pub user_id: Uuid,
  pub content: String,
  pub media: Option<Vec<Media>>,
  pub created_at: DateTime<Utc>,
  pub expires_at: DateTime<Utc>,  // 24h 后过期
  pub viewers: Vec<Uuid>,
}
```

**实现步骤**:
1. 创建 Story 创建 UI
2. 实现 Story 列表视图
3. 实现 Story 查看器
4. 实现查看历史追踪
5. 测试过期逻辑

---

## P3: 高级功能 (3-4天, 16-24h)

### 直播流集成

**流程**:
```
iOS/Web → RTMP 推流 → Nginx-RTMP → HLS → 播放器
```

**修复清单**:
- [ ] iOS: 添加 RTMP 推流客户端
- [ ] 前端: 添加 HLS 播放器
- [ ] 实时聊天集成
- [ ] 质量切换 (自适应码率)
- [ ] 录制功能

---

## 🔧 立即开始: 第一周任务清单

### 第一天 (周一)

**前端**:
- [ ] PR: 修复 token 字段名 (accessToken)
- [ ] PR: 实现 Like/Comment API 调用
- [ ] 运行测试确保无破坏

**iOS**:
- [ ] PR: 修复硬编码 IP (使用 Info.plist)
- [ ] 验证其他 4 人可以连接
- [ ] 实现 Post Creation 完成

**后端**:
- [ ] 验证所有 API 端点工作正常
- [ ] 检查 Like/Comment 端点 (应该已实现)

### 第二天 (周二)

**前端**:
- [ ] 完成消息加密实现 (使用 TweetNaCl.js)
- [ ] 添加单元测试 (>80% 覆盖率)

**iOS**:
- [ ] 实现离线消息队列
- [ ] 修复 WebSocket 心跳
- [ ] 测试消息可靠性

### 第三天 (周三)

**前端 + iOS**:
- [ ] 集成测试 (两个平台同时发消息)
- [ ] 修复不同步问题
- [ ] 性能测试

---

## 🧪 测试策略

### 单元测试目标
- 前端: >70% 覆盖率 (当前 <10%)
- iOS: >60% 覆盖率 (当前 ~40%)

### 集成测试
```bash
# 场景 1: 跨平台消息
1. iOS 发送消息 → 前端接收
2. 前端回复 → iOS 接收
3. 验证加密/解密工作

# 场景 2: 点赞同步
1. iOS 点赞文章 → 前端刷新显示
2. 前端取消赞 → iOS 刷新显示

# 场景 3: 离线恢复
1. iOS 模拟网络中断
2. 发送消息 (保存到队列)
3. 恢复网络 → 消息自动发送
```

---

## 📱 API 端点映射

### 优先实现 (P0 + P1, 18个端点)

| 端点 | 方法 | 前端 | iOS | 优先级 |
|------|------|------|-----|--------|
| `/posts/{id}/like` | POST | 需要 | 需要 | P0 |
| `/posts/{id}/like` | DELETE | 需要 | 需要 | P0 |
| `/posts/{id}/comments` | POST | 需要 | 需要 | P0 |
| `/posts/{id}/comments` | GET | 需要 | 需要 | P0 |
| `/auth/login` | POST | ❌ 存根 | ✅ | P0 |
| `/auth/refresh` | POST | 需要 | ✅ | P0 |
| `/conversations` | GET | ✅ | ✅ | ✅ |
| `/conversations/{id}/messages` | POST | ✅ | ✅ | ✅ |
| `/videos/upload` | POST | ❌ | ❌ | P1 |
| `/videos/{id}` | GET | ❌ | ❌ | P1 |
| `/stories` | POST | ❌ | ❌ | P2 |
| `/stories/{id}/viewers` | POST | ❌ | ❌ | P2 |
| `/streams/start` | POST | ❌ | ❌ | P3 |
| `/streams/{id}/chat` | WebSocket | ❌ | ❌ | P3 |

---

## 🚀 成功指标

### 第一周末 (P0 完成)
- [ ] 前端点赞/评论功能完全工作
- [ ] iOS 不依赖硬编码 IP
- [ ] Post Creation 支持视频
- [ ] 认证 token 管理统一
- [ ] 消息离线队列工作

### 第二周末 (P1 完成)
- [ ] 消息端到端加密工作
- [ ] iOS 视频上传功能
- [ ] 推送通知集成
- [ ] 跨平台测试通过

### 第三周末 (P2 完成)
- [ ] Stories 系统完全工作
- [ ] 直播流基础功能

---

## 🔐 安全检查清单

- [ ] 所有 token 使用 Keychain (iOS) 或 encrypted storage (前端)
- [ ] HTTPS 用于生产环境
- [ ] 消息使用 E2E 加密
- [ ] CORS 配置正确
- [ ] 敏感端点有速率限制
- [ ] 输入验证在客户端和服务器

---

## 📞 沟通规范

### 日报格式
```markdown
## 日期: YYYY-MM-DD

### 完成
- 任务 A: PR#123 已合并
- 任务 B: 完成度 75%

### 阻碍
- [如有]

### 下一步
- 任务 C: 预计完成时间
```

### PR 规范
- 标题: `feat(frontend): implement like/comment` 或 `fix(ios): hardcoded IP`
- 描述: 包括 "为什么" 和 "测试如何验证"
- 最少 1 个测试用例
- 代码审查要求: 2 人批准

---

## 🎓 推荐阅读

- 前端: `/Users/proerror/Documents/nova/QUICK_API_REFERENCE.md`
- iOS: `/Users/proerror/Documents/nova/iOS_INTEGRATION_GAPS.md`
- 后端: `/Users/proerror/Documents/nova/NOVA_API_REFERENCE.md`

---

**制定者**: Linus (架构审查)
**最后更新**: 2025-10-25
**下次审查**: 完成 P0 后
