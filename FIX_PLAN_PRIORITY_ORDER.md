# Nova 后端修复优先级计划 - 立即执行清单

## 第 1 天：编译错误修复（CRITICAL）

### Task 1.1：修复 content-service 编译错误
**预计时间：30 分钟**

**问题：** `middleware` 模块未导入

**操作步骤：**
```bash
# 1. 打开文件
vi /Users/proerror/Documents/nova/backend/content-service/src/main.rs

# 2. 在文件顶部添加导入（第 10 行左右）
use content_service::middleware;

# 3. 保存并验证
cargo check -p content-service

# 应该通过或显示其他可以修复的错误
```

---

### Task 1.2：修复 media-service Uuid FromRequest 错误
**预计时间：1 小时**

**问题：** video handler 中使用 `Uuid` 但未实现 `FromRequest`

**操作步骤：**
```bash
# 1. 查看错误位置
cd /Users/proerror/Documents/nova
cargo check -p media-service 2>&1 | grep "Uuid"

# 2. 打开 media-service/src/handlers/videos.rs
vi backend/media-service/src/handlers/videos.rs

# 3. 检查 create_video handler 签名，应该使用 web::Path 提取器
# 错误示例：
async fn create_video(
    pool: web::Data<PgPool>,
    user_id: Uuid,  // ❌ 不能直接从 body 提取 Uuid
    req: web::Json<CreateVideoRequest>,
) -> Result<HttpResponse>

# 应该改为：
async fn create_video(
    pool: web::Data<PgPool>,
    user_id: UserId,  // ✅ 使用自定义 FromRequest 提取器
    req: web::Json<CreateVideoRequest>,
) -> Result<HttpResponse>
```

**验证：**
```bash
cargo check -p media-service
```

---

### Task 1.3：修复 user-service 值移动错误
**预计时间：1 小时**

**问题：** `blocked_user_id` 值被移动两次

**位置：** `backend/user-service/src/handlers/preferences.rs:240-280`

**操作步骤：**
```rust
// ❌ 错误代码（第 244 和 280 行）
if user_id == blocked_user_id.into_inner() {  // 第一次 move
    // ...
}
let blocked_id_str = blocked_user_id.into_inner().to_string();  // ❌ 第二次使用

// ✅ 修复方案
let blocked_id = blocked_user_id.into_inner();  // 一次 move，保存结果
if user_id == blocked_id {
    // ...
}
let blocked_id_str = blocked_id.to_string();  // 使用保存的值
```

**验证：**
```bash
cargo check -p user-service
```

---

### Task 1.4：修复 AppError 类型错误
**预计时间：1 小时**

**问题：** `AppError::Unauthorized` 变体不存在

**位置：** `backend/user-service/src/error.rs` 和 `src/handlers/preferences.rs:358`

**操作步骤：**

1. **检查错误定义：**
```bash
vi backend/user-service/src/error.rs
```

2. **添加缺失的错误变体：**
```rust
#[derive(Debug)]
pub enum AppError {
    Database(sqlx::Error),
    Redis(RedisError),
    Validation(String),
    Authentication(String),
    Authorization(String),
    Unauthorized,  // ✅ 添加此行
    NotFound(String),
    // ...
}

impl ResponseError for AppError {
    fn status_code(&self) -> StatusCode {
        match self {
            // ...
            AppError::Unauthorized => StatusCode::UNAUTHORIZED,  // ✅ 添加此行
            // ...
        }
    }
}
```

3. **验证：**
```bash
cargo check -p user-service
```

---

## 第 2 天：安全加固（CRITICAL）

### Task 2.1：修复 JWT 密钥硬编码
**预计时间：2 小时**

**操作步骤：**

1. **编辑 docker-compose.dev.yml（仅用于开发）：**
```bash
vi docker-compose.dev.yml

# 保持为测试密钥
JWT_SECRET: dev_secret_change_in_production_32chars  # ✅ OK for dev
```

2. **编辑 Kubernetes secrets.yaml（生产用）：**
```bash
vi k8s/base/secrets.yaml

stringData:
  JWT_PUBLIC_KEY_PEM: |
    ${JWT_PUBLIC_KEY}  # ✅ 由 CI/CD 替换
  JWT_PRIVATE_KEY_PEM: |
    ${JWT_PRIVATE_KEY}  # ✅ 由 CI/CD 替换
```

3. **在各服务中添加生产检查：**
```bash
# 编辑 backend/user-service/src/config.rs（其他服务类似）
vi backend/user-service/src/config.rs
```

**添加代码：**
```rust
impl Config {
    pub fn validate_production(&self) -> Result<(), String> {
        if self.app.env == "production" {
            // JWT 密钥验证
            let jwt_secret = std::env::var("JWT_SECRET")
                .map_err(|_| "JWT_SECRET not set in production".to_string())?;

            if jwt_secret.contains("dev_secret") || jwt_secret.len() < 32 {
                return Err("JWT_SECRET is too weak for production".to_string());
            }

            // 数据库密码验证
            if self.database.url.contains("nova_password") {
                return Err("Database password looks like default, change it!".to_string());
            }
        }

        Ok(())
    }
}
```

4. **在 main.rs 中调用验证：**
```bash
vi backend/user-service/src/main.rs
```

```rust
#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let config = Config::from_env();

    // 生产环境验证
    config.validate_production()
        .expect("Configuration validation failed");

    // ... 继续启动服务
}
```

5. **验证：**
```bash
# 开发环境应该通过
cargo run -p user-service

# 测试生产验证
APP_ENV=production cargo run -p user-service
# 应该报错提示需要设置真实密钥
```

---

### Task 2.2：修复 CORS 过于宽松
**预计时间：1 小时**

**问题位置：**
- `backend/content-service/src/config.rs:106`
- `backend/media-service/src/config.rs`

**操作步骤：**

1. **修复 content-service:**
```bash
vi backend/content-service/src/config.rs
```

**找到并修改：**
```rust
// ❌ 错误
allowed_origins: std::env::var("CORS_ALLOWED_ORIGINS")
    .unwrap_or_else(|_| "*".to_string()),

// ✅ 修复
allowed_origins: {
    let origins = std::env::var("CORS_ALLOWED_ORIGINS")
        .unwrap_or_else(|_| "http://localhost:3000".to_string());

    // 生产环境验证
    if std::env::var("APP_ENV").unwrap_or_default() == "production" {
        if origins == "*" {
            panic!("CORS_ALLOWED_ORIGINS cannot be '*' in production");
        }
    }

    origins
},
```

2. **修复其他服务（media-service, user-service）：**
```bash
# 搜索所有 CORS 配置
grep -r "allow_any_origin\|CORS_ALLOWED_ORIGINS" backend/ --include="*.rs"

# 逐个修复
```

3. **验证：**
```bash
# 开发环境应该使用默认值
APP_ENV=development cargo check -p content-service

# 生产环境必须显式设置
APP_ENV=production CORS_ALLOWED_ORIGINS="https://example.com" cargo check -p content-service
```

---

### Task 2.3：启用 HTTPS/TLS
**预计时间：1.5 小时**

**操作步骤：**

1. **生成自签名证书（用于本地测试）：**
```bash
mkdir -p /Users/proerror/Documents/nova/backend/certs
cd /Users/proerror/Documents/nova/backend/certs

# 生成自签名证书（10 年有效期）
openssl req -x509 -newkey rsa:4096 -keyout tls.key -out tls.crt -days 3650 -nodes \
    -subj "/CN=localhost"

# 验证
ls -la
# 应该看到 tls.crt 和 tls.key
```

2. **更新 nginx 配置：**
```bash
vi backend/nginx/nginx.conf
```

**找到并修改 server block：**
```nginx
server {
    # 原有配置
    listen 80;

    # ✅ 添加 HTTPS 支持
    listen 443 ssl http2;

    # ✅ 证书路径（Docker 中）
    ssl_certificate /etc/nginx/certs/tls.crt;
    ssl_certificate_key /etc/nginx/certs/tls.key;

    # ✅ SSL 安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;

    # ✅ HTTP 重定向到 HTTPS（可选，生产推荐）
    if ($scheme = http) {
        return 301 https://$server_name$request_uri;
    }
}
```

3. **更新 Docker Compose 挂载证书：**
```bash
vi docker-compose.dev.yml
```

**找到 nginx 服务，修改 volumes：**
```yaml
nginx:
  image: nginx:alpine
  ports:
    - "80:80"
    - "443:443"  # ✅ 添加 HTTPS 端口
  volumes:
    - ./backend/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    - ./backend/nginx/conf.d:/etc/nginx/conf.d:ro
    - ./backend/certs:/etc/nginx/certs:ro  # ✅ 挂载证书
```

4. **验证：**
```bash
# 重建 Docker 镜像
docker-compose -f docker-compose.dev.yml down
docker-compose -f docker-compose.dev.yml up -d nginx

# 测试 HTTP（应该重定向到 HTTPS）
curl -i http://localhost/api/v1/health
# 应该看到 301 重定向

# 测试 HTTPS（接受自签名证书）
curl -k https://localhost/api/v1/health
# 应该返回 200
```

---

## 第 3 天：数据库和备份（CRITICAL）

### Task 3.1：实现数据库自动备份
**预计时间：2 小时**

**操作步骤：**

1. **创建备份脚本：**
```bash
mkdir -p /Users/proerror/Documents/nova/scripts
cat > /Users/proerror/Documents/nova/scripts/backup-db.sh << 'EOF'
#!/bin/bash

# 数据库备份脚本
set -e

DB_HOST=${DB_HOST:-localhost}
DB_USER=${DB_USER:-nova}
DB_NAME=${DB_NAME:-nova_auth}
BACKUP_DIR=${BACKUP_DIR:-./backups}

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 备份文件名（包含时间戳）
BACKUP_FILE="$BACKUP_DIR/postgres_$(date +%Y%m%d_%H%M%S).sql.gz"

echo "开始备份 PostgreSQL: $DB_NAME"

# 执行备份
pg_dump -h "$DB_HOST" -U "$DB_USER" "$DB_NAME" | gzip > "$BACKUP_FILE"

echo "备份完成: $BACKUP_FILE"

# 删除 30 天前的备份（可选）
find "$BACKUP_DIR" -name "postgres_*.sql.gz" -mtime +30 -delete

# 上传到 S3（可选，需要 AWS CLI）
if command -v aws &> /dev/null; then
    echo "上传到 S3..."
    aws s3 cp "$BACKUP_FILE" "s3://nova-backups/$(basename $BACKUP_FILE)"
fi

echo "完成！"
EOF

chmod +x /Users/proerror/Documents/nova/scripts/backup-db.sh
```

2. **测试备份脚本：**
```bash
# 启动 Docker Compose（确保 PostgreSQL 运行）
docker-compose -f docker-compose.dev.yml up -d postgres

# 等待数据库启动
sleep 5

# 执行备份
DB_HOST=localhost DB_USER=nova DB_NAME=nova_auth \
    ./scripts/backup-db.sh

# 验证备份文件
ls -lh backups/
```

3. **配置定时执行（Linux/Mac）：**
```bash
# 编辑 crontab
crontab -e

# 添加每天午夜备份
0 0 * * * /Users/proerror/Documents/nova/scripts/backup-db.sh >> /tmp/backup.log 2>&1
```

4. **Docker Compose 中配置自动备份（可选）：**
```bash
vi docker-compose.dev.yml

# 在 postgres 服务后添加备份服务
backup:
  image: postgres:15-alpine
  depends_on:
    - postgres
  environment:
    PGPASSWORD: nova_password
  entrypoint:
    - /bin/sh
    - -c
    - |
      while true; do
        echo "Backup at $(date)"
        pg_dump -h postgres -U nova nova_auth | gzip > /backups/backup_$(date +%Y%m%d_%H%M%S).sql.gz
        # 保留最近 7 天的备份
        find /backups -name "*.sql.gz" -mtime +7 -delete
        sleep 86400  # 24 小时
      done
  volumes:
    - ./backups:/backups
```

---

### Task 3.2：测试备份恢复流程
**预计时间：1.5 小时**

**操作步骤：**

1. **创建恢复脚本：**
```bash
cat > /Users/proerror/Documents/nova/scripts/restore-db.sh << 'EOF'
#!/bin/bash

set -e

BACKUP_FILE=$1
DB_HOST=${DB_HOST:-localhost}
DB_USER=${DB_USER:-nova}
DB_NAME=${DB_NAME:-nova_auth}

if [ -z "$BACKUP_FILE" ]; then
    echo "用法: $0 <backup_file>"
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "错误: 备份文件不存在: $BACKUP_FILE"
    exit 1
fi

echo "从 $BACKUP_FILE 恢复数据库..."

# 删除现有数据库
psql -h "$DB_HOST" -U "$DB_USER" -c "DROP DATABASE IF EXISTS $DB_NAME;"

# 创建新数据库
psql -h "$DB_HOST" -U "$DB_USER" -c "CREATE DATABASE $DB_NAME;"

# 恢复数据
if [[ "$BACKUP_FILE" == *.gz ]]; then
    gunzip -c "$BACKUP_FILE" | psql -h "$DB_HOST" -U "$DB_USER" "$DB_NAME"
else
    psql -h "$DB_HOST" -U "$DB_USER" "$DB_NAME" < "$BACKUP_FILE"
fi

echo "恢复完成！"
EOF

chmod +x /Users/proerror/Documents/nova/scripts/restore-db.sh
```

2. **测试恢复：**
```bash
# 1. 创建备份
DB_HOST=localhost DB_USER=nova DB_NAME=nova_auth \
    ./scripts/backup-db.sh

# 2. 恢复测试
DB_HOST=localhost DB_USER=nova DB_NAME=nova_auth \
    ./scripts/restore-db.sh backups/postgres_*.sql.gz

# 3. 验证数据
psql -h localhost -U nova nova_auth -c "SELECT COUNT(*) FROM users;"
```

---

## 第 4 天：API 限流和监控（HIGH）

### Task 4.1：配置差异化 API 限流
**预计时间：1.5 小时**

**操作步骤：**

1. **编辑 nginx 配置：**
```bash
vi backend/nginx/nginx.conf
```

**在 http 块中添加限流区域：**
```nginx
http {
    # 全局限流（默认）
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=100r/s;

    # 注册端点限流：10 req/min per IP
    limit_req_zone $binary_remote_addr zone=auth_register_limit:10m rate=10r/m;

    # 登录端点限流：5 req/min per IP
    limit_req_zone $binary_remote_addr zone=auth_login_limit:10m rate=5r/m;

    # 搜索端点限流：20 req/sec
    limit_req_zone $binary_remote_addr zone=search_limit:10m rate=20r/s;

    # ... 其他配置
}
```

**在各个 location 块中应用：**
```nginx
location ~ ^/api/v1/auth/register$ {
    limit_req zone=auth_register_limit burst=2 nodelay;
    # 限制注册：10 req/分钟，允许 2 个 burst
    proxy_pass http://user_service;
}

location ~ ^/api/v1/auth/login$ {
    limit_req zone=auth_login_limit burst=1 nodelay;
    # 限制登录：5 req/分钟，允许 1 个 burst
    proxy_pass http://user_service;
}

location ~ ^/api/v1/search {
    limit_req zone=search_limit burst=5 nodelay;
    # 限制搜索：20 req/秒，允许 5 个 burst
    proxy_pass http://search_service;
}

location ~ ^/api/v1/ {
    limit_req zone=api_limit burst=20 nodelay;
    # 默认限制：100 req/秒
    proxy_pass http://backend;
}
```

2. **验证：**
```bash
# 测试注册限流（应该在 10 次后被限制）
for i in {1..15}; do
    curl -X POST http://localhost/api/v1/auth/register \
        -H "Content-Type: application/json" \
        -d '{"email":"test'$i'@example.com","password":"123456"}'
    echo "$i"
    sleep 1
done
```

---

### Task 4.2：改进健康检查端点
**预计时间：1 小时**

**操作步骤：**

1. **编辑所有服务的 health endpoint**

**示例（user-service）：**
```bash
vi backend/user-service/src/handlers/mod.rs
```

**添加健康检查处理器：**
```rust
use crate::AppState;

#[derive(Debug, serde::Serialize)]
pub struct HealthResponse {
    pub status: String,
    pub database: String,
    pub redis: String,
    pub timestamp: i64,
}

pub async fn health_check(state: web::Data<AppState>) -> impl Responder {
    let now = chrono::Utc::now().timestamp();

    // 检查数据库连接
    let db_status = if state.db.acquire().await.is_ok() {
        "healthy"
    } else {
        "unhealthy"
    };

    // 检查 Redis 连接
    let redis_status = if state.redis.ping().await.is_ok() {
        "healthy"
    } else {
        "unhealthy"
    };

    let overall_status = if db_status == "healthy" && redis_status == "healthy" {
        "ok"
    } else {
        "degraded"
    };

    let response = HealthResponse {
        status: overall_status.to_string(),
        database: db_status.to_string(),
        redis: redis_status.to_string(),
        timestamp: now,
    };

    HttpResponse::Ok().json(response)
}

pub async fn health_ready(state: web::Data<AppState>) -> impl Responder {
    // 同样的检查，但返回不同的 HTTP 状态码
    let db_ok = state.db.acquire().await.is_ok();
    let redis_ok = state.redis.ping().await.is_ok();

    if db_ok && redis_ok {
        HttpResponse::Ok().json(serde_json::json!({"ready": true}))
    } else {
        HttpResponse::ServiceUnavailable().json(serde_json::json!({"ready": false}))
    }
}

pub async fn health_live() -> impl Responder {
    // 仅检查进程是否存活（总是返回 200）
    HttpResponse::Ok().json(serde_json::json!({"alive": true}))
}
```

2. **在 main.rs 中注册路由：**
```bash
vi backend/user-service/src/main.rs
```

```rust
.route("/health", web::get().to(handlers::health_check))
.route("/health/ready", web::get().to(handlers::health_ready))
.route("/health/live", web::get().to(handlers::health_live))
```

3. **验证：**
```bash
# 启动服务
cargo run -p user-service

# 测试
curl http://localhost:8080/health
# 应该返回包含 database/redis 状态的 JSON

curl http://localhost:8080/health/ready
# 应该返回 200 或 503（取决于依赖状态）
```

---

## 完成检查

完成以上所有任务后，验证：

```bash
# 1. 编译检查（0 errors）
cargo check --all

# 2. 依赖安全检查
cargo audit

# 3. 格式检查
cargo fmt --all

# 4. Linter 检查
cargo clippy --all

# 5. 运行测试
cargo test --all

# 6. 构建 Docker 镜像
docker-compose -f docker-compose.dev.yml build

# 7. 启动服务
docker-compose -f docker-compose.dev.yml up -d

# 8. 测试 API
curl https://localhost/api/v1/health -k

echo "✅ 第 1 阶段修复完成！"
```

---

## 下一步

完成上述 4 天的修复后：

1. **Push 代码到 feature 分支**
   ```bash
   git add -A
   git commit -m "fix: 修复关键编译、安全和备份问题"
   git push origin feature/backend-optimization
   ```

2. **部署到 staging 环境**
   ```bash
   kubectl apply -k k8s/overlays/dev
   ```

3. **第 2-3 周：实施高优先级改进**
   - gRPC 重试和超时
   - CloudWatch 集成
   - 分布式追踪

4. **第 4-6 周：测试和优化**
   - 性能测试
   - 负载测试
   - 端到端测试

---

**加油！完成这 4 天的工作，你的后端就可以部署到 staging 环境了！** 🚀
