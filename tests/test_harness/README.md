# Test Harness 实现指南

## 用途

Test Harness 提供统一的测试基础设施接口,简化测试编写:

- 自动管理 Docker 容器生命周期
- 提供类型安全的客户端 (Kafka, ClickHouse, PostgreSQL, Redis, Feed API)
- 处理连接池、重试、超时等底层细节
- 确保测试隔离和清理

## 模块结构

```
tests/
├── test_harness/
│   ├── mod.rs              # 导出所有公共接口
│   ├── environment.rs      # TestEnvironment - 管理服务生命周期
│   ├── kafka.rs            # KafkaProducer - Kafka 生产者客户端
│   ├── clickhouse.rs       # ClickHouseClient - ClickHouse 查询客户端
│   ├── postgres.rs         # PostgresClient - PostgreSQL 客户端
│   ├── redis.rs            # RedisClient - Redis 客户端
│   └── api.rs              # FeedApiClient - Feed API HTTP 客户端
├── core_flow_test.rs
├── known_issues_regression_test.rs
└── performance_benchmark_test.rs
```

## 核心组件

### 1. TestEnvironment (`environment.rs`)

**职责**: 管理测试环境的启动、停止、服务发现

**关键方法**:
```rust
impl TestEnvironment {
    /// 启动所有服务 (PostgreSQL, Kafka, ClickHouse, Redis)
    pub async fn new() -> Self;

    /// 清理所有测试数据,停止服务
    pub async fn cleanup(&self);

    /// 停止 ClickHouse (用于降级测试)
    pub async fn stop_clickhouse(&self);

    /// 启动 ClickHouse (用于恢复测试)
    pub async fn start_clickhouse(&self);

    /// 健康检查,等待所有服务就绪
    async fn wait_for_services(&self) -> Result<(), String>;
}
```

**实现思路**:
```rust
pub struct TestEnvironment {
    pub pg_url: String,
    pub kafka_brokers: Vec<String>,
    pub ch_url: String,
    pub redis_url: String,
    pub api_url: String,
    docker_compose_path: PathBuf,
}

impl TestEnvironment {
    pub async fn new() -> Self {
        // 1. 读取 docker-compose.test.yml
        // 2. 启动所有服务: docker-compose up -d
        // 3. 等待健康检查通过
        // 4. 返回服务 URLs

        let env = Self {
            pg_url: "postgresql://test:test@localhost:5433/nova_test".to_string(),
            kafka_brokers: vec!["localhost:9093".to_string()],
            ch_url: "http://localhost:8124".to_string(),
            redis_url: "redis://localhost:6380".to_string(),
            api_url: "http://localhost:8080".to_string(),
            docker_compose_path: PathBuf::from("docker-compose.test.yml"),
        };

        env.wait_for_services().await.expect("Services failed to start");
        env
    }

    async fn wait_for_services(&self) -> Result<(), String> {
        // 健康检查逻辑
        // - PostgreSQL: SELECT 1
        // - Kafka: list topics
        // - ClickHouse: SELECT 1
        // - Redis: PING
        // 最多重试 30 次,每次 1 秒
    }

    pub async fn cleanup(&self) {
        // 1. 清理测试数据 (TRUNCATE 表)
        // 2. 关闭所有客户端连接
        // 注意: 不 down 容器,保持服务运行以加速后续测试
    }

    pub async fn stop_clickhouse(&self) {
        // docker-compose stop clickhouse
        std::process::Command::new("docker-compose")
            .args(&["-f", "docker-compose.test.yml", "stop", "clickhouse"])
            .output()
            .expect("Failed to stop ClickHouse");
    }

    pub async fn start_clickhouse(&self) {
        // docker-compose start clickhouse
        std::process::Command::new("docker-compose")
            .args(&["-f", "docker-compose.test.yml", "start", "clickhouse"])
            .output()
            .expect("Failed to start ClickHouse");
    }
}
```

---

### 2. KafkaProducer (`kafka.rs`)

**职责**: 发送测试事件到 Kafka

**关键方法**:
```rust
impl KafkaProducer {
    pub async fn new(brokers: &[String]) -> Self;

    /// 发送 JSON 消息到指定 topic
    pub async fn send(&self, topic: &str, payload: serde_json::Value) -> Result<(), String>;
}
```

**实现思路**:
```rust
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::ClientConfig;

pub struct KafkaProducer {
    producer: FutureProducer,
}

impl KafkaProducer {
    pub async fn new(brokers: &[String]) -> Self {
        let producer: FutureProducer = ClientConfig::new()
            .set("bootstrap.servers", brokers.join(","))
            .set("message.timeout.ms", "5000")
            .create()
            .expect("Failed to create Kafka producer");

        Self { producer }
    }

    pub async fn send(&self, topic: &str, payload: serde_json::Value) -> Result<(), String> {
        let json_str = serde_json::to_string(&payload).unwrap();
        let record = FutureRecord::to(topic)
            .payload(&json_str)
            .key("test-key");

        self.producer
            .send(record, Duration::from_secs(5))
            .await
            .map_err(|(err, _)| format!("Kafka send error: {}", err))?;

        Ok(())
    }
}
```

---

### 3. ClickHouseClient (`clickhouse.rs`)

**职责**: 查询和写入 ClickHouse

**关键方法**:
```rust
impl ClickHouseClient {
    pub async fn new(url: &str) -> Self;

    /// 执行查询,返回单个值 (如 COUNT)
    pub async fn query_one<T: FromStr>(&self, sql: &str, params: &[&str]) -> Result<T, String>;

    /// 执行查询,返回单行 JSON
    pub async fn query_one_json(&self, sql: &str, params: &[&str]) -> Result<serde_json::Value, String>;

    /// 批量执行 INSERT 语句
    pub async fn execute_batch(&self, sqls: &[&str]) -> Result<(), String>;
}
```

**实现思路**:
```rust
use clickhouse::Client;

pub struct ClickHouseClient {
    client: Client,
}

impl ClickHouseClient {
    pub async fn new(url: &str) -> Self {
        let client = Client::default().with_url(url);
        Self { client }
    }

    pub async fn query_one<T: FromStr>(&self, sql: &str, params: &[&str]) -> Result<T, String> {
        // 实现参数化查询
        // 使用 clickhouse-rs 库执行 SQL
        // 解析结果为类型 T
    }

    pub async fn execute_batch(&self, sqls: &[&str]) -> Result<(), String> {
        for sql in sqls {
            self.client
                .query(sql)
                .execute()
                .await
                .map_err(|e| format!("ClickHouse execute error: {}", e))?;
        }
        Ok(())
    }
}
```

---

### 4. PostgresClient (`postgres.rs`)

**职责**: 操作 PostgreSQL (用于 CDC 测试)

**关键方法**:
```rust
impl PostgresClient {
    pub async fn new(url: &str) -> Self;

    /// 执行 INSERT/UPDATE/DELETE
    pub async fn execute(&self, sql: &str, params: &[&(dyn ToSql + Sync)]) -> Result<u64, String>;

    /// 执行查询,返回行数
    pub async fn query_count(&self, sql: &str) -> Result<i64, String>;
}
```

**实现思路**:
```rust
use tokio_postgres::{Client, NoTls};

pub struct PostgresClient {
    client: Client,
}

impl PostgresClient {
    pub async fn new(url: &str) -> Self {
        let (client, connection) = tokio_postgres::connect(url, NoTls)
            .await
            .expect("Failed to connect to PostgreSQL");

        tokio::spawn(async move {
            if let Err(e) = connection.await {
                eprintln!("PostgreSQL connection error: {}", e);
            }
        });

        Self { client }
    }

    pub async fn execute(&self, sql: &str, params: &[&(dyn ToSql + Sync)]) -> Result<u64, String> {
        self.client
            .execute(sql, params)
            .await
            .map_err(|e| format!("PostgreSQL execute error: {}", e))
    }
}
```

---

### 5. RedisClient (`redis.rs`)

**职责**: 操作 Redis (用于缓存测试)

**关键方法**:
```rust
impl RedisClient {
    pub async fn new(url: &str) -> Self;

    /// SET key value with TTL
    pub async fn set(&self, key: &str, value: String, ttl_secs: u64) -> Result<(), String>;

    /// GET key
    pub async fn get(&self, key: &str) -> Result<Option<String>, String>;

    /// DELETE key
    pub async fn del(&self, key: &str) -> Result<(), String>;
}
```

**实现思路**:
```rust
use redis::AsyncCommands;

pub struct RedisClient {
    client: redis::Client,
}

impl RedisClient {
    pub async fn new(url: &str) -> Self {
        let client = redis::Client::open(url)
            .expect("Failed to create Redis client");
        Self { client }
    }

    pub async fn set(&self, key: &str, value: String, ttl_secs: u64) -> Result<(), String> {
        let mut conn = self.client.get_async_connection().await
            .map_err(|e| format!("Redis connection error: {}", e))?;

        conn.set_ex(key, value, ttl_secs).await
            .map_err(|e| format!("Redis SET error: {}", e))
    }

    pub async fn get(&self, key: &str) -> Result<Option<String>, String> {
        let mut conn = self.client.get_async_connection().await.unwrap();
        conn.get(key).await
            .map_err(|e| format!("Redis GET error: {}", e))
    }
}
```

---

### 6. FeedApiClient (`api.rs`)

**职责**: 调用 Feed API (HTTP 客户端)

**关键方法**:
```rust
impl FeedApiClient {
    pub fn new(base_url: &str) -> Self;

    /// GET /api/feed/{user_id}?limit=50
    pub async fn get_feed(&self, user_id: &str, limit: usize) -> Result<Vec<FeedPost>, String>;
}

#[derive(Debug, Clone, Deserialize)]
pub struct FeedPost {
    pub post_id: String,
    pub author_id: String,
    pub score: f64,
    pub rank: i32,
}
```

**实现思路**:
```rust
use reqwest::Client;
use serde::Deserialize;

#[derive(Clone)]
pub struct FeedApiClient {
    client: Client,
    base_url: String,
}

impl FeedApiClient {
    pub fn new(base_url: &str) -> Self {
        Self {
            client: Client::new(),
            base_url: base_url.to_string(),
        }
    }

    pub async fn get_feed(&self, user_id: &str, limit: usize) -> Result<Vec<FeedPost>, String> {
        let url = format!("{}/api/feed/{}?limit={}", self.base_url, user_id, limit);

        let response = self.client
            .get(&url)
            .send()
            .await
            .map_err(|e| format!("HTTP request error: {}", e))?;

        if !response.status().is_success() {
            return Err(format!("API error: {}", response.status()));
        }

        response
            .json::<Vec<FeedPost>>()
            .await
            .map_err(|e| format!("JSON parse error: {}", e))
    }
}
```

---

## 依赖清单

在 `Cargo.toml` 中添加测试依赖:

```toml
[dev-dependencies]
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
chrono = { version = "0.4", features = ["serde"] }

# Kafka
rdkafka = { version = "0.34", features = ["tokio"] }

# ClickHouse
clickhouse = "0.11"

# PostgreSQL
tokio-postgres = { version = "0.7", features = ["with-chrono-0_4"] }

# Redis
redis = { version = "0.23", features = ["tokio-comp", "connection-manager"] }

# HTTP Client
reqwest = { version = "0.11", features = ["json"] }
```

## 使用示例

```rust
use test_harness::{TestEnvironment, KafkaProducer, ClickHouseClient};

#[tokio::test]
async fn example_test() {
    // Setup
    let env = TestEnvironment::new().await;
    let kafka = KafkaProducer::new(&env.kafka_brokers).await;
    let ch = ClickHouseClient::new(&env.ch_url).await;

    // Action
    kafka.send("events", json!({"event_id": "test"})).await.unwrap();
    sleep(Duration::from_secs(1)).await;

    // Assert
    let count: u64 = ch.query_one("SELECT count() FROM events", &[]).await.unwrap();
    assert_eq!(count, 1);

    // Cleanup
    env.cleanup().await;
}
```

## 开发优先级

按 Linus 的实用主义,实现顺序:

1. **TestEnvironment** - 最基础,先让服务跑起来
2. **ClickHouseClient** - 核心数据存储,优先验证
3. **FeedApiClient** - 端到端测试需要
4. **KafkaProducer** - 事件发送
5. **RedisClient** - 缓存测试
6. **PostgresClient** - CDC 测试 (相对次要)

## 简化原则

> "如果实现需要超过 3 层缩进,重新设计它"

- ❌ 不要写通用的 "TestFramework",只写够用的工具
- ❌ 不要实现完整的 CRUD,只实现测试需要的方法
- ❌ 不要过度封装,直接暴露底层库的类型

## Linus 会说什么?

> "Talk is cheap. Show me the code."

这个 README 是指南,不是规范。如果实际实现时发现更简单的方案,直接用。

好品味 > 完美设计。
