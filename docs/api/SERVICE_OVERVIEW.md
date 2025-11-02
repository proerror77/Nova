# Nova Backend API / Swagger 導覽

這份清單彙總了目前 8 個核心後端服務的用途、REST 入口、以及 Swagger / OpenAPI 狀態，方便前端或整合方快速找到對應規格檔。

> ⛳️ **環境路徑格式**  
> 以下路徑以 `https://{ENV}-api.nova.example.com` 為範例網域；請依照實際的 staging / production 網域替換 `{ENV}`。  
> 內部 Service 名稱則對應 Kubernetes Service (例如 `auth-service`, `user-service` 等)。

| 服務 | 主要職責 | REST Base Path | Swagger UI | OpenAPI JSON | gRPC Port / Proto |
|------|----------|----------------|------------|--------------|-------------------|
| **auth-service** | 登入、註冊、OAuth、JWT | `/api/v1/auth/*` | `https://{ENV}-api.nova.example.com/auth/swagger-ui/` | `https://{ENV}-api.nova.example.com/auth/api/v1/openapi.json` | 依預設 `server_port + 1000`；定義於 `backend/protos/auth.proto` |
| **user-service** | 使用者 Profile、關係、偏好 | `/api/v1/users/*` | `https://{ENV}-api.nova.example.com/users/swagger-ui/` | `https://{ENV}-api.nova.example.com/users/api/v1/openapi.json` | 透過 gRPC 讀寫 auth/content/media 服務 |
| **content-service** | 貼文、留言、Stories | `/api/v1/posts/*` 、 `/api/v1/stories/*` | `https://{ENV}-api.nova.example.com/content/swagger-ui/` | `https://{ENV}-api.nova.example.com/content/api/v1/openapi.json` | 相關定義規劃在 `backend/protos/content_service.proto` |
| **feed-service** | 動態牆、推薦 | `/api/v1/feed/*` | `https://{ENV}-api.nova.example.com/feed/swagger-ui/` | `https://{ENV}-api.nova.example.com/feed/api/v1/openapi.json` | `backend/protos/content_service.proto` / 其他 feed proto |
| **messaging-service** | 私訊、群組、WebSocket | `/api/v1/messaging/*` | `https://{ENV}-api.nova.example.com/messaging/swagger-ui/` | `https://{ENV}-api.nova.example.com/messaging/api/v1/openapi.json` | 核心 gRPC 介面在 `backend/protos/messaging_service.proto` |
| **media-service** | 媒體上傳、轉檔 | `/api/v1/media/*` | `https://{ENV}-api.nova.example.com/media/swagger-ui/` | `https://{ENV}-api.nova.example.com/media/api/v1/openapi.json` | 介面定義於 `backend/protos/media_service.proto` |
| **search-service** | 搜尋、索引 | `/api/v1/search/*` | `https://{ENV}-api.nova.example.com/search/swagger-ui/` | `https://{ENV}-api.nova.example.com/search/api/v1/openapi.json` | 後端透過 gRPC 暴露查詢能力 |
| **streaming-service** | 影音串流、實況 | `/api/v1/streaming/*` | `https://{ENV}-api.nova.example.com/streaming/swagger-ui/` | `https://{ENV}-api.nova.example.com/streaming/api/v1/openapi.json` | 介面定義於 `backend/protos/streaming.proto` |

目前 8 個核心服務均已提供 OpenAPI / Swagger。若新增服務，可依照下述步驟快速掛載對應路由。

---

## 如何取得 OpenAPI 規格

```bash
# 下載 JSON 規格
curl -o specs/user-service.openapi.json \
  https://{ENV}-api.nova.example.com/users/api/v1/openapi.json

# 使用 openapi-generator 產生 TypeScript Axios client
openapi-generator generate \
  -i specs/user-service.openapi.json \
  -g typescript-axios \
  -o clients/user-service-ts

# auth-service 亦可套用相同方式
curl -o specs/auth-service.openapi.json \
  https://{ENV}-api.nova.example.com/auth/api/v1/openapi.json

openapi-generator generate \
  -i specs/auth-service.openapi.json \
  -g typescript-axios \
  -o clients/auth-service-ts

# 或使用 repo 內的腳本一次抓取
./scripts/fetch_openapi.sh https://{ENV}-api.nova.example.com specs
```

> 若想快速確認文件，可直接瀏覽 `https://{ENV}-api.nova.example.com/users/swagger-ui/` 或 `https://{ENV}-api.nova.example.com/auth/swagger-ui/`。

---

## 其他服務新增 Swagger / OpenAPI 的建議流程

1. 在服務的 `Cargo.toml` 新增依賴：
   ```toml
   utoipa = { version = "4", features = ["chrono", "uuid"] }
   utoipa-swagger-ui = { version = "5", features = ["actix-web"] }
   ```

2. 定義 OpenAPI 文件（可放在 `src/openapi.rs`）：
   ```rust
   use utoipa::OpenApi;

   #[derive(OpenApi)]
   #[openapi(
       paths(
           handlers::posts::create_post,
           handlers::posts::get_post,
       ),
       components(schemas(Post, CreatePostRequest)),
       tags((name = "posts", description = "Content service posts API"))
   )]
   pub struct ApiDoc;
   ```

3. 在 `main.rs` (Actix `App::new()`) 中掛上路由：
   ```rust
   use utoipa_swagger_ui::SwaggerUi;

   let openapi = ApiDoc::openapi();

   .app_data(web::Data::new(openapi.clone()))
   .route(
       "/api/v1/openapi.json",
       web::get().to(|doc: web::Data<utoipa::openapi::OpenApi>| async move {
           HttpResponse::Ok()
               .content_type("application/json")
               .body(serde_json::to_string(&*doc).unwrap())
       }),
   )
   .service(
       SwaggerUi::new("/swagger-ui/{_:.*}")
           .url("/api/v1/openapi.json", openapi),
   )
   ```

4. 重新部署後，即可透過  
   - Swagger UI：`https://{ENV}-api.nova.example.com/<service>/swagger-ui/`  
   - OpenAPI：`https://{ENV}-api.nova.example.com/<service>/api/v1/openapi.json`

---

## 後續建議

- 將本文件同步到開發 Wiki，並定期更新 Swagger 狀態。  
- 對於尚未導出 OpenAPI 的服務，優先在 `staging` 環境驗證路由；一旦穩定可部署至 production。  
- 若有 API Gateway / Ingress，加上一層 Rewrite 規則，統一以 `/users`, `/auth`, `/content` 等前綴對外暴露 Swagger UI，方便前端快速存取。
- 在 CI/CD 部署流程中加入 `curl -sf https://{ENV}-api.nova.example.com/auth/api/v1/openapi.json` 等檢查，確保文件端點可用。
- 若使用 `scripts/smoke-staging.sh` 作為部署後健檢，現已自動檢查所有服務的 `/api/v1/openapi.json`，可直接在 pipeline 中呼叫。
