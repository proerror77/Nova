# messaging-service Axum → Actix 迁移指南

## 当前状态

**架构层**: ✅ 已完成 (HTTP Server, WebSocket Actor, Middleware)
**业务层**: ⚠️ 需修复 (13 个 handler 文件有编译错误)

**编译错误数**: 99 个
**主要错误类型**:
- `unresolved import axum` (剩余的 axum 引用)
- `cannot find type HttpResponse` (缺少 actix-web 导入)
- `cannot find function Json` (提取器未导入)
- `mismatched types` (返回类型不匹配)

---

## 修复策略

### 方法 1: 手动逐文件修复 (推荐,更可控)

**步骤**:

1. **选择一个文件开始** (例如: `src/routes/messages.rs`)

2. **删除所有 Axum imports**:
```rust
// 删除这些行
use axum::extract::{State, Path, Json, Query};
use axum::response::IntoResponse;
use axum::http::StatusCode;
use axum::Router;
```

3. **添加 Actix-Web imports**:
```rust
// 在文件顶部添加
use actix_web::{web, HttpResponse, Error};
```

4. **修改每个 handler 函数签名**:

**示例 1: 简单 GET 请求**
```rust
// Before (Axum)
async fn get_messages(
    State(app_state): State<AppState>,
    Path(conversation_id): Path<Uuid>,
    Query(params): Query<MessageQueryParams>,
) -> Result<impl IntoResponse, AppError> {
    let messages = fetch_messages(&app_state.db, conversation_id, params).await?;
    Ok((StatusCode::OK, Json(messages)))
}

// After (Actix)
async fn get_messages(
    app_state: web::Data<AppState>,
    conversation_id: web::Path<Uuid>,
    params: web::Query<MessageQueryParams>,
) -> Result<HttpResponse, Error> {
    let messages = fetch_messages(&app_state.db, *conversation_id, params.into_inner()).await?;
    Ok(HttpResponse::Ok().json(messages))
}
```

**示例 2: POST 请求 with JSON body**
```rust
// Before (Axum)
async fn create_message(
    State(app_state): State<AppState>,
    Path(conversation_id): Path<Uuid>,
    Json(req): Json<CreateMessageRequest>,
) -> Result<impl IntoResponse, AppError> {
    let message = create_msg(&app_state.db, conversation_id, req).await?;
    Ok((StatusCode::CREATED, Json(message)))
}

// After (Actix)
async fn create_message(
    app_state: web::Data<AppState>,
    conversation_id: web::Path<Uuid>,
    req: web::Json<CreateMessageRequest>,
) -> Result<HttpResponse, Error> {
    let message = create_msg(&app_state.db, *conversation_id, req.into_inner()).await?;
    Ok(HttpResponse::Created().json(message))
}
```

**示例 3: DELETE 请求**
```rust
// Before (Axum)
async fn delete_message(
    State(app_state): State<AppState>,
    Path((conversation_id, message_id)): Path<(Uuid, Uuid)>,
) -> Result<impl IntoResponse, AppError> {
    delete_msg(&app_state.db, conversation_id, message_id).await?;
    Ok(StatusCode::NO_CONTENT)
}

// After (Actix)
async fn delete_message(
    app_state: web::Data<AppState>,
    ids: web::Path<(Uuid, Uuid)>,
) -> Result<HttpResponse, Error> {
    let (conversation_id, message_id) = ids.into_inner();
    delete_msg(&app_state.db, conversation_id, message_id).await?;
    Ok(HttpResponse::NoContent().finish())
}
```

5. **处理 StatusCode 返回**:

```rust
// Axum 模式
Ok(StatusCode::OK)
Ok(StatusCode::CREATED)
Ok(StatusCode::NO_CONTENT)

// Actix 模式
Ok(HttpResponse::Ok().finish())
Ok(HttpResponse::Created().finish())
Ok(HttpResponse::NoContent().finish())
```

6. **编译检查**:
```bash
cd backend/messaging-service
cargo check
```

7. **重复步骤 1-6** 直到所有文件修复完成

---

### 方法 2: 批量替换 (快速但可能需要手动调整)

创建修复脚本 `scripts/fix_messaging_final.sh`:

```bash
#!/bin/bash
set -e

cd backend/messaging-service/src

# 需要修复的文件列表
FILES=(
    "routes/calls.rs"
    "routes/conversations.rs"
    "routes/groups.rs"
    "routes/messages.rs"
    "routes/reactions.rs"
    "routes/locations.rs"
    "routes/key_exchange.rs"
    "routes/rtc.rs"
    "routes/notifications.rs"
    "routes/attachments.rs"
    "websocket/events.rs"
    "websocket/streams.rs"
    "handlers/websocket_offline.rs"
)

for file in "${FILES[@]}"; do
    echo "Processing $file..."

    # 1. 删除 axum imports
    sed -i '' '/use axum::/d' "$file"

    # 2. 添加 actix-web import (如果不存在)
    if ! grep -q "use actix_web::" "$file"; then
        sed -i '' '1i\
use actix_web::{web, HttpResponse, Error};\
' "$file"
    fi

    # 3. 替换常见模式 (需要人工检查)
    # Note: 这些是简单替换,复杂的 handler 需要手动调整
done

echo "✅ Batch processing complete. Now run 'cargo check' and fix remaining errors manually."
```

**运行**:
```bash
chmod +x scripts/fix_messaging_final.sh
./scripts/fix_messaging_final.sh
cd backend/messaging-service && cargo check
```

---

## 常见问题修复

### 问题 1: `web::Path<T>` 提取值

```rust
// 错误
async fn handler(id: web::Path<Uuid>) {
    let uuid = id; // id 是 Path<Uuid>,不是 Uuid
}

// 正确
async fn handler(id: web::Path<Uuid>) {
    let uuid = *id; // 解引用
    // 或
    let uuid = id.into_inner(); // 消费 Path
}
```

### 问题 2: `web::Json<T>` 提取值

```rust
// 错误
async fn handler(req: web::Json<Request>) {
    process(req); // req 是 Json<Request>,不是 Request
}

// 正确
async fn handler(req: web::Json<Request>) {
    let data = req.into_inner(); // 获取内部值
    process(data);
}
```

### 问题 3: 返回 JSON 响应

```rust
// Axum
Ok((StatusCode::OK, Json(data)))

// Actix
Ok(HttpResponse::Ok().json(data))
```

### 问题 4: 返回空响应

```rust
// Axum
Ok(StatusCode::NO_CONTENT)

// Actix
Ok(HttpResponse::NoContent().finish())
```

### 问题 5: 错误处理

```rust
// 如果 AppError 已经实现了 ResponseError trait (已在 error.rs 完成)
async fn handler() -> Result<HttpResponse, Error> {
    // AppError 会自动转换为 actix_web::Error
    Err(AppError::NotFound("Message not found".into()))?;
    Ok(HttpResponse::Ok().finish())
}
```

### 问题 6: 从 Request Extensions 提取数据

```rust
// Axum
async fn handler(Extension(user_id): Extension<UserId>) { ... }

// Actix (如果使用 actix-middleware::UserId)
use actix_middleware::UserId;

async fn handler(user_id: UserId) -> Result<HttpResponse, Error> {
    // UserId 已实现 FromRequest trait
    let uuid = user_id.0;
}

// 或者手动从 extensions 提取
async fn handler(req: HttpRequest) -> Result<HttpResponse, Error> {
    let user_id = req.extensions()
        .get::<UserId>()
        .ok_or(actix_web::error::ErrorUnauthorized("Not authenticated"))?;
}
```

---

## 逐文件修复检查清单

使用此清单逐个完成文件修复:

- [ ] `src/routes/calls.rs`
  - [ ] 删除 axum imports
  - [ ] 添加 actix-web imports
  - [ ] 修改 handler 签名
  - [ ] 修改返回语句
  - [ ] `cargo check` 通过

- [ ] `src/routes/conversations.rs`
  - [ ] 删除 axum imports
  - [ ] 添加 actix-web imports
  - [ ] 修改 handler 签名
  - [ ] 修改返回语句
  - [ ] `cargo check` 通过

- [ ] `src/routes/groups.rs`
  - [ ] 删除 axum imports
  - [ ] 添加 actix-web imports
  - [ ] 修改 handler 签名
  - [ ] 修改返回语句
  - [ ] `cargo check` 通过

- [ ] `src/routes/messages.rs`
  - [ ] 删除 axum imports
  - [ ] 添加 actix-web imports
  - [ ] 修改 handler 签名
  - [ ] 修改返回语句
  - [ ] `cargo check` 通过

- [ ] `src/routes/reactions.rs`
  - [ ] 删除 axum imports
  - [ ] 添加 actix-web imports
  - [ ] 修改 handler 签名
  - [ ] 修改返回语句
  - [ ] `cargo check` 通过

- [ ] `src/routes/locations.rs`
  - [ ] 删除 axum imports
  - [ ] 添加 actix-web imports
  - [ ] 修改 handler 签名
  - [ ] 修改返回语句
  - [ ] `cargo check` 通过

- [ ] `src/routes/key_exchange.rs`
  - [ ] 删除 axum imports
  - [ ] 添加 actix-web imports
  - [ ] 修改 handler 签名
  - [ ] 修改返回语句
  - [ ] `cargo check` 通过

- [ ] `src/routes/rtc.rs`
  - [ ] 删除 axum imports
  - [ ] 添加 actix-web imports
  - [ ] 修改 handler 签名
  - [ ] 修改返回语句
  - [ ] `cargo check` 通过

- [ ] `src/routes/notifications.rs`
  - [ ] 删除 axum imports
  - [ ] 添加 actix-web imports
  - [ ] 修改 handler 签名
  - [ ] 修改返回语句
  - [ ] `cargo check` 通过

- [ ] `src/routes/attachments.rs`
  - [ ] 删除 axum imports
  - [ ] 添加 actix-web imports
  - [ ] 修改 handler 签名
  - [ ] 修改返回语句
  - [ ] `cargo check` 通过

- [ ] `src/websocket/events.rs`
  - [ ] 替换 `axum::extract::ws::Message` 引用
  - [ ] 如果需要发送 WebSocket 消息,使用 Actor 消息传递
  - [ ] `cargo check` 通过

- [ ] `src/websocket/streams.rs`
  - [ ] 替换 `axum::extract::ws::Message` 引用
  - [ ] `cargo check` 通过

- [ ] `src/handlers/websocket_offline.rs`
  - [ ] 删除 axum imports
  - [ ] 添加 actix-web imports
  - [ ] `cargo check` 通过

---

## 验证步骤

修复完成后,执行以下验证:

1. **编译检查**:
```bash
cd backend/messaging-service
cargo check
# 应该看到: Finished `dev` profile [unoptimized + debuginfo] target(s) in X.XXs
```

2. **编译构建**:
```bash
cargo build
```

3. **运行测试** (如果有):
```bash
cargo test
```

4. **本地启动测试**:
```bash
# 设置环境变量
export DATABASE_URL="postgresql://..."
export REDIS_URL="redis://localhost:6379"
export KAFKA_BROKERS="localhost:9092"

# 启动服务
cargo run
```

5. **WebSocket 连接测试**:
```bash
# 使用 wscat 测试 WebSocket
wscat -c ws://localhost:8080/ws?token=<jwt_token>
```

---

## 预计工作量

- **每个文件**: 5-15 分钟 (取决于复杂度)
- **总计 13 个文件**: 约 1-3 小时
- **测试与验证**: 约 30 分钟

**总预计**: 1.5 - 4 小时

---

## 如果遇到困难

1. **参考已迁移的服务**:
   - `backend/auth-service/src/handlers/auth.rs` (✅ 完整示例)
   - `backend/search-service/src/main.rs` (✅ 完整示例)

2. **查看 Actix 文档**:
   - https://actix.rs/docs/extractors/
   - https://actix.rs/docs/handlers/

3. **使用 diff 对比**:
```bash
# 对比 auth-service 迁移前后的变化
git diff HEAD~10 backend/auth-service/src/handlers/auth.rs
```

4. **逐步调试**:
   - 一次只修复一个文件
   - 每次修改后运行 `cargo check`
   - 根据编译错误调整

---

**Good luck! May the Force be with you.**
