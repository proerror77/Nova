# 推送通知完整实现指南

**日期**: 2025-10-29
**优先级**: P0 关键项
**工期**: 2-3 天（FCM + APNs）
**状态**: 📋 实现计划

---

## 📊 现状分析

### 已完成

✅ **APNs (iOS)**
- 文件: `messaging-service/src/services/push.rs`
- 状态: 完整实现 100%
- 方式: 使用 `apns2` crate，同步 client
- 功能: 完整的通知发送、错误处理、日志记录

### 待完成

🔴 **FCM (Android/Web)**
- 文件: `user-service/src/services/notifications/fcm_client.rs`
- 状态: 骨架实现 10%
- 问题: `send()` 方法返回硬编码成功，未实际调用 FCM API
- 风险: Android 用户完全无法收到推送

---

## 🎯 FCM 完整实现计划

### Phase 1: 依赖和环境 (30 分钟)

#### 添加 Cargo 依赖

```toml
# user-service/Cargo.toml
[dependencies]
# 现有依赖
reqwest = { version = "0.11", features = ["json"] }
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# 新增：FCM 支持
fcm = "0.11"                      # Firebase Cloud Messaging
jsonwebtoken = "9"                 # JWT 令牌生成（用于 OAuth2）
```

#### 环境变量配置

```bash
# .env
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_SERVICE_ACCOUNT_KEY_PATH=/path/to/service-account-key.json
FCM_API_ENDPOINT=https://fcm.googleapis.com/v1/projects/YOUR_PROJECT_ID/messages:send
```

### Phase 2: FCM OAuth2 令牌获取 (1 小时)

FCM v1 API 需要 OAuth2 访问令牌。需要实现令牌获取:

#### 步骤 1: 创建令牌生成模块

```rust
// user-service/src/services/notifications/fcm_oauth2.rs

use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Serialize, Deserialize)]
pub struct ServiceAccountKey {
    pub project_id: String,
    pub private_key_id: String,
    pub private_key: String,
    pub client_email: String,
    pub client_id: String,
    pub auth_uri: String,
    pub token_uri: String,
}

#[derive(Debug, Serialize)]
pub struct JwtClaims {
    pub iss: String,            // client_email
    pub scope: String,          // FCM 作用域
    pub aud: String,            // token_uri
    pub exp: u64,               // 过期时间（now + 3600s）
    pub iat: u64,               // 签发时间
}

pub struct FcmOAuth2 {
    service_account: ServiceAccountKey,
    cached_token: Option<(String, u64)>, // (token, expiry_time)
}

impl FcmOAuth2 {
    pub fn new(service_account: ServiceAccountKey) -> Self {
        Self {
            service_account,
            cached_token: None,
        }
    }

    /// 获取有效的 OAuth2 访问令牌
    pub async fn get_access_token(&mut self) -> Result<String, String> {
        // 1. 检查缓存令牌是否仍有效
        if let Some((token, expiry)) = &self.cached_token {
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs();
            if now < *expiry - 60 {
                // 令牌有效（留 60 秒余量）
                return Ok(token.clone());
            }
        }

        // 2. 生成新的 JWT（自签名）
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let claims = JwtClaims {
            iss: self.service_account.client_email.clone(),
            scope: "https://www.googleapis.com/auth/cloud-platform".to_string(),
            aud: self.service_account.token_uri.clone(),
            exp: now + 3600,
            iat: now,
        };

        // 3. 用私钥签名 JWT
        let key = EncodingKey::from_rsa_pem(self.service_account.private_key.as_bytes())
            .map_err(|e| format!("Failed to parse private key: {e}"))?;

        let token = encode(
            &Header::new(Algorithm::RS256),
            &claims,
            &key,
        )
        .map_err(|e| format!("Failed to encode JWT: {e}"))?;

        // 4. 使用 JWT 向 Google OAuth2 端点交换访问令牌
        let client = reqwest::Client::new();
        let response = client
            .post(&self.service_account.token_uri)
            .form(&[
                ("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                ("assertion", &token),
            ])
            .send()
            .await
            .map_err(|e| format!("OAuth2 token request failed: {e}"))?;

        #[derive(Deserialize)]
        struct TokenResponse {
            access_token: String,
            expires_in: u64,
        }

        let token_resp: TokenResponse = response
            .json()
            .await
            .map_err(|e| format!("Failed to parse token response: {e}"))?;

        let access_token = token_resp.access_token.clone();
        let expiry = now + token_resp.expires_in;

        // 5. 缓存令牌和过期时间
        self.cached_token = Some((access_token.clone(), expiry));

        Ok(access_token)
    }
}
```

### Phase 3: FCM 消息发送实现 (1.5 小时)

#### 步骤 2: 完整的 FCM 发送实现

```rust
// user-service/src/services/notifications/fcm_client.rs（更新）

use reqwest::Client;
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::sync::Arc;
use tokio::sync::Mutex;
use uuid::Uuid;

mod fcm_oauth2;
use fcm_oauth2::FcmOAuth2;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FCMSendResult {
    pub message_id: String,
    pub success: bool,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MulticastSendResult {
    pub success_count: usize,
    pub failure_count: usize,
    pub results: Vec<FCMSendResult>,
}

pub struct FCMClient {
    pub project_id: String,
    oauth2: Arc<Mutex<FcmOAuth2>>,
    http_client: Client,
    api_endpoint: String,
}

impl FCMClient {
    /// 创建新的 FCM 客户端
    pub async fn new(
        project_id: String,
        service_account_key: ServiceAccountKey,
    ) -> Result<Self, String> {
        let oauth2 = FcmOAuth2::new(service_account_key);

        Ok(Self {
            project_id,
            oauth2: Arc::new(Mutex::new(oauth2)),
            http_client: Client::new(),
            api_endpoint: format!(
                "https://fcm.googleapis.com/v1/projects/{}/messages:send",
                project_id
            ),
        })
    }

    /// 向单个设备发送推送通知
    pub async fn send(
        &self,
        device_token: &str,
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> Result<FCMSendResult, String> {
        // 1. 获取访问令牌
        let mut oauth2 = self.oauth2.lock().await;
        let access_token = oauth2.get_access_token().await?;
        drop(oauth2);

        // 2. 构建 FCM 消息
        let mut message_body = json!({
            "message": {
                "token": device_token,
                "notification": {
                    "title": title,
                    "body": body,
                },
                "android": {
                    "priority": "high",
                    "notification": {
                        "sound": "default",
                        "channel_id": "default",
                    }
                },
                "apns": {
                    "headers": {
                        "apns-priority": "10"
                    }
                }
            }
        });

        // 3. 添加自定义数据（可选）
        if let Some(custom_data) = data {
            if let Some(msg) = message_body.get_mut("message") {
                msg["data"] = custom_data;
            }
        }

        // 4. 发送到 FCM API
        let response = self
            .http_client
            .post(&self.api_endpoint)
            .bearer_auth(&access_token)
            .json(&message_body)
            .send()
            .await
            .map_err(|e| format!("FCM HTTP request failed: {e}"))?;

        // 5. 处理响应
        match response.status() {
            reqwest::StatusCode::OK => {
                #[derive(Deserialize)]
                struct FcmResponse {
                    name: String,
                }

                let fcm_resp: FcmResponse = response
                    .json()
                    .await
                    .map_err(|e| format!("Failed to parse FCM response: {e}"))?;

                // 提取消息 ID（格式: projects/{project}/messages/{message_id}）
                let message_id = fcm_resp
                    .name
                    .split('/')
                    .last()
                    .unwrap_or("unknown")
                    .to_string();

                Ok(FCMSendResult {
                    message_id,
                    success: true,
                    error: None,
                })
            }
            _ => {
                let error_text = response
                    .text()
                    .await
                    .unwrap_or_else(|_| "Unknown error".to_string());

                Err(format!("FCM API error: {}", error_text))
            }
        }
    }

    /// 向多个设备发送推送通知（批量）
    pub async fn send_multicast(
        &self,
        device_tokens: &[String],
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> Result<MulticastSendResult, String> {
        let mut results = Vec::new();
        let mut success_count = 0;
        let mut failure_count = 0;

        // 按 500 个设备分批发送（FCM 限制）
        for chunk in device_tokens.chunks(500) {
            for token in chunk {
                match self.send(token, title, body, data.clone()).await {
                    Ok(result) => {
                        success_count += 1;
                        results.push(result);
                    }
                    Err(e) => {
                        failure_count += 1;
                        results.push(FCMSendResult {
                            message_id: Uuid::new_v4().to_string(),
                            success: false,
                            error: Some(e),
                        });
                    }
                }
            }
        }

        Ok(MulticastSendResult {
            success_count,
            failure_count,
            results,
        })
    }

    /// 向主题发送推送通知
    pub async fn send_to_topic(
        &self,
        topic: &str,
        title: &str,
        body: &str,
        data: Option<serde_json::Value>,
    ) -> Result<FCMSendResult, String> {
        let mut oauth2 = self.oauth2.lock().await;
        let access_token = oauth2.get_access_token().await?;
        drop(oauth2);

        let mut message_body = json!({
            "message": {
                "topic": topic,
                "notification": {
                    "title": title,
                    "body": body,
                }
            }
        });

        if let Some(custom_data) = data {
            if let Some(msg) = message_body.get_mut("message") {
                msg["data"] = custom_data;
            }
        }

        let response = self
            .http_client
            .post(&self.api_endpoint)
            .bearer_auth(&access_token)
            .json(&message_body)
            .send()
            .await
            .map_err(|e| format!("FCM HTTP request failed: {e}"))?;

        match response.status() {
            reqwest::StatusCode::OK => {
                #[derive(Deserialize)]
                struct FcmResponse {
                    name: String,
                }

                let fcm_resp: FcmResponse = response
                    .json()
                    .await
                    .map_err(|e| format!("Failed to parse FCM response: {e}"))?;

                let message_id = fcm_resp
                    .name
                    .split('/')
                    .last()
                    .unwrap_or("unknown")
                    .to_string();

                Ok(FCMSendResult {
                    message_id,
                    success: true,
                    error: None,
                })
            }
            _ => {
                let error_text = response
                    .text()
                    .await
                    .unwrap_or_else(|_| "Unknown error".to_string());

                Err(format!("FCM API error: {}", error_text))
            }
        }
    }
}
```

### Phase 4: 通知服务集成 (1 小时)

#### 步骤 3: 在通知系统中集成 FCM 和 APNs

```rust
// messaging-service/src/services/notification_service.rs（更新）

use crate::services::push::{PushProvider, ApnsPush};
// 导入 FCMClient（从 user-service 通过 gRPC）

pub struct NotificationService {
    apns: Option<Arc<ApnsPush>>,
    fcm: Option<Arc<FCMClient>>,
    db: Arc<PgPool>,
}

impl NotificationService {
    pub async fn new(
        db: Arc<PgPool>,
        apns: Option<Arc<ApnsPush>>,
        fcm: Option<Arc<FCMClient>>,
    ) -> Result<Self, AppError> {
        Ok(Self { apns, fcm, db })
    }

    /// 向用户所有设备发送推送通知
    pub async fn send_to_user(
        &self,
        user_id: Uuid,
        title: &str,
        body: &str,
        badge: Option<u32>,
    ) -> Result<NotificationResult, AppError> {
        // 1. 从数据库获取用户所有设备的令牌
        let devices = sqlx::query!(
            "SELECT device_id, device_token, device_type FROM user_devices WHERE user_id = $1 AND device_token IS NOT NULL",
            user_id
        )
        .fetch_all(self.db.as_ref())
        .await?;

        let mut success_count = 0;
        let mut failure_count = 0;
        let mut errors = Vec::new();

        for device in devices {
            match device.device_type.as_str() {
                "ios" => {
                    // 使用 APNs 发送
                    if let Some(apns) = &self.apns {
                        match apns.send(
                            device.device_token.clone(),
                            title.to_string(),
                            body.to_string(),
                            badge,
                        )
                        .await
                        {
                            Ok(_) => success_count += 1,
                            Err(e) => {
                                failure_count += 1;
                                errors.push(format!("iOS device {}: {}", device.device_id, e));
                            }
                        }
                    }
                }
                "android" => {
                    // 使用 FCM 发送
                    if let Some(fcm) = &self.fcm {
                        match fcm.send(&device.device_token, title, body, None).await {
                            Ok(_) => success_count += 1,
                            Err(e) => {
                                failure_count += 1;
                                errors.push(format!("Android device {}: {}", device.device_id, e));
                            }
                        }
                    }
                }
                _ => {
                    failure_count += 1;
                    errors.push(format!("Unknown device type: {}", device.device_type));
                }
            }
        }

        Ok(NotificationResult {
            total: success_count + failure_count,
            success_count,
            failure_count,
            errors,
        })
    }
}
```

---

## 📋 Firebase 项目配置

### Step 1: 创建 Firebase 项目

1. 访问 [Firebase Console](https://console.firebase.google.com/)
2. 点击 "创建项目"
3. 选择或创建 Google Cloud 项目
4. 启用 Cloud Messaging

### Step 2: 获取服务账户密钥

1. 进入项目设置 → 服务账户
2. 点击 "生成新的私钥"
3. 下载 JSON 文件
4. 保存为 `/config/firebase-credentials.json`

### Step 3: 获取服务器 API 密钥（备用）

1. 进入项目设置 → API 密钥
2. 复制 "API 密钥"
3. 保存到 `.env` 文件

---

## 🧪 测试计划

### 单元测试

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_fcm_send_success() {
        // Mock FCM API 响应
        let client = FCMClient::new(
            "test-project".to_string(),
            create_test_credentials(),
        )
        .await
        .unwrap();

        let result = client
            .send(
                "valid-device-token",
                "Test Title",
                "Test Body",
                None,
            )
            .await;

        assert!(result.is_ok());
        assert!(result.unwrap().success);
    }

    #[tokio::test]
    async fn test_fcm_send_invalid_token() {
        let client = FCMClient::new(
            "test-project".to_string(),
            create_test_credentials(),
        )
        .await
        .unwrap();

        let result = client
            .send(
                "invalid-token",
                "Test",
                "Test",
                None,
            )
            .await;

        assert!(result.is_err());
    }
}
```

### 集成测试

```bash
# 测试 APNs
curl -X POST http://localhost:8085/api/v1/notifications/send \
  -H "Authorization: Bearer YOUR_JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "title": "Test",
    "body": "Test notification",
    "platform": "ios"
  }'

# 测试 FCM
curl -X POST http://localhost:8085/api/v1/notifications/send \
  -H "Authorization: Bearer YOUR_JWT" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "550e8400-e29b-41d4-a716-446655440000",
    "title": "Test",
    "body": "Test notification",
    "platform": "android"
  }'
```

---

## 📅 实施日程

| 日期 | 任务 | 工时 | 负责人 |
|------|------|------|--------|
| Day 1 PM | Phase 1-2: 依赖、OAuth2 | 1.5h | @dev1 |
| Day 2 AM | Phase 3: 消息发送实现 | 1.5h | @dev1 |
| Day 2 PM | Phase 4: 服务集成 | 1h | @dev2 |
| Day 3 AM | 单元测试 | 1.5h | @dev1 |
| Day 3 PM | 集成测试 + 部署 | 1.5h | @dev2 |

**总工期**: 2-3 天

---

## 🔒 环境变量清单

```bash
# Firebase 配置
FIREBASE_PROJECT_ID=your-project-id
FIREBASE_SERVICE_ACCOUNT_KEY_PATH=/path/to/service-account-key.json
FCM_API_ENDPOINT=https://fcm.googleapis.com/v1/projects/YOUR_PROJECT_ID/messages:send

# APNs 配置（已有）
APNS_CERTIFICATE_PATH=/path/to/certificate.p12
APNS_CERTIFICATE_PASSPHRASE=your-passphrase
APNS_BUNDLE_ID=com.example.nova
APNS_PRODUCTION=false  # true 在生产环境

# 服务配置
PUSH_NOTIFICATION_ENABLED=true
PUSH_BATCH_SIZE=500
PUSH_TIMEOUT_SECS=30
```

---

## ✅ 验证清单

部署前确保：

- [ ] Firebase 项目已创建
- [ ] 服务账户密钥已获取
- [ ] APNs 证书已配置
- [ ] 环境变量已设置
- [ ] FCM OAuth2 令牌获取正常工作
- [ ] 单元测试全部通过
- [ ] 集成测试在 iOS 和 Android 上通过
- [ ] APNs 和 FCM 都能成功发送通知

---

## 📚 参考文档

- [FCM v1 API 文档](https://firebase.google.com/docs/cloud-messaging/migrate-v1)
- [APNs 文档](https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server)
- [Firebase 控制台](https://console.firebase.google.com/)

---

**状态**: 📋 待实施
**优先级**: 🔴 P0 关键
**工期**: 2-3 天
**预期完成**: 2025-11-01

May the Force be with you.
