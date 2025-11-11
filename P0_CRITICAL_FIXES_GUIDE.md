# P0 Critical Fixes Implementation Guide

**Status**: 🔴 BLOCKING PRODUCTION
**Priority**: Must fix before any production deployment
**Estimated Time**: 2-4 hours total

---

## P0-1: messaging-service 跨服務寫入 users 表 [BLOCKER]

### 問題描述

**違規代碼位置**: `backend/messaging-service/src/services/conversation_service.rs:333`

```rust
// ❌ 當前違規代碼
let creator_username = format!("u_{}", creator_id.to_string()[..8].to_string());
sqlx::query("INSERT INTO users (id, username) VALUES ($1, $2) ON CONFLICT (id) DO NOTHING")
    .bind(creator_id)
    .bind(creator_username)
    .execute(&mut *tx)
    .await
    .map_err(|e| crate::error::AppError::StartServer(format!("ensure creator: {e}")))?;
```

**為什麼這是 BLOCKER**:
- messaging-service 直接寫入屬於 user-service 的 `users` 表
- 違反數據所有權單一寫入原則
- 創建的用戶數據不完整（只有 id 和偽造的 username）
- 如果 user-service 和 messaging-service 分離到不同數據庫，這段代碼會崩潰

### 修復方案 A: 移除"確保用戶存在"邏輯 [推薦，2 小時]

**核心思想**: messaging-service 應該信任 user-service 已經創建了用戶

**步驟 1**: 移除違規代碼

```rust
// ✅ 修復後的代碼
// backend/messaging-service/src/services/conversation_service.rs

// 刪除行 331-338 (確保 creator 存在)
// 刪除行 340-353 (確保 members 存在)

// 直接創建 conversation，不要嘗試寫入 users 表
let mut all_members = vec![creator_id];
for member_id in &member_ids {
    if member_id != &creator_id && !all_members.contains(member_id) {
        all_members.push(*member_id);
    }
}
let member_count = all_members.len() as i32;

// Create conversation
sqlx::query(
    r#"
    INSERT INTO conversations (id, kind, name, description, avatar_url, member_count, privacy_mode, admin_key_version)
    VALUES ($1, 'group', $2, $3, $4, $5, $6, 1)
    "#
)
// ... 繼續原有的 conversation 創建邏輯
```

**步驟 2**: 添加外鍵約束驗證

```sql
-- 在數據庫 migration 中添加
-- backend/messaging-service/migrations/add_user_fk.sql

ALTER TABLE conversation_members
ADD CONSTRAINT fk_conversation_members_user
FOREIGN KEY (user_id) REFERENCES users(id)
ON DELETE RESTRICT;  -- 防止刪除仍在 conversation 中的用戶
```

**步驟 3**: 錯誤處理

```rust
// 如果用戶不存在，Foreign Key 約束會拋出錯誤
// 捕獲並返回明確的錯誤信息

.map_err(|e| {
    if e.to_string().contains("foreign key constraint") {
        crate::error::AppError::BadRequest(
            "One or more users do not exist. Please ensure all users are registered before creating a conversation.".to_string()
        )
    } else {
        crate::error::AppError::StartServer(format!("create conversation: {e}"))
    }
})?;
```

**測試**:
```bash
# 1. 編譯測試
cd backend/messaging-service
cargo build --release

# 2. 運行單元測試
cargo test test_create_conversation

# 3. 集成測試
# 創建不存在的用戶應該失敗
curl -X POST http://localhost:8080/conversations \
  -H "Content-Type: application/json" \
  -d '{
    "creator_id": "00000000-0000-0000-0000-000000000000",
    "member_ids": ["11111111-1111-1111-1111-111111111111"]
  }'
# 預期: HTTP 400 "users do not exist"
```

### 修復方案 B: 調用 user-service gRPC API [完整方案，4 小時]

**步驟 1**: 添加 user-service gRPC client

```toml
# backend/messaging-service/Cargo.toml
[dependencies]
user-service-proto = { path = "../libs/user-service-proto" }
tonic = "0.10"
```

**步驟 2**: 初始化 gRPC 客戶端

```rust
// backend/messaging-service/src/clients/user_client.rs
use user_service_proto::user_service_client::UserServiceClient;
use tonic::transport::Channel;

pub struct UserClient {
    client: UserServiceClient<Channel>,
}

impl UserClient {
    pub async fn new(endpoint: String) -> Result<Self, Box<dyn std::error::Error>> {
        let client = UserServiceClient::connect(endpoint).await?;
        Ok(Self { client })
    }

    pub async fn verify_users_exist(&mut self, user_ids: Vec<Uuid>) -> Result<bool, Box<dyn std::error::Error>> {
        let request = tonic::Request::new(user_service_proto::VerifyUsersRequest {
            user_ids: user_ids.iter().map(|id| id.to_string()).collect(),
        });

        let response = self.client.verify_users_exist(request).await?;
        Ok(response.into_inner().all_exist)
    }
}
```

**步驟 3**: 在 conversation 創建前驗證用戶

```rust
// backend/messaging-service/src/services/conversation_service.rs

// 替換 "確保用戶存在" 為 "驗證用戶存在"
let mut all_user_ids = vec![creator_id];
all_user_ids.extend_from_slice(&member_ids);

// 調用 user-service 驗證
if !self.user_client.verify_users_exist(all_user_ids.clone()).await? {
    return Err(crate::error::AppError::BadRequest(
        "One or more users do not exist".to_string()
    ));
}

// 用戶驗證通過，繼續創建 conversation
let member_count = all_user_ids.len() as i32;
sqlx::query(...)
```

**步驟 4**: user-service 實現 VerifyUsersExist RPC

```protobuf
// backend/libs/user-service-proto/user_service.proto
service UserService {
  rpc VerifyUsersExist(VerifyUsersRequest) returns (VerifyUsersResponse);
}

message VerifyUsersRequest {
  repeated string user_ids = 1;
}

message VerifyUsersResponse {
  bool all_exist = 1;
  repeated string missing_user_ids = 2;
}
```

```rust
// backend/user-service/src/handlers/verify.rs
pub async fn verify_users_exist(
    &self,
    request: Request<VerifyUsersRequest>,
) -> Result<Response<VerifyUsersResponse>, Status> {
    let user_ids: Vec<Uuid> = request
        .into_inner()
        .user_ids
        .iter()
        .map(|s| Uuid::parse_str(s).map_err(|_| Status::invalid_argument("Invalid UUID")))
        .collect::<Result<Vec<_>, _>>()?;

    // 批量查詢用戶存在性
    let existing_ids: Vec<Uuid> = sqlx::query_scalar!(
        "SELECT id FROM users WHERE id = ANY($1)",
        &user_ids
    )
    .fetch_all(&self.pool)
    .await
    .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

    let all_exist = existing_ids.len() == user_ids.len();
    let missing_ids: Vec<String> = user_ids
        .iter()
        .filter(|id| !existing_ids.contains(id))
        .map(|id| id.to_string())
        .collect();

    Ok(Response::new(VerifyUsersResponse {
        all_exist,
        missing_user_ids: missing_ids,
    }))
}
```

---

## P0-2: 添加缺失的 ECR latest 標籤 [30 分鐘]

### 問題描述

3 個服務的 ECR repositories 缺少 `latest` 標籤，導致 Kubernetes 部署失敗：
- `nova/notification-service`
- `nova/events-service`
- `nova/cdn-service`

### 修復方案

**選項 A: 手動添加標籤** [立即執行]

```bash
# 為 notification-service 添加 latest 標籤
aws ecr put-image \
  --repository-name nova/notification-service \
  --image-tag latest \
  --image-manifest "$(aws ecr batch-get-image \
    --repository-name nova/notification-service \
    --image-ids imageTag=main \
    --query 'images[].imageManifest' \
    --output text)" \
  --region ap-northeast-1

# 為 events-service 添加 latest 標籤
aws ecr put-image \
  --repository-name nova/events-service \
  --image-tag latest \
  --image-manifest "$(aws ecr batch-get-image \
    --repository-name nova/events-service \
    --image-ids imageTag=main \
    --query 'images[].imageManifest' \
    --output text)" \
  --region ap-northeast-1

# 為 cdn-service 添加 latest 標籤
aws ecr put-image \
  --repository-name nova/cdn-service \
  --image-tag latest \
  --image-manifest "$(aws ecr batch-get-image \
    --repository-name nova/cdn-service \
    --image-ids imageTag=main \
    --query 'images[].imageManifest' \
    --output text)" \
  --region ap-northeast-1

# 驗證
aws ecr describe-images \
  --repository-name nova/notification-service \
  --region ap-northeast-1 \
  --query 'imageDetails[?contains(imageTags, `latest`)].imageTags'
```

**選項 B: 修復 GitHub Actions workflow** [根本解決]

```yaml
# .github/workflows/ecr-build-push.yml
# 確保 latest 標籤始終被推送

- name: Build and push Docker image
  uses: docker/build-push-action@v6
  with:
    context: .
    file: ./backend/${{ matrix.service }}/Dockerfile
    platforms: linux/amd64
    push: ${{ github.event_name != 'pull_request' }}
    tags: |
      ${{ steps.meta.outputs.image }}
      ${{ env.ECR_REGISTRY }}/${{ env.REGISTRY_ALIAS }}/${{ matrix.service }}:latest  # ← 確保添加
    cache-from: ...
    cache-to: ...
```

---

## P0-3: 修復 user-service CLICKHOUSE_URL 環境變量 [15 分鐘]

### 問題描述

user-service 崩潰：`CLICKHOUSE_URL must be set: NotPresent`

**違規代碼位置**: `backend/user-service/src/config/mod.rs:480`

```rust
// ❌ 使用 .expect() 強制要求環境變量
env::var("CLICKHOUSE_URL").expect("CLICKHOUSE_URL must be set")
```

### 修復方案

**選項 A: 添加環境變量** [立即執行]

```bash
kubectl set env deployment/user-service -n nova-backend \
  CLICKHOUSE_URL=http://clickhouse.nova-infra:8123

# 驗證
kubectl get deployment user-service -n nova-backend -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="CLICKHOUSE_URL")].value}'

# 重啟 pods
kubectl rollout restart deployment/user-service -n nova-backend

# 檢查狀態
kubectl get pods -n nova-backend -l app=user-service -w
```

**選項 B: 修改代碼使其可選** [根本解決]

```rust
// backend/user-service/src/config/mod.rs

// ✅ 修改為可選，提供默認值
let clickhouse_url = env::var("CLICKHOUSE_URL")
    .unwrap_or_else(|_| "http://clickhouse.nova-infra:8123".to_string());

// 或者使其完全可選（如果不是關鍵功能）
let clickhouse_url = env::var("CLICKHOUSE_URL").ok();

// 後續代碼需要適配：
if let Some(url) = clickhouse_url {
    // 初始化 ClickHouse 客戶端
} else {
    warn!("ClickHouse URL not configured, analytics disabled");
}
```

---

## P0-4: 修復 graphql-gateway JWT_PRIVATE_KEY_PEM [15 分鐘]

### 問題描述

graphql-gateway 部分 pods 崩潰：`JWT_PRIVATE_KEY_PEM must be set: NotPresent`

### 修復方案

**選項 A: 從 Secret 注入** [推薦]

```bash
# 1. 創建 Secret（如果不存在）
kubectl create secret generic jwt-keys -n nova-gateway \
  --from-file=private-key=/path/to/jwt-private.pem \
  --from-file=public-key=/path/to/jwt-public.pem \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. 更新 deployment 使用 Secret
kubectl patch deployment graphql-gateway -n nova-gateway --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "JWT_PRIVATE_KEY_PEM",
      "valueFrom": {
        "secretKeyRef": {
          "name": "jwt-keys",
          "key": "private-key"
        }
      }
    }
  }
]'

# 3. 重啟
kubectl rollout restart deployment/graphql-gateway -n nova-gateway
```

**選項 B: 直接注入值** [臨時方案]

```bash
# ⚠️ 僅用於開發環境
kubectl set env deployment/graphql-gateway -n nova-gateway \
  JWT_PRIVATE_KEY_PEM="$(cat /path/to/jwt-private.pem)"
```

---

## 驗證清單

完成所有修復後，運行以下驗證：

```bash
# 1. 服務狀態檢查
kubectl get pods --all-namespaces | grep nova

# 預期結果：
# - user-service: 4/4 Running
# - graphql-gateway: 4/4 Running
# - events-service: 4/4 Running
# - 所有服務無 CrashLoopBackOff

# 2. 運行邊界驗證測試
cd /Users/proerror/Documents/nova/backend
./scripts/validate-boundaries-simple.sh

# 預期結果：
# ✅ 0 個跨服務寫操作
# ✅ messaging-service 不再寫 users 表

# 3. ECR 標籤驗證
aws ecr describe-images --region ap-northeast-1 \
  --repository-name nova/notification-service \
  --query 'imageDetails[?contains(imageTags, `latest`)].imageTags'

# 預期結果：包含 latest 標籤

# 4. 端到端測試
# 創建 conversation（應該成功，假設用戶已存在）
curl -X POST http://nova-backend.example.com/api/conversations \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Test Group",
    "member_ids": ["existing-user-uuid"]
  }'

# 預期結果：HTTP 200，conversation 創建成功
```

---

## 執行順序

1. **P0-2**: ECR 標籤（30 分鐘） - 無風險，立即執行
2. **P0-3**: CLICKHOUSE_URL（15 分鐘） - 環境變量注入，無風險
3. **P0-4**: JWT_PRIVATE_KEY（15 分鐘） - 環境變量注入，無風險
4. **P0-1**: messaging-service 代碼修復（2-4 小時） - 需要測試，建議在 staging 環境先驗證

**總計時間**: 3-5 小時

---

## 回滾策略

如果 P0-1 修復後出現問題：

```bash
# 1. 立即回滾到修復前的版本
kubectl rollout undo deployment/messaging-service -n nova-backend

# 2. 檢查 pods 狀態
kubectl get pods -n nova-backend -l app=messaging-service -w

# 3. 檢查日誌查找問題
kubectl logs -n nova-backend -l app=messaging-service --tail=100

# 4. 如果需要，可以臨時恢復"確保用戶存在"邏輯
# 但必須添加 TODO 註釋，標記為技術債
```

---

**文檔版本**: 1.0
**創建時間**: 2025-11-11
**優先級**: P0 - BLOCKING
**負責人**: Backend Team Lead
