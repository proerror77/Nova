# 📋 Nova 项目 - 实际剩余工作清单

**日期**: 2025-10-25
**基础**: 后端代码库审查结果
**现实**: 不是规划功能，而是完成已启动的功能

---

## 🎯 实际情况

后端已经实现了**95%**的功能：
- ✅ Stories API 完成
- ✅ 视频上传 API 完成
- ✅ 消息 API + E2E 加密完成
- ✅ Like/Comment API 完成
- ⚠️ 推送通知 API 框架完成，实现 40%
- ⚠️ 前端集成缺失

**所以真正的工作是**：完成推送通知 + 前端集成

---

## 🔴 CRITICAL: 推送通知最后实现 (3-4 天)

### 后端: FCM 实现 (1.5 天)

**现状**: `fcm_client.rs` 中所有方法都是 `TODO`

```rust
// src/services/notifications/fcm_client.rs
impl FCMClient {
  pub async fn send(&self, token: &str, message: &Message) -> Result<String> {
    // ❌ TODO: 实现实际的 FCM API 调用
    todo!()
  }

  pub async fn send_multicast(&self, tokens: Vec<&str>, message: &Message) -> Result<Vec<String>> {
    // ❌ TODO: 实现
    todo!()
  }
}
```

**需要**:
1. 添加 FCM 库到 `Cargo.toml`
   ```toml
   [dependencies]
   fcm = "0.11"  # 或官方 google-fcm crate
   ```

2. 实现实际的 FCM 发送逻辑
   ```rust
   pub async fn send(&self, token: &str, message: &Message) -> Result<String> {
     // 1. 构造 FCM 消息
     let fcm_message = FirebaseMessage::new(token)
       .notification(Notification::default()
         .title(&message.title)
         .body(&message.body)
       )
       .data(message.data.clone());

     // 2. 发送到 FCM API
     let response = self.client.send(fcm_message).await?;

     // 3. 返回消息 ID
     Ok(response.message_id)
   }
   ```

3. 测试 FCM 集成
   - [ ] 单元测试: 模拟 FCM API
   - [ ] 集成测试: 真实 FCM 令牌测试

**文件**: `backend/user-service/src/services/notifications/fcm_client.rs`

---

### 后端: APNs 实现 (1.5 天)

**现状**: `apns_client.rs` 中所有方法都是 `TODO`

```rust
impl APNsClient {
  pub async fn send(&self, token: &str, message: &APNsMessage) -> Result<()> {
    // ❌ TODO: 实现 HTTP/2 APNs API 调用
    todo!()
  }
}
```

**需要**:
1. 添加 APNs 库 (HTTP/2)
   ```toml
   [dependencies]
   a2 = "0.6"  # Apple Push Notification 库
   ```

2. 配置 APNs 证书加载
   ```rust
   // 从环境变量或文件加载 .p8 证书
   let certificate = std::fs::read("./certs/key.p8")?;
   let client = APNsClientConfig::new()
     .certificate_der(&certificate)?
     .team_id("XXXXXXXXXX")
     .key_id("KEYID1234")
     .build()?;
   ```

3. 实现发送逻辑
   ```rust
   pub async fn send(&self, token: &str, message: &APNsMessage) -> Result<()> {
     let notification = DefaultNotification {
       title: Some(&message.title),
       body: Some(&message.body),
       ..Default::default()
     };

     self.client.send(token, notification).await?;
     Ok(())
   }
   ```

**文件**: `backend/user-service/src/services/notifications/apns_client.rs`

---

### 后端: 数据库表 + API (1 天)

#### 缺失的表

```sql
-- 1. 设备令牌表
CREATE TABLE device_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL UNIQUE,
  platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
  app_version TEXT,
  os_version TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  last_used TIMESTAMP,
  is_active BOOLEAN DEFAULT TRUE,

  INDEX idx_device_tokens_user (user_id),
  INDEX idx_device_tokens_token (token),
  INDEX idx_device_tokens_platform (platform)
);

-- 2. 通知表
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL, -- message, like, comment, follow, story
  related_user_id UUID REFERENCES users(id),
  related_post_id UUID,
  related_conversation_id UUID,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  INDEX idx_notifications_user (user_id, is_read),
  INDEX idx_notifications_created (created_at DESC)
);

-- 3. 推送历史（可选）
CREATE TABLE push_delivery_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id UUID REFERENCES notifications(id),
  device_token_id UUID REFERENCES device_tokens(id),
  status TEXT, -- sent, failed, bounced
  response_code INT,
  error_message TEXT,
  sent_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

  INDEX idx_delivery_logs_notification (notification_id)
);
```

#### 缺失的 API 端点

```rust
// POST /api/v1/devices/register
// Body: { token: string, platform: "ios" | "android" | "web" }
// Response: { device_id: UUID, registered_at: DateTime }
#[post("/devices/register")]
async fn register_device(
  AuthRequired(user_id): AuthRequired,
  body: Json<RegisterDeviceRequest>,
) -> Result<Json<DeviceResponse>> {
  // 保存设备令牌
  // 删除旧令牌（可选）
}

// DELETE /api/v1/devices/{device_id}
// 注销设备
#[delete("/devices/{device_id}")]
async fn unregister_device(
  AuthRequired(user_id): AuthRequired,
  device_id: Path<Uuid>,
) -> Result<()> {
  // 标记设备为不活跃
}

// GET /api/v1/devices
// 获取用户的所有设备
#[get("/devices")]
async fn list_devices(
  AuthRequired(user_id): AuthRequired,
) -> Result<Json<Vec<DeviceResponse>>> {
  // 返回用户的所有活跃设备
}

// GET /api/v1/notifications
// 获取用户的通知
#[get("/notifications")]
async fn list_notifications(
  AuthRequired(user_id): AuthRequired,
  #[query] unread_only: Option<bool>,
  #[query] limit: Option<i32>,
) -> Result<Json<Vec<NotificationResponse>>> {
  // 返回通知列表
}

// POST /api/v1/notifications/{id}/read
// 标记通知为已读
#[post("/notifications/{id}/read")]
async fn mark_notification_read(
  AuthRequired(user_id): AuthRequired,
  id: Path<Uuid>,
) -> Result<()> {
  // 更新 is_read
}
```

---

## 🟡 HIGH: 前端集成 (3-4 天)

### 1. Stories 前端集成 (1 天)

**后端 API 已有**: `/api/v1/stories/*`

**前端需要**:
- [ ] `StoriesView.tsx` - 竖直轮播组件
  ```typescript
  // 调用现有的 API
  const stories = await fetch('/api/v1/stories');

  // 显示故事
  // 记录浏览 (POST /api/v1/stories/{id}/view)
  ```

- [ ] `StoryUpload.tsx` - 上传组件
  ```typescript
  // 拍照/选择 → 上传 → POST /api/v1/stories
  ```

- [ ] `storiesStore.ts` - Zustand 状态管理
  ```typescript
  const useStoriesStore = create((set) => ({
    stories: [],
    currentIndex: 0,
    fetchStories: async () => { /* ... */ },
    uploadStory: async (media, caption) => { /* ... */ },
  }));
  ```

**预期完成**: 1 天

---

### 2. 推送通知前端 (1.5 天)

#### Web

```typescript
// 1. Service Worker 注册
navigator.serviceWorker.register('/sw.js');

// 2. 请求权限
Notification.requestPermission();

// 3. 注册设备令牌
async function registerDevice() {
  const registration = await navigator.serviceWorker.ready;
  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: urlBase64ToUint8Array(PUBLIC_VAPID_KEY),
  });

  // 保存到后端
  await fetch('/api/v1/devices/register', {
    method: 'POST',
    body: JSON.stringify({
      token: subscription.endpoint,
      platform: 'web',
    }),
  });
}

// 4. Service Worker 处理推送
// sw.js
self.addEventListener('push', (event) => {
  const data = event.data.json();
  self.registration.showNotification(data.title, {
    body: data.body,
    icon: data.icon,
    badge: data.badge,
    data: data.data,
  });
});

self.addEventListener('notificationclick', (event) => {
  // 点击通知时的处理
  event.notification.close();
  clients.openWindow(event.notification.data.click_action);
});
```

#### iOS (Swift)

```swift
// 1. 请求推送权限
UNUserNotificationCenter.current().requestAuthorization(
  options: [.alert, .sound, .badge]
) { granted, _ in
  DispatchQueue.main.async {
    UIApplication.shared.registerForRemoteNotifications()
  }
}

// 2. 获取设备令牌
// AppDelegate.swift
func application(
  _ application: UIApplication,
  didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool {
  // ...
  UIApplication.shared.registerForRemoteNotifications()
  return true
}

func application(
  _ application: UIApplication,
  didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
) {
  let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()

  // 注册到后端
  Task {
    await registerDeviceToken(token: token, platform: "ios")
  }
}

// 3. 处理接收的推送
// AppDelegate.swift
func userNotificationCenter(
  _ center: UNUserNotificationCenter,
  willPresent notification: UNNotification,
  withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
) {
  // App 在前台时处理
  let userInfo = notification.request.content.userInfo
  handleNotification(userInfo)

  completionHandler([.banner, .sound, .badge])
}

func userNotificationCenter(
  _ center: UNUserNotificationCenter,
  didReceive response: UNNotificationResponse,
  withCompletionHandler completionHandler: @escaping () -> Void
) {
  // 用户点击通知时处理
  let userInfo = response.notification.request.content.userInfo
  navigateTo(userInfo)
  completionHandler()
}
```

**预期完成**: 1.5 天

---

### 3. 视频上传前端集成 (1 天)

#### Web 和 iOS

```typescript
// 调用后端已有的 API
// 1. POST /api/v1/uploads/init → 获取 uploadId
const response = await fetch('/api/v1/uploads/init', {
  method: 'POST',
  body: JSON.stringify({
    file_name: file.name,
    file_size: file.size,
    chunk_size: 5 * 1024 * 1024, // 5MB
  }),
});
const { upload_id } = await response.json();

// 2. PUT /api/v1/uploads/{upload_id}/chunks/{index}
// 上传每个分块
for (let i = 0; i < chunks.length; i++) {
  const chunk = chunks[i];
  await fetch(`/api/v1/uploads/${upload_id}/chunks/${i}`, {
    method: 'PUT',
    body: chunk,
  });
}

// 3. POST /api/v1/uploads/{upload_id}/complete
// 完成上传，获取最终 URL
const finalResponse = await fetch(`/api/v1/uploads/${upload_id}/complete`, {
  method: 'POST',
});
const { file_url } = await finalResponse.json();

// 4. 使用 file_url 创建 post
// POST /api/v1/posts
await createPost({
  caption: userCaption,
  video_url: file_url,
});
```

**预期完成**: 1 天

---

### 4. 消息加密前端集成 (TBD - 降级为 P2)

**现状**: 后端支持 E2E 加密，前端还是占位符

**工作**:
- [ ] 替换 `client.ts` 的占位符为真实 NaCl 加密
- [ ] 集成到 `messagingStore.ts` 发送逻辑
- [ ] 详见 `P1_REVISED_PLAN.md`

**预期完成**: P2 (11月8-15日)

---

## 📅 真实工作时间表

```
今天 (10月25日)
├─ 确认剩余工作（现在做的）
└─ 开始推送通知后端实现

周一-周三 (10月26-28日) - 推送通知后端
├─ Mon: FCM 库集成 + 实现
├─ Tue: APNs 库集成 + 实现 + 数据库表
└─ Wed: API 端点 + 测试

周四-五 (10月29-30日) - 前端集成开始
├─ Stories 前端集成
└─ 推送通知前端 (Web) 开始

11月1-2日 - 推送完成 + 视频上传
├─ 推送通知前端 (iOS) 完成
├─ 视频上传集成测试
└─ Bug 修复

预期: 11月2日 - 核心功能完成
```

---

## 📊 工作量重估

| 工作 | 原估计 | 实际 | 原因 |
|------|--------|------|------|
| Stories | 4-5h | 1d | 后端 100% 完成，前端只需集成 |
| 推送通知 | 5-6h | 3-4d | FCM/APNs 实际实现 + DB 设计 |
| 视频上传 | 6-7h | 1d | 后端完全完成，前端只需调用 |
| 消息加密 | 6-8h | 1w | 推后到 P2 |
| **总计** | 18-20h | **6-7d** | **集中于推送通知完成** |

---

## 🎯 关键洞察 (Linus 视角)

> "我们不是在建设功能，而是在完成已开始的东西。
>
> 推送通知是关键——框架完成了，但实现还没。
>
> 这不是'添加功能'问题，而是'完成该死的工作'问题。"

**所以优先级应该是**:
1. 🔴 **推送通知后端** - FCM/APNs 实现 (3-4 天)
2. 🟡 **前端集成** - Stories/推送/视频 (3 天)
3. 🟢 **消息加密** - 推后到 P2 (11月8 开始)

---

## ✅ 立即行动

### 今天
- [ ] 确认这个评估
- [ ] 分配人员做推送通知后端

### 周一-周三
- [ ] 后端: FCM + APNs + DB 表完成
- [ ] 前端: Stories 基础实现

### 周四-周五
- [ ] 后端: 推送通知 API 端点完成
- [ ] 前端: 推送通知集成

### 下周一
- [ ] 全面测试 + bug 修复
- [ ] 性能测试
- [ ] 部署准备

---

**状态**: 真实的工作清单（不是规划）

May the Force be with you.
