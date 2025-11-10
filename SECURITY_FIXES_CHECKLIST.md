# Security Fixes Checklist

**Use this checklist to track progress on security remediation**

---

## 🔴 P0 BLOCKERS (Week 1)

### [P0-1] JWT Secret 硬编码

**File**: `backend/user-service/src/config/mod.rs`

- [ ] **Step 1**: 移除默认值逻辑
  ```rust
  // BEFORE (line 297-305)
  fn default_jwt_secret() -> String {
      env::var("JWT_SECRET").unwrap_or_else(|_| {
          if env::var("APP_ENV").unwrap_or_default() == "production" {
              panic!("JWT_SECRET must not be empty in production");
          }
          "dev-jwt-secret-not-for-production".to_string()
      })
  }

  // AFTER
  fn default_jwt_secret() -> String {
      env::var("JWT_SECRET").unwrap_or_else(|_| {
          eprintln!("FATAL: JWT_SECRET environment variable not set");
          eprintln!("Generate a secure secret: openssl rand -base64 64");
          std::process::exit(1);
      })
  }
  ```

- [ ] **Step 2**: 添加启动时验证 (在 `main.rs`)
  ```rust
  // Add to main() after config loading
  validate_jwt_secret(&config.jwt.secret);

  fn validate_jwt_secret(secret: &str) {
      if secret.len() < 64 {
          eprintln!("FATAL: JWT_SECRET must be at least 64 characters");
          std::process::exit(1);
      }

      let weak_patterns = ["dev-", "test-", "secret", "password", "12345"];
      for pattern in &weak_patterns {
          if secret.to_lowercase().contains(pattern) {
              eprintln!("FATAL: JWT_SECRET contains weak pattern: {}", pattern);
              std::process::exit(1);
          }
      }
  }
  ```

- [ ] **Step 3**: 更新 Kubernetes Secret
  ```bash
  # Generate strong secret
  openssl rand -base64 64 > jwt_secret.txt

  # Create Kubernetes secret
  kubectl create secret generic nova-jwt-secret \
    --from-file=JWT_SECRET=jwt_secret.txt \
    -n nova

  # Update deployment to use secret
  # k8s/microservices/user-service-deployment.yaml
  ```

- [ ] **Step 4**: 更新文档
  - [ ] README.md: 添加 JWT_SECRET 生成指令
  - [ ] .env.example: 添加 JWT_SECRET 示例 (不包含实际值)

- [ ] **Verification**:
  ```bash
  # Test 1: Start without JWT_SECRET should fail
  unset JWT_SECRET
  cargo run # Should exit with error

  # Test 2: Weak secret should fail
  export JWT_SECRET="dev-secret-12345"
  cargo run # Should exit with error

  # Test 3: Strong secret should work
  export JWT_SECRET=$(openssl rand -base64 64)
  cargo run # Should start normally
  ```

---

### [P0-2] todo!() 宏移除

**Files**:
- `backend/messaging-service/src/routes/wsroute.rs:336-340`
- `backend/search-service/tests/unit/test_es_client.rs:7`

#### Fix 1: WebSocket Handler

- [ ] **Step 1**: 在 `WsSession` 结构体中添加 `app_state` 字段
  ```rust
  // wsroute.rs
  struct WsSession {
      conversation_id: Uuid,
      user_id: Uuid,
      client_id: Uuid,
      subscriber_id: SubscriberId,
      registry: ConnectionRegistry,
      redis: RedisClient,
      db: Pool<Postgres>,
      app_state: Arc<AppState>, // ✅ Add this
      hb: Instant,
  }
  ```

- [ ] **Step 2**: 更新 `WsSession::new()` 签名
  ```rust
  impl WsSession {
      fn new(
          conversation_id: Uuid,
          user_id: Uuid,
          client_id: Uuid,
          subscriber_id: SubscriberId,
          registry: ConnectionRegistry,
          redis: RedisClient,
          db: Pool<Postgres>,
          app_state: Arc<AppState>, // ✅ Add this parameter
      ) -> Self {
          Self {
              conversation_id,
              user_id,
              client_id,
              subscriber_id,
              registry,
              redis,
              db,
              app_state, // ✅ Store it
              hb: Instant::now(),
          }
      }
  }
  ```

- [ ] **Step 3**: 移除 `todo!()` 调用
  ```rust
  // BEFORE (line 336-340)
  let state = AppState {
      db: self.db.clone(),
      registry: self.registry.clone(),
      redis: self.redis.clone(),
      config: todo!(),
      apns: None,
      encryption: todo!(),
      key_exchange_service: None,
      auth_client: todo!(),
  };

  // AFTER
  let state = self.app_state.clone(); // ✅ Use stored state
  ```

- [ ] **Step 4**: 更新所有 `WsSession::new()` 调用点
  ```bash
  # Find all usages
  grep -rn "WsSession::new" backend/messaging-service/src/
  ```

- [ ] **Verification**:
  ```bash
  # Test WebSocket connection
  cargo test --package messaging-service --test test_ws_jwt_auth

  # Check for remaining todo!()
  grep -r "todo!()" backend/messaging-service/src/
  ```

#### Fix 2: Test Stub

- [ ] **Step 1**: 实现测试桩
  ```rust
  // search-service/tests/unit/test_es_client.rs
  // BEFORE
  fn connect_es(_url: &str) { todo!("connect_es not implemented") }

  // AFTER
  fn connect_es(_url: &str) {
      // Mock implementation for testing
      // Use reqwest mock or wiremock if needed
  }
  ```

- [ ] **Verification**:
  ```bash
  cargo test --package search-service --test test_es_client
  ```

---

### [P0-3] ON DELETE CASCADE 修复

**Files**: Multiple migration files

#### Phase 1: Add RESTRICT constraints (不破坏现有功能)

- [ ] **Step 1**: 创建新迁移文件
  ```bash
  # user-service
  sqlx migrate add fix_cascade_constraints_phase1

  # auth-service
  sqlx migrate add fix_cascade_constraints_phase1

  # messaging-service
  sqlx migrate add fix_cascade_constraints_phase1
  ```

- [ ] **Step 2**: 添加新的 RESTRICT 外键 (expand)
  ```sql
  -- user-service/migrations/XXX_fix_cascade_constraints_phase1.sql

  -- 1. search_suggestions
  ALTER TABLE search_suggestions
    ADD COLUMN user_id_v2 UUID;

  UPDATE search_suggestions
    SET user_id_v2 = user_id
    WHERE user_id IS NOT NULL;

  ALTER TABLE search_suggestions
    ALTER COLUMN user_id_v2 SET NOT NULL;

  ALTER TABLE search_suggestions
    ADD CONSTRAINT fk_search_suggestions_user_v2
    FOREIGN KEY (user_id_v2)
    REFERENCES users(id)
    ON DELETE RESTRICT; -- ✅ New constraint

  CREATE INDEX idx_search_suggestions_user_v2
    ON search_suggestions(user_id_v2);

  -- 2. reports (类似处理)
  -- 3. sessions (类似处理)
  -- ...
  ```

- [ ] **Step 3**: 实现 soft delete pattern
  ```sql
  -- Add deleted_at column to users table
  ALTER TABLE users
    ADD COLUMN deleted_at TIMESTAMPTZ DEFAULT NULL;

  CREATE INDEX idx_users_deleted_at
    ON users(deleted_at)
    WHERE deleted_at IS NULL;

  -- Create view for active users
  CREATE VIEW active_users AS
  SELECT * FROM users
  WHERE deleted_at IS NULL;
  ```

- [ ] **Step 4**: 更新应用代码使用 soft delete
  ```rust
  // user-service/src/handlers/users.rs

  // BEFORE
  pub async fn delete_user(
      db: web::Data<PgPool>,
      path: web::Path<Uuid>,
  ) -> Result<HttpResponse, Error> {
      let user_id = path.into_inner();
      sqlx::query("DELETE FROM users WHERE id = $1")
          .bind(user_id)
          .execute(db.get_ref())
          .await?;
      Ok(HttpResponse::NoContent().finish())
  }

  // AFTER
  pub async fn delete_user(
      db: web::Data<PgPool>,
      path: web::Path<Uuid>,
  ) -> Result<HttpResponse, Error> {
      let user_id = path.into_inner();

      // ✅ Soft delete
      sqlx::query(
          "UPDATE users
           SET deleted_at = NOW()
           WHERE id = $1 AND deleted_at IS NULL"
      )
      .bind(user_id)
      .execute(db.get_ref())
      .await?;

      Ok(HttpResponse::NoContent().finish())
  }

  // Update all queries to filter deleted users
  pub async fn get_user(
      db: web::Data<PgPool>,
      path: web::Path<Uuid>,
  ) -> Result<HttpResponse, Error> {
      let user = sqlx::query_as::<_, User>(
          "SELECT * FROM users
           WHERE id = $1 AND deleted_at IS NULL" // ✅ Filter
      )
      .bind(path.into_inner())
      .fetch_one(db.get_ref())
      .await?;

      Ok(HttpResponse::Ok().json(user))
  }
  ```

- [ ] **Verification**:
  ```bash
  # Test migrations
  sqlx migrate run --database-url "$DATABASE_URL"

  # Test soft delete
  cargo test --package user-service test_soft_delete

  # Check no CASCADE remains
  psql $DATABASE_URL -c "
    SELECT
      tc.table_name,
      kcu.column_name,
      ccu.table_name AS foreign_table_name,
      rc.delete_rule
    FROM information_schema.table_constraints AS tc
    JOIN information_schema.key_column_usage AS kcu
      ON tc.constraint_name = kcu.constraint_name
    JOIN information_schema.constraint_column_usage AS ccu
      ON ccu.constraint_name = tc.constraint_name
    JOIN information_schema.referential_constraints AS rc
      ON tc.constraint_name = rc.constraint_name
    WHERE tc.constraint_type = 'FOREIGN KEY'
      AND rc.delete_rule = 'CASCADE'
  "
  ```

#### Phase 2: Remove old constraints (contract) - 在 Phase 1 稳定运行 1 周后执行

- [ ] **Step 1**: 创建迁移移除旧字段
  ```sql
  -- XXX_fix_cascade_constraints_phase2.sql
  ALTER TABLE search_suggestions
    DROP CONSTRAINT fk_search_suggestions_user;

  ALTER TABLE search_suggestions
    DROP COLUMN user_id;

  ALTER TABLE search_suggestions
    RENAME COLUMN user_id_v2 TO user_id;
  ```

---

## 🟠 P1 HIGH PRIORITY (Week 2-4)

### [P1-4] gRPC TLS 加密

- [ ] **Step 1**: 生成 TLS 证书 (开发环境用 self-signed)
  ```bash
  # Generate CA
  openssl req -x509 -newkey rsa:4096 -days 365 -nodes \
    -keyout ca-key.pem -out ca-cert.pem \
    -subj "/CN=Nova CA"

  # Generate server certificate
  openssl req -newkey rsa:4096 -nodes \
    -keyout server-key.pem -out server-req.pem \
    -subj "/CN=user-service.nova.svc.cluster.local"

  # Sign with CA
  openssl x509 -req -in server-req.pem -days 365 \
    -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
    -out server-cert.pem
  ```

- [ ] **Step 2**: 创建 Kubernetes Secret
  ```bash
  kubectl create secret generic grpc-tls-certs \
    --from-file=ca.crt=ca-cert.pem \
    --from-file=server.crt=server-cert.pem \
    --from-file=server.key=server-key.pem \
    -n nova
  ```

- [ ] **Step 3**: 更新 gRPC server 代码
  ```rust
  // user-service/src/main.rs

  use tonic::transport::{Server, ServerTlsConfig, Identity, Certificate};
  use std::fs;

  // Load TLS config from environment
  let tls_config = if let (Ok(cert_path), Ok(key_path)) = (
      env::var("GRPC_TLS_CERT_PATH"),
      env::var("GRPC_TLS_KEY_PATH"),
  ) {
      let cert = fs::read(&cert_path)
          .context("Failed to read TLS certificate")?;
      let key = fs::read(&key_path)
          .context("Failed to read TLS key")?;

      let server_identity = Identity::from_pem(cert, key);

      Some(
          ServerTlsConfig::new()
              .identity(server_identity)
              // Optional: Enable mTLS
              .client_ca_root(
                  Certificate::from_pem(
                      fs::read(env::var("GRPC_CA_CERT_PATH")?)?
                  )
              )
      )
  } else {
      tracing::warn!("TLS not configured for gRPC server");
      None
  };

  let mut server_builder = Server::builder();
  if let Some(tls) = tls_config {
      server_builder = server_builder
          .tls_config(tls)
          .context("Failed to configure TLS")?;
  }

  server_builder
      .add_service(health_service)
      .add_service(grpc_server_svc)
      .serve_with_shutdown(grpc_addr_parsed, shutdown_signal)
      .await?;
  ```

- [ ] **Step 4**: 更新 gRPC client 代码
  ```rust
  // libs/grpc-clients/src/user_client.rs

  use tonic::transport::{ClientTlsConfig, Certificate};

  pub async fn connect(addr: &str) -> Result<Self> {
      let tls_config = if let Ok(ca_cert_path) = env::var("GRPC_CA_CERT_PATH") {
          let ca_cert = fs::read(ca_cert_path)
              .context("Failed to read CA certificate")?;
          Some(
              ClientTlsConfig::new()
                  .ca_certificate(Certificate::from_pem(ca_cert))
                  .domain_name("user-service.nova.svc.cluster.local")
          )
      } else {
          None
      };

      let mut endpoint = Channel::from_shared(addr.to_string())?;
      if let Some(tls) = tls_config {
          endpoint = endpoint.tls_config(tls)?;
      }

      let channel = endpoint.connect().await?;
      Ok(Self { client: UserServiceClient::new(channel) })
  }
  ```

- [ ] **Step 5**: 更新 Kubernetes deployment
  ```yaml
  # k8s/microservices/user-service-deployment.yaml
  spec:
    template:
      spec:
        containers:
        - name: user-service
          env:
          - name: GRPC_TLS_CERT_PATH
            value: /etc/tls/server.crt
          - name: GRPC_TLS_KEY_PATH
            value: /etc/tls/server.key
          - name: GRPC_CA_CERT_PATH
            value: /etc/tls/ca.crt
          volumeMounts:
          - name: tls-certs
            mountPath: /etc/tls
            readOnly: true
        volumes:
        - name: tls-certs
          secret:
            secretName: grpc-tls-certs
  ```

- [ ] **Verification**:
  ```bash
  # Test TLS connection
  grpcurl -d '{"user_id": "test"}' \
    -cacert ca-cert.pem \
    user-service.nova.svc.cluster.local:9080 \
    nova.UserService/GetUser

  # Test mTLS (if enabled)
  grpcurl -d '{"user_id": "test"}' \
    -cacert ca-cert.pem \
    -cert client-cert.pem \
    -key client-key.pem \
    user-service.nova.svc.cluster.local:9080 \
    nova.UserService/GetUser
  ```

---

### [P1-5] JWT jti 重放检查

- [ ] **Step 1**: 更新 `validate_token` 签名
  ```rust
  // user-service/src/security/jwt.rs

  pub async fn validate_token(
      token: &str,
      redis: &RedisManager,
  ) -> Result<TokenData<Claims>> {
      // Existing validation...
      let token_data = decode::<Claims>(token, &decoding_key, &validation)?;

      let jti = token_data
          .claims
          .jti
          .as_ref()
          .ok_or_else(|| anyhow!("Missing jti claim"))?;

      // ✅ Check revocation
      let revoked_key = format!("revoked:jti:{}", jti);
      if redis.exists(&revoked_key).await? {
          return Err(anyhow!("Token has been revoked"));
      }

      // ✅ Track usage for replay detection
      let replay_key = format!("jti:use:{}", jti);
      let use_count: i64 = redis.incr(&replay_key, 1).await?;

      if use_count == 1 {
          let exp_time = token_data.claims.exp as u64;
          let now = SystemTime::now()
              .duration_since(UNIX_EPOCH)?
              .as_secs();
          let ttl = exp_time.saturating_sub(now);
          redis.expire(&replay_key, ttl as usize).await?;
      } else if use_count > 3 {
          // ⚠️ Suspicious: same token used >3 times in short period
          tracing::warn!(
              jti = %jti,
              use_count = use_count,
              "Potential JWT replay attack"
          );
      }

      Ok(token_data)
  }
  ```

- [ ] **Step 2**: 更新 JWT 中间件
  ```rust
  // user-service/src/middleware/jwt_auth.rs

  impl<S, B> Service<ServiceRequest> for JwtMiddlewareService<S> {
      fn call(&self, req: ServiceRequest) -> Self::Future {
          // Extract token...
          let token = extract_token(&req)?;

          let redis = self.redis.clone();
          let fut = self.service.call(req);

          Box::pin(async move {
              // ✅ Validate with Redis check
              let token_data = validate_token(&token, &redis).await
                  .map_err(|e| actix_web::error::ErrorUnauthorized(e))?;

              // Store claims in request extensions
              req.extensions_mut().insert(token_data.claims);

              fut.await
          })
      }
  }
  ```

- [ ] **Verification**:
  ```bash
  # Test revocation
  curl -H "Authorization: Bearer $TOKEN" \
    https://api.nova.com/api/v1/auth/logout

  # Same token should fail
  curl -H "Authorization: Bearer $TOKEN" \
    https://api.nova.com/api/v1/users/me
  # Expected: 401 Unauthorized
  ```

---

### [P1-2] Per-IP Rate Limiting

- [ ] **Step 1**: 添加依赖
  ```toml
  # graphql-gateway/Cargo.toml
  [dependencies]
  governor = { version = "0.6", features = ["std"] }
  ```

- [ ] **Step 2**: 实现 per-IP limiter
  ```rust
  // graphql-gateway/src/middleware/rate_limit.rs

  use governor::{
      Quota, RateLimiter,
      state::{
          InMemoryState,
          keyed::DefaultKeyedStateStore,
      },
      clock::DefaultClock,
  };
  use std::net::IpAddr;

  pub struct RateLimitMiddleware {
      per_ip_limiter: Arc<RateLimiter<
          IpAddr,
          DefaultKeyedStateStore<IpAddr>,
          DefaultClock,
      >>,
      global_limiter: Arc<RateLimiter<
          (),
          InMemoryState,
          DefaultClock,
      >>,
      trusted_proxies: Vec<IpAddr>,
  }

  impl RateLimitMiddleware {
      pub fn new(config: RateLimitConfig) -> Self {
          let per_ip_quota = Quota::per_second(
              NonZeroU32::new(config.per_ip_rps).unwrap()
          );
          let global_quota = Quota::per_second(
              NonZeroU32::new(config.global_rps).unwrap()
          );

          Self {
              per_ip_limiter: Arc::new(RateLimiter::keyed(per_ip_quota)),
              global_limiter: Arc::new(RateLimiter::direct(global_quota)),
              trusted_proxies: config.trusted_proxies,
          }
      }

      fn extract_client_ip(&self, req: &ServiceRequest) -> IpAddr {
          let peer_ip = req.peer_addr()
              .map(|addr| addr.ip())
              .unwrap_or(IpAddr::from([127, 0, 0, 1]));

          // Only trust X-Forwarded-For from known proxies
          if !self.trusted_proxies.contains(&peer_ip) {
              return peer_ip;
          }

          // Parse X-Forwarded-For (rightmost untrusted IP)
          if let Some(xff) = req.headers().get("X-Forwarded-For") {
              if let Ok(header) = xff.to_str() {
                  for ip_str in header.split(',').rev() {
                      if let Ok(ip) = ip_str.trim().parse::<IpAddr>() {
                          if !self.trusted_proxies.contains(&ip) {
                              return ip;
                          }
                      }
                  }
              }
          }

          peer_ip
      }

      fn check_limits(&self, ip: IpAddr) -> Result<(), RateLimitError> {
          // Global limit first (fast path)
          self.global_limiter.check()
              .map_err(|_| RateLimitError::Global)?;

          // Per-IP limit
          self.per_ip_limiter.check_key(&ip)
              .map_err(|_| RateLimitError::PerIp(ip))?;

          Ok(())
      }
  }
  ```

- [ ] **Verification**:
  ```bash
  # Test per-IP limiting
  for i in {1..150}; do
    curl -s -o /dev/null -w "%{http_code}\n" \
      https://api.nova.com/graphql
  done
  # First 100 should be 200, rest 429
  ```

---

### [P1-8] CORS 配置修复

- [ ] **Step 1**: 更新 CORS 逻辑
  ```rust
  // user-service/src/main.rs

  use actix_cors::Cors;

  let allowed_origins: Vec<String> = match env::var("APP_ENV").as_deref() {
      Ok("development") | Ok("test") => {
          vec!["http://localhost:3000".to_string()]
      }
      _ => {
          server_config.cors.allowed_origins
              .split(',')
              .map(|s| s.trim().to_string())
              .filter(|s| !s.is_empty() && s != "*")
              .collect()
      }
  };

  if allowed_origins.is_empty() {
      eprintln!("FATAL: No valid CORS origins configured");
      std::process::exit(1);
  }

  tracing::info!("CORS allowed origins: {:?}", allowed_origins);

  let cors = Cors::default()
      .allowed_origin_fn(move |origin, _req_head| {
          let origin_str = origin.to_str().unwrap_or("");
          allowed_origins.iter().any(|allowed| allowed == origin_str)
      })
      .allowed_methods(vec!["GET", "POST", "PUT", "DELETE", "OPTIONS"])
      .allowed_headers(vec![
          "Authorization",
          "Content-Type",
          "Accept",
          "X-Request-ID",
      ])
      .expose_headers(vec!["X-Request-ID"])
      .max_age(3600)
      .supports_credentials();
  ```

- [ ] **Verification**:
  ```bash
  # Test CORS from allowed origin
  curl -H "Origin: https://app.nova.com" \
    -H "Access-Control-Request-Method: POST" \
    -X OPTIONS \
    https://api.nova.com/api/v1/users/me
  # Should return: Access-Control-Allow-Origin: https://app.nova.com

  # Test from disallowed origin
  curl -H "Origin: https://evil.com" \
    -X OPTIONS \
    https://api.nova.com/api/v1/users/me
  # Should NOT return Access-Control-Allow-Origin
  ```

---

## 🟡 P2 MEDIUM (Month 2-3)

### Batch Fixes: Replace unwrap/expect

- [ ] **Run automated refactoring**:
  ```bash
  # Find all unwrap() calls
  rg "\.unwrap\(\)" --type rust backend/ > unwrap_locations.txt

  # Semi-automated replacement (requires manual review)
  sd '\.unwrap\(\)' '.context("TODO: Add context")?' backend/**/*.rs
  ```

- [ ] **Manual review**: Each `.context()` needs a meaningful message

---

## Verification Matrix

| Fix | Unit Tests | Integration Tests | Manual Testing | Approved |
|-----|-----------|------------------|---------------|----------|
| P0-1: JWT Secret | ✅ | ✅ | ✅ | ⬜ |
| P0-2: todo!() | ✅ | ✅ | ✅ | ⬜ |
| P0-3: CASCADE | ✅ | ✅ | ✅ | ⬜ |
| P1-4: TLS | ✅ | ✅ | ✅ | ⬜ |
| P1-5: jti | ✅ | ✅ | ✅ | ⬜ |
| P1-2: Rate Limit | ✅ | ✅ | ✅ | ⬜ |
| P1-8: CORS | ✅ | ✅ | ✅ | ⬜ |

---

## Final Checklist

- [ ] All P0 fixes deployed to staging
- [ ] All P1 fixes deployed to staging
- [ ] Security penetration test passed
- [ ] SAST scan shows 0 Critical/High
- [ ] DAST scan shows 0 Critical/High
- [ ] Dependency audit clean
- [ ] Compliance review approved
- [ ] Production deployment approved

---

**Use `git grep -l "TODO: Security fix"` to find pending fixes**
