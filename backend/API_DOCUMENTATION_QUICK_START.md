# Nova API 文檔快速指南

## 🚀 快速訪問

### 本地開發環境

**User Service** (端口 8081):
```bash
# 文檔入口
http://localhost:8081/docs

# Swagger UI
http://localhost:8081/swagger-ui

# OpenAPI JSON
http://localhost:8081/api/v1/openapi.json
```

**Messaging Service** (端口 8085):
```bash
# 文檔入口
http://localhost:8085/docs

# Swagger UI
http://localhost:8085/swagger-ui

# OpenAPI JSON
http://localhost:8085/openapi.json
```

**Search Service** (端口 8086):
```bash
# 文檔入口
http://localhost:8086/docs

# Swagger UI
http://localhost:8086/swagger-ui

# OpenAPI JSON
http://localhost:8086/openapi.json
```

---

## 📖 文檔使用指南

### 1. 交互式測試（Swagger UI）
推薦用於：API 測試、參數驗證、快速原型

**步驟**：
1. 訪問 `/swagger-ui`
2. 點擊端點展開
3. 點擊 "Try it out"
4. 填寫參數
5. 點擊 "Execute"
6. 查看響應

**特點**：
- ✅ 實時 API 測試
- ✅ 請求/響應示例
- ✅ Schema 驗證
- ✅ 授權配置（Bearer Token）

### 2. OpenAPI JSON
推薦用於：客戶端生成、契約測試、CI/CD 集成

**用途**：
```bash
# iOS Swift 客戶端生成
npx @openapitools/openapi-generator-cli generate \
  -i http://localhost:8081/api/v1/openapi.json \
  -g swift5 \
  -o ./iOS/Generated

# TypeScript 客戶端生成
npx @openapitools/openapi-generator-cli generate \
  -i http://localhost:8081/api/v1/openapi.json \
  -g typescript-axios \
  -o ./web/src/api

# Postman Collection
curl http://localhost:8081/api/v1/openapi.json > user-service.json
# Import user-service.json into Postman
```

---

## 🔧 開發者工作流

### 添加新 API 端點

#### 1. 在 Rust 代碼中添加 utoipa 註解

**Actix-web (user-service)**:
```rust
use utoipa::ToSchema;

#[derive(Serialize, Deserialize, ToSchema)]
pub struct CreateUserRequest {
    #[schema(example = "alice")]
    pub username: String,

    #[schema(example = "alice@example.com")]
    pub email: String,
}

/// Create a new user
#[utoipa::path(
    post,
    path = "/api/v1/users",
    request_body = CreateUserRequest,
    responses(
        (status = 201, description = "User created successfully", body = User),
        (status = 400, description = "Invalid input"),
        (status = 409, description = "User already exists")
    ),
    tag = "Users"
)]
pub async fn create_user(
    data: web::Json<CreateUserRequest>,
) -> Result<HttpResponse, AppError> {
    // ...
}
```

**Axum (messaging-service, search-service)**:
```rust
/// Send a message to a conversation
#[utoipa::path(
    post,
    path = "/conversations/{id}/messages",
    params(
        ("id" = Uuid, Path, description = "Conversation ID")
    ),
    request_body = SendMessageRequest,
    responses(
        (status = 201, description = "Message sent", body = Message),
        (status = 404, description = "Conversation not found")
    ),
    tag = "Messages"
)]
pub async fn send_message(
    Path(id): Path<Uuid>,
    State(state): State<AppState>,
    Json(req): Json<SendMessageRequest>,
) -> Result<Json<Message>, AppError> {
    // ...
}
```

#### 2. 在 OpenAPI 定義中註冊

**user-service/src/openapi.rs**:
```rust
#[derive(OpenApi)]
#[openapi(
    paths(
        crate::routes::users::create_user,  // 添加這裡
        // ...
    ),
    components(schemas(User, CreateUserRequest))  // 添加 schema
)]
pub struct ApiDoc;
```

#### 3. 重新編譯並驗證
```bash
cd /Users/proerror/Documents/nova/backend
cargo build --release

# 啟動服務
./target/release/user-service

# 驗證 OpenAPI JSON
curl http://localhost:8081/api/v1/openapi.json | jq '.paths'

# 訪問 Swagger UI
open http://localhost:8081/swagger-ui
```

---

## 🎨 自定義 Swagger UI

### 更改主題顏色

編輯 `src/main.rs` 或 `src/routes/mod.rs` 中的 Swagger UI HTML：

```html
<script>
    SwaggerUIBundle({
        url: "/openapi.json",
        dom_id: '#swagger-ui',
        deepLinking: true,
        // 添加自定義配置
        defaultModelsExpandDepth: 2,
        defaultModelExpandDepth: 2,
        displayRequestDuration: true,
        filter: true,  // 啟用搜索過濾
        tryItOutEnabled: true,  // 默認啟用 "Try it out"
        persistAuthorization: true,  // 記住授權信息
    });
</script>
```

### 添加 Bearer Token 授權

Swagger UI 會自動讀取 OpenAPI 中的 `securitySchemes`：

```rust
#[derive(OpenApi)]
#[openapi(
    // ...
    security(
        ("bearer_auth" = [])
    ),
    components(
        schemas(...),
        security_schemes(
            ("bearer_auth" = (
                type = Http,
                scheme = "bearer",
                bearer_format = "JWT"
            ))
        )
    )
)]
```

重新編譯後，Swagger UI 會顯示 🔒 圖標，點擊可輸入 JWT token。

---

## 🔍 常見問題

### Q: OpenAPI JSON 沒有更新？
**A**: 需要重新編譯服務：
```bash
cargo build --release
# 重啟服務
```

### Q: Swagger UI 顯示 "Failed to load API definition"？
**A**: 檢查 `/openapi.json` 端點是否可訪問：
```bash
curl http://localhost:8081/api/v1/openapi.json
```

### Q: 如何在生產環境禁用 Swagger UI？
**A**: 使用 feature flag：
```rust
#[cfg(feature = "swagger")]
.route("/swagger-ui", get(swagger_ui))
```

```bash
# 生產構建時不啟用 swagger
cargo build --release --no-default-features
```

### Q: 如何聚合多個服務的 OpenAPI？
**A**: 方案 1 - 使用 Nginx 代理：
```nginx
location /api-docs/user {
    proxy_pass http://user-service:8081/api/v1/openapi.json;
}
location /api-docs/messaging {
    proxy_pass http://messaging-service:8085/openapi.json;
}
location /api-docs/search {
    proxy_pass http://search-service:8086/openapi.json;
}
```

**方案 2** - 使用合併工具：
```bash
npm install -g openapi-merge-cli

openapi-merge-cli \
  --input user=http://localhost:8081/api/v1/openapi.json \
  --input messaging=http://localhost:8085/openapi.json \
  --input search=http://localhost:8086/openapi.json \
  --output merged-openapi.json
```

---

## 📚 參考資料

- [utoipa 完整文檔](https://docs.rs/utoipa/)
- [OpenAPI 3.0 規範](https://spec.openapis.org/oas/v3.0.3)
- [Swagger UI 配置選項](https://swagger.io/docs/open-source-tools/swagger-ui/usage/configuration/)
- [OpenAPI Generator](https://openapi-generator.tech/)

---

## 🛠 故障排除

### 編譯錯誤：`utoipa` 宏找不到類型

**錯誤**：
```
error[E0433]: failed to resolve: use of undeclared type `User`
```

**解決**：確保在 `openapi.rs` 中導入所有 schema：
```rust
#[openapi(
    components(schemas(
        User,           // 確保這裡列出
        CreateUserRequest,
    ))
)]
```

### CDN 載入失敗

**錯誤**：Swagger UI 無法載入 CSS/JS

**解決**：使用本地 Swagger UI（如果網絡受限）：
```bash
# 下載 Swagger UI
wget https://github.com/swagger-api/swagger-ui/archive/refs/tags/v5.0.0.tar.gz
tar -xzf v5.0.0.tar.gz
cp -r swagger-ui-5.0.0/dist ./static/swagger-ui

# 修改 HTML，使用本地文件
<link rel="stylesheet" href="/static/swagger-ui/swagger-ui.css" />
<script src="/static/swagger-ui/swagger-ui-bundle.js"></script>
```

---

**最後更新**: 2025-10-26
**維護者**: Nova Backend Team
