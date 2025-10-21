# 工程师B - T202 FCM/APNs集成实现指南

**任务**: T202 - Firebase Cloud Messaging & Apple Push Notifications 集成
**分配时间**: 16 小时 (周五-周一)
**目标**: 25+ 单元测试，发送成功率 > 99%

---

## 🚀 快速启动

```bash
# 1. 切换到特性分支
git checkout feature/T202-push-notifications
git pull origin feature/T202-push-notifications

# 2. 验证框架代码已加载
cd backend/user-service/src/services/notifications
ls -la fcm_client.rs apns_client.rs  # 应该都存在

# 3. 编译验证框架
cargo build --lib --release

# 4. 运行现有单元测试
cargo test fcm_client --lib
cargo test apns_client --lib
```

---

## 📋 实现任务分解

### 第1部分：FCM集成 (8小时)

**目标**: 实现完整的 Firebase Cloud Messaging 集成

**文件**: `fcm_client.rs`

#### 1.1 身份验证 (2小时)

```rust
impl FCMClient {
    /// 获取 FCM 访问令牌
    async fn get_access_token(&self) -> Result<String, String> {
        // TODO: 实现：
        // 1. 从 ServiceAccountKey 创建 JWT
        // JWT 内容:
        // {
        //   "iss": client_email,
        //   "sub": client_email,
        //   "scope": "https://www.googleapis.com/auth/firebase.messaging",
        //   "aud": "https://oauth2.googleapis.com/token",
        //   "iat": now,
        //   "exp": now + 3600
        // }

        // 2. 使用 private_key 签名 JWT
        // 3. 交换 JWT 获取访问令牌

        // 参考: https://developers.google.com/identity/protocols/oauth2/service-account
    }
}
```

**验收标准**:
- [ ] JWT 创建和签名成功
- [ ] 访问令牌获取成功
- [ ] 令牌缓存机制实现 (1小时有效期)
- [ ] 令牌过期自动刷新

**单元测试** (2个):
```rust
#[tokio::test]
async fn test_jwt_creation() { }

#[tokio::test]
async fn test_access_token_retrieval() { }
```

#### 1.2 单条消息发送 (3小时)

```rust
impl FCMClient {
    pub async fn send(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> Result<FCMSendResult, String> {
        // TODO: 实现：
        // 1. 验证设备令牌格式
        // 2. 构建 FCM 消息体:
        // {
        //   "message": {
        //     "token": device_token,
        //     "notification": {
        //       "title": title,
        //       "body": body
        //     },
        //     "data": data,
        //     "android": {
        //       "priority": "high",
        //       "notification": {
        //         "sound": "default"
        //       }
        //     },
        //     "webpush": {
        //       "headers": {
        //         "TTL": "3600"
        //       }
        //     }
        //   }
        // }

        // 3. 调用 FCM API:
        // POST https://fcm.googleapis.com/v1/projects/{project_id}/messages:send

        // 4. 处理响应:
        // 成功: 返回 message_id
        // 失败: 返回错误并记录

        // 5. 实现重试逻辑 (429/503/500)

        Ok(FCMSendResult {
            message_id: Uuid::new_v4().to_string(),
            success: true,
            error: None,
        })
    }
}
```

**性能目标**:
- 延迟 (P95): < 500ms
- 吞吐量: ≥ 1k msg/sec

**单元测试** (3个):
```rust
#[tokio::test]
async fn test_send_notification() { }

#[tokio::test]
async fn test_send_with_data() { }

#[tokio::test]
async fn test_send_error_handling() { }
```

#### 1.3 多播和主题 (3小时)

```rust
impl FCMClient {
    /// 发送到多个设备
    pub async fn send_multicast(
        &self,
        device_tokens: &[String],
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> Result<MulticastSendResult, String> {
        // TODO: 实现：
        // 1. 批量构建消息 (最多 500 条/批)
        // 2. 并行发送 (使用 tokio::join_all)
        // 3. 收集结果和错误
        // 4. 重试失败的消息 (最多 3 次)
        // 5. 返回聚合结果

        // 注: FCM API 不支持真正的多播，需要逐条发送
    }

    /// 订阅主题
    pub async fn subscribe_to_topic(
        &self,
        device_tokens: &[String],
        topic: &str,
    ) -> Result<TopicSubscriptionResult, String> {
        // TODO: 实现：
        // POST /iid/v1/accounts:batchAddToGroup
        // {
        //   "to": "/topics/{topic}",
        //   "registration_tokens": device_tokens
        // }
    }

    /// 发送到主题
    pub async fn send_to_topic(
        &self,
        topic: &str,
        title: &str,
        body: &str,
    ) -> Result<FCMSendResult, String> {
        // TODO: 实现：
        // 与单条发送类似，但使用 "topic" 而不是 "token"
    }
}
```

**单元测试** (4个):
```rust
#[tokio::test]
async fn test_multicast_send() { }

#[tokio::test]
async fn test_topic_subscription() { }

#[tokio::test]
async fn test_send_to_topic() { }

#[tokio::test]
async fn test_multicast_error_recovery() { }
```

---

### 第2部分：APNs集成 (8小时)

**目标**: 实现完整的 Apple Push Notification Service 集成

**文件**: `apns_client.rs`

#### 2.1 证书管理 (2小时)

```rust
impl APNsClient {
    /// 加载证书和密钥
    async fn load_credentials(&self) -> Result<APNsCredentials, String> {
        // TODO: 实现：
        // 1. 读取 .p8 证书文件
        // 2. 解析证书内容
        // 3. 验证证书有效期
        // 4. 缓存证书 (使用 Arc<Mutex<>>)

        // .p8 证书格式:
        // -----BEGIN PRIVATE KEY-----
        // Base64 encoded content
        // -----END PRIVATE KEY-----
    }

    /// 建立 TLS 连接
    async fn create_connection(&self) -> Result<APNsConnection, String> {
        // TODO: 实现：
        // 1. 创建 TLS 客户端配置
        // 2. 连接到 APNs 服务器:
        //    - 生产: api.push.apple.com:443
        //    - 沙箱: api.sandbox.push.apple.com:443
        // 3. 建立 HTTP/2 连接
        // 4. 实现连接池和重用
    }
}
```

**验收标准**:
- [ ] 证书读取和验证成功
- [ ] TLS 连接建立成功
- [ ] 连接池实现 (最多 10 个连接)
- [ ] 连接复用减少延迟

**单元测试** (2个):
```rust
#[test]
fn test_certificate_loading() { }

#[tokio::test]
async fn test_apns_connection() { }
```

#### 2.2 单条消息发送 (3小时)

```rust
impl APNsClient {
    pub async fn send(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
        priority: APNsPriority,
    ) -> Result<APNsSendResult, String> {
        // TODO: 实现：
        // 1. 验证设备令牌 (64 个十六进制字符)
        // 2. 构建 APNs 负载:
        // {
        //   "aps": {
        //     "alert": {
        //       "title": title,
        //       "body": body
        //     },
        //     "badge": 1,
        //     "sound": "default",
        //     "category": "NOTIFICATION_ACTION"
        //   }
        // }

        // 3. 发送 HTTP/2 POST 请求
        // POST /3/device/{device_token}
        // Headers:
        //   apns-priority: 10 (high) or 5 (low)
        //   apns-expiration: now + 3600
        //   apns-topic: app_bundle_id

        // 4. 解析响应:
        // 成功: 200 OK with apple-id
        // 失败: 各种错误代码

        Ok(APNsSendResult {
            message_id: Uuid::new_v4().to_string(),
            success: true,
            error: None,
        })
    }
}
```

**性能目标**:
- 延迟 (P95): < 500ms
- 吞吐量: ≥ 500 msg/sec (APNs 限制)

**单元测试** (4个):
```rust
#[tokio::test]
async fn test_send_high_priority() { }

#[tokio::test]
async fn test_send_low_priority() { }

#[tokio::test]
async fn test_invalid_token_format() { }

#[tokio::test]
async fn test_apns_error_codes() { }
```

#### 2.3 高级功能 (3小时)

```rust
impl APNsClient {
    /// 发送带徽章的通知
    pub async fn send_with_badge(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
        badge: i32,
    ) -> Result<APNsSendResult, String> {
        // TODO: 实现
        // 在 APNs 负载中设置 badge 字段
    }

    /// 发送静默通知 (后台更新)
    pub async fn send_silent(
        &self,
        device_token: &str,
        data: serde_json::Value,
    ) -> Result<APNsSendResult, String> {
        // TODO: 实现
        // 不显示任何通知，仅触发后台更新
        // 使用 content-available: 1
    }

    /// 多播发送
    pub async fn send_multicast(
        &self,
        device_tokens: &[String],
        title: &str,
        body: &str,
        priority: APNsPriority,
    ) -> Result<APNsMulticastResult, String> {
        // TODO: 实现
        // 1. 并行发送到多个设备
        // 2. 使用连接池提高吞吐量
        // 3. 收集和聚合结果
    }
}
```

**单元测试** (3个):
```rust
#[tokio::test]
async fn test_send_with_badge() { }

#[tokio::test]
async fn test_send_silent() { }

#[tokio::test]
async fn test_multicast_send() { }
```

---

### 第3部分：多平台路由 (外部实现)

**目标**: 根据用户设备类型路由通知到正确的平台

```rust
pub struct NotificationRouter {
    fcm_client: Arc<FCMClient>,
    apns_client: Arc<APNsClient>,
}

impl NotificationRouter {
    pub async fn send_notification(
        &self,
        user_device: &UserDevice,
        title: &str,
        body: &str,
    ) -> Result<SendResult, String> {
        // TODO: 实现
        // 1. 查询用户设备列表
        // 2. 为每个设备选择正确的客户端:
        //    - Android/Web -> FCM
        //    - iOS/macOS -> APNs
        // 3. 并行发送
        // 4. 返回聚合结果
    }
}
```

---

## 🧪 测试清单

### 需要实现的测试 (25+)

**FCM 测试** (12个):
- [ ] JWT 创建
- [ ] 访问令牌获取
- [ ] 令牌缓存
- [ ] 单条发送
- [ ] 带数据发送
- [ ] 错误处理
- [ ] 多播发送
- [ ] 主题订阅
- [ ] 主题发送
- [ ] 多播错误恢复
- [ ] 速率限制处理
- [ ] 连接池性能

**APNs 测试** (13个):
- [ ] 证书加载
- [ ] 连接建立
- [ ] 高优先级发送
- [ ] 低优先级发送
- [ ] 令牌验证
- [ ] 错误代码处理
- [ ] 带徽章发送
- [ ] 静默通知
- [ ] 多播发送
- [ ] 连接重用
- [ ] 关闭处理
- [ ] 反馈处理
- [ ] 过期令牌处理

---

## 📊 性能目标

| 指标 | 目标 | 平台 |
|------|------|------|
| 发送延迟 (P95) | < 500ms | FCM/APNs |
| 成功率 | > 99% | 两者 |
| 吞吐量 | ≥ 1k msg/sec | FCM |
| 吞吐量 | ≥ 500 msg/sec | APNs |
| 错误恢复 | < 3 秒 | 两者 |
| 连接复用 | > 90% | APNs |

---

## 📅 每日检查点

### 周五 (Day 1) - 前 4 小时
- [ ] FCM 身份验证实现
- [ ] 单条消息发送功能
- [ ] 2 个 FCM 测试通过

### 周六-周日 (Day 2-3) - 中间 6 小时
- [ ] FCM 多播和主题功能
- [ ] APNs 证书管理
- [ ] APNs 连接建立
- [ ] 8 个测试通过

### 周一 (Day 4) - 后 6 小时
- [ ] APNs 完整功能
- [ ] 多平台路由
- [ ] 所有 25+ 测试通过
- [ ] 性能基准测试完成

---

## 🎯 完成标准

✅ **T202 完成定义**:
1. `FCMClient::send()` 完全实现
2. `FCMClient::send_multicast()` 完全实现
3. `FCMClient::send_to_topic()` 完全实现
4. `APNsClient::send()` 完全实现
5. `APNsClient::send_multicast()` 完全实现
6. 25+ 单元测试全部通过
7. 性能目标全部达成:
   - FCM P95 < 500ms
   - APNs P95 < 500ms
   - 成功率 > 99%
8. 错误处理完整
9. 代码审查通过
10. 完整文档交付

---

## 🔧 开发环境设置

### 必需依赖

```toml
[dependencies]
reqwest = { version = "0.11", features = ["json"] }
jsonwebtoken = "9"
tls-native = "0.1"
h2 = "0.3"
```

### Firebase 配置

1. 创建 Firebase 项目: https://console.firebase.google.com
2. 生成服务账户密钥
3. 下载 `.json` 文件

### APNs 配置

1. 获取 App ID 和团队 ID
2. 生成 `.p8` 证书
3. 获取 Key ID

---

## 💡 实现建议

**按照 Linus 原则**:

1. **数据结构优先**
   - 清晰的 JWT 结构
   - 统一的消息格式

2. **消除特殊情况**
   - 所有发送流程统一
   - 错误处理一致

3. **简洁执念**
   - 发送函数不超过 40 行
   - 认证逻辑不超过 30 行

4. **性能考虑**
   - 连接池必须实现
   - 令牌缓存必须实现
   - 并行发送必须实现

---

**准备好了吗？ Let's go! 🚀**

*最后更新: 2025-10-21 | 预计完成: 2025-10-27*
