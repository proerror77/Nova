# gRPC 指标集成示例

本文档展示如何在新的 gRPC 服务中集成 `grpc-metrics` 库。

## 完整示例：auth-service

### 步骤 1: 添加依赖

在 `backend/auth-service/Cargo.toml` 的 `[dependencies]` 部分添加：

```toml
grpc-metrics = { path = "../libs/grpc-metrics" }
```

### 步骤 2: 导入库

在 `backend/auth-service/src/grpc/mod.rs` 顶部添加：

```rust
use grpc_metrics::layer::RequestGuard;
```

### 步骤 3: 为 RPC 方法添加指标

#### 示例：Register 方法

**修改前**（来自 messaging-service）：

```rust
async fn register(
    &self,
    request: Request<RegisterRequest>,
) -> Result<Response<RegisterResponse>, Status> {
    let req = request.into_inner();

    // 验证邮箱格式
    if req.email.is_empty() {
        return Err(Status::invalid_argument("Email cannot be empty"));
    }

    // 检查邮箱是否已存在
    let user = sqlx::query_as::<_, (Uuid,)>(
        "SELECT id FROM users WHERE email = $1"
    )
    .bind(&req.email)
    .fetch_optional(&self.state.db)
    .await
    .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

    if user.is_some() {
        return Err(Status::already_exists("Email already registered"));
    }

    // 创建用户
    let user_id = Uuid::new_v4();
    sqlx::query(
        "INSERT INTO users (id, email, password_hash, created_at) VALUES ($1, $2, $3, $4)"
    )
    .bind(user_id)
    .bind(&req.email)
    .bind(&req.password)
    .bind(Utc::now())
    .execute(&self.state.db)
    .await
    .map_err(|e| Status::internal(format!("Database error: {}", e)))?;

    Ok(Response::new(RegisterResponse {
        user_id: user_id.to_string(),
    }))
}
```

**修改后**（添加指标）：

```rust
async fn register(
    &self,
    request: Request<RegisterRequest>,
) -> Result<Response<RegisterResponse>, Status> {
    // ← 步骤 1: 在方法开始添加 guard
    let guard = RequestGuard::new("auth-service", "Register");

    let req = request.into_inner();

    // 验证邮箱格式
    if req.email.is_empty() {
        // ← 步骤 2a: 记录错误代码
        guard.complete("3");  // INVALID_ARGUMENT
        return Err(Status::invalid_argument("Email cannot be empty"));
    }

    // 检查邮箱是否已存在
    let user = match sqlx::query_as::<_, (Uuid,)>(
        "SELECT id FROM users WHERE email = $1"
    )
    .bind(&req.email)
    .fetch_optional(&self.state.db)
    .await
    {
        Ok(result) => result,
        Err(e) => {
            // ← 步骤 2b: 记录数据库错误
            guard.complete("13");  // INTERNAL
            return Err(Status::internal(format!("Database error: {}", e)));
        }
    };

    if user.is_some() {
        // ← 步骤 2c: 记录已存在错误
        guard.complete("6");  // ALREADY_EXISTS
        return Err(Status::already_exists("Email already registered"));
    }

    // 创建用户
    let user_id = Uuid::new_v4();
    match sqlx::query(
        "INSERT INTO users (id, email, password_hash, created_at) VALUES ($1, $2, $3, $4)"
    )
    .bind(user_id)
    .bind(&req.email)
    .bind(&req.password)
    .bind(Utc::now())
    .execute(&self.state.db)
    .await
    {
        Ok(_) => {},
        Err(e) => {
            // ← 步骤 2d: 记录插入错误
            guard.complete("13");  // INTERNAL
            return Err(Status::internal(format!("Database error: {}", e)));
        }
    }

    // ← 步骤 3: 成功时记录状态码
    guard.complete("0");  // OK
    Ok(Response::new(RegisterResponse {
        user_id: user_id.to_string(),
    }))
}
```

#### 模式总结

```rust
async fn method_name(
    &self,
    request: Request<RequestType>,
) -> Result<Response<ResponseType>, Status> {
    // 1. 创建守卫
    let guard = RequestGuard::new("service-name", "MethodName");

    let req = request.into_inner();

    // 2a. 验证错误 -> 记录 INVALID_ARGUMENT (3)
    if invalid_input {
        guard.complete("3");
        return Err(Status::invalid_argument(...));
    }

    // 2b. 资源不存在 -> 记录 NOT_FOUND (5)
    if resource_not_found {
        guard.complete("5");
        return Err(Status::not_found(...));
    }

    // 2c. 资源已存在 -> 记录 ALREADY_EXISTS (6)
    if resource_exists {
        guard.complete("6");
        return Err(Status::already_exists(...));
    }

    // 2d. 权限错误 -> 记录 PERMISSION_DENIED (7)
    if no_permission {
        guard.complete("7");
        return Err(Status::permission_denied(...));
    }

    // 2e. 内部错误 -> 记录 INTERNAL (13)
    let result = operation().await
        .map_err(|e| {
            guard.complete("13");
            Status::internal(...)
        })?;

    // 2f. 外部服务不可用 -> 记录 UNAVAILABLE (14)
    let external_result = external_service().await
        .map_err(|e| {
            guard.complete("14");
            Status::unavailable(...)
        })?;

    // 3. 成功 -> 记录 OK (0)
    guard.complete("0");
    Ok(Response::new(response))
}
```

## 关键要点

### 1. 所有错误路径都要记录状态

不要遗漏任何 early return：

```rust
// ❌ 错误：忘记记录
if invalid {
    return Err(Status::invalid_argument(...));
}

// ✅ 正确：记录状态
if invalid {
    guard.complete("3");
    return Err(Status::invalid_argument(...));
}
```

### 2. 正确的状态码映射

| 情况 | 代码 | 示例 |
|------|------|------|
| 参数验证失败 | 3 | `guard.complete("3");` |
| 资源不存在 | 5 | `guard.complete("5");` |
| 资源已存在 | 6 | `guard.complete("6");` |
| 权限不足 | 7 | `guard.complete("7");` |
| 内部错误（DB等） | 13 | `guard.complete("13");` |
| 外部服务不可用 | 14 | `guard.complete("14");` |
| 成功 | 0 | `guard.complete("0");` |

### 3. 避免双重 Complete

```rust
// ❌ 错误：调用两次
guard.complete("3");
guard.complete("0");

// ✅ 正确：只调用一次
if error {
    guard.complete("3");
} else {
    guard.complete("0");
}
```

### 4. 处理 await + map_err

避免在 map_err 闭包中使用 guard（会导致所有权问题）：

```rust
// ❌ 不推荐：map_err 闭包
result.await.map_err(|e| {
    guard.complete("13");
    Status::internal(...)
})?;

// ✅ 推荐：分离处理
let result = operation().await;
if let Err(e) = result {
    guard.complete("13");
    return Err(Status::internal(...));
}
```

## 验证集成

### 1. 编译验证

```bash
cargo check -p auth-service --lib
# 应该输出: Finished `dev` profile
```

### 2. 运行时验证

启动服务后，调用 RPC：

```bash
# 使用 grpcurl 调用
grpcurl -plaintext \
  -d '{"email":"test@example.com","password":"123"}' \
  localhost:50051 \
  auth.AuthService/Register
```

### 3. 指标验证

检查 Prometheus 端点：

```bash
curl http://localhost:8081/metrics | grep grpc_server_requests_total

# 应该看到：
# grpc_server_requests_total{code="0",method="Register",service="auth-service"} 1
```

## 常见错误

### 错误 1：忘记导入

```rust
// ❌ 错误
let guard = RequestGuard::new(...);

// ✅ 正确
use grpc_metrics::layer::RequestGuard;
let guard = RequestGuard::new(...);
```

### 错误 2：使用错误的服务名

```rust
// ❌ 错误
let guard = RequestGuard::new("auth", "Register");

// ✅ 正确（使用完整服务名）
let guard = RequestGuard::new("auth-service", "Register");
```

### 错误 3：没有记录成功状态

```rust
// ❌ 错误（没有记录 OK）
let result = process();
Ok(Response::new(result))

// ✅ 正确
let result = process();
guard.complete("0");
Ok(Response::new(result))
```

## 集成检查清单

对于每个服务：

- [ ] 添加 `grpc-metrics` 到 `Cargo.toml`
- [ ] 导入 `RequestGuard`
- [ ] 为所有 RPC 方法添加 guard
- [ ] 在所有错误路径记录正确的状态码
- [ ] 在成功路径记录 "0"
- [ ] 库部分编译成功: `cargo check -p <service> --lib`
- [ ] 验证指标输出

## 参考

- [gRPC 状态码完整列表](https://grpc.io/docs/guides/status-codes/)
- [grpc-metrics README](./libs/grpc-metrics/README.md)
- [RED 指标框架](https://www.weave.works/blog/the-red-method-key-metrics-for-microservices-architecture/)
