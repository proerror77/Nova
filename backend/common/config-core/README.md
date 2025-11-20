# Nova Config Core Library

Unified configuration management for all Nova backend microservices.

## Features

- ✅ **Type-safe configuration** with validation
- ✅ **Environment-aware** loading (local, dev, staging, prod)
- ✅ **Secret management** with zero-copy protection
- ✅ **Multi-source loading** (files, env vars, defaults)
- ✅ **Hot reload support** (optional)
- ✅ **Comprehensive coverage** (database, Redis, Kafka, observability, security)

## Installation

Add to your `Cargo.toml`:

```toml
[dependencies]
config-core = { path = "../common/config-core" }
error-types = { path = "../common/error-types" }
```

## Usage

### Basic Service Configuration

```rust
use config_core::{BaseConfig, ServiceConfig, Environment};
use serde::Deserialize;
use error_types::ServiceResult;

#[derive(Debug, Clone, Deserialize)]
pub struct MyServiceConfig {
    #[serde(flatten)]
    pub base: BaseConfig,

    // Service-specific fields
    pub feature_flags: FeatureFlags,
}

impl ServiceConfig for MyServiceConfig {
    fn load() -> ServiceResult<Self> {
        // Load from default path: ./config/config.toml
        let base = BaseConfig::load(Some(Path::new("config/config.toml")))?;

        Ok(MyServiceConfig {
            base,
            feature_flags: FeatureFlags::default(),
        })
    }

    fn base(&self) -> &BaseConfig {
        &self.base
    }
}

// Use the configuration
#[tokio::main]
async fn main() -> ServiceResult<()> {
    let config = MyServiceConfig::load()?;

    println!("Starting {} on port {}",
             config.base.app_name,
             config.base.http.port);

    // Access database config
    if let Some(db) = &config.base.database {
        let db_url = db.connection_url();
        // Connect to database...
    }

    Ok(())
}
```

### Configuration Loading Order

Configuration is loaded in the following order (later sources override earlier):

1. **Built-in defaults** (`config/defaults.toml`)
2. **Base configuration file** (`config/config.toml`)
3. **Environment-specific file** (`config/config.production.toml`)
4. **Environment variables** (`NOVA_*` prefix)

### Environment Variables

Environment variables use the `NOVA_` prefix and underscore separators:

```bash
# Set HTTP port
export NOVA_HTTP_PORT=8080

# Set database host
export NOVA_DATABASE_HOST=db.example.com

# Set JWT public key
export NOVA_SECURITY_JWT_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----..."

# Set log level
export NOVA_OBSERVABILITY_LOGGING_LEVEL=debug
```

### Configuration Files

#### `config/config.toml` - Base configuration

```toml
app_name = "content-service"
app_version = "1.0.0"
environment = "development"

[http]
port = 8081
max_body_size = 10485760 # 10MB

[database]
host = "localhost"
port = 5432
database = "nova_content"
username = "nova"
password = "changeme"
ssl_mode = "require"

[database.pool]
max_connections = 20
min_connections = 5

[redis]
mode = "single"
host = "localhost"
port = 6379
database = 0

[security.jwt]
algorithm = "RS256"
public_key = """
-----BEGIN PUBLIC KEY-----
...
-----END PUBLIC KEY-----
"""
private_key = """
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
"""
```

#### `config/config.production.toml` - Production overrides

```toml
environment = "production"

[http]
host = "0.0.0.0"
port = 443
tls.cert_path = "/etc/certs/server.crt"
tls.key_path = "/etc/certs/server.key"

[database]
host = "prod-db.internal"
ssl_mode = "verify-full"

[database.pool]
max_connections = 50

# Read replicas for load balancing
[[database.read_replicas]]
host = "replica1.internal"
port = 5432
weight = 10

[[database.read_replicas]]
host = "replica2.internal"
port = 5432
weight = 10

[redis]
mode = "cluster"
[[redis.nodes]]
host = "redis-node1.internal"
port = 6379

[[redis.nodes]]
host = "redis-node2.internal"
port = 6379

[observability.tracing]
enabled = true
exporter = { opentelemetry = { endpoint = "http://otel-collector:4317", protocol = "grpc" } }
```

### Hot Reload Support

```rust
use config_core::ConfigLoader;
use std::time::Duration;

#[tokio::main]
async fn main() -> ServiceResult<()> {
    // Create loader with 30-second reload interval
    let loader = ConfigLoader::<MyServiceConfig>::with_reload(
        Duration::from_secs(30)
    ).await?;

    // Get current config
    let config = loader.get().await;

    // Manually reload
    loader.reload().await?;

    Ok(())
}
```

## Configuration Modules

### Database Configuration

```rust
use config_core::DatabaseConfig;

let db_config = DatabaseConfig {
    host: "localhost".to_string(),
    port: 5432,
    database: "nova".to_string(),
    username: "user".to_string(),
    password: SecretString::from("password"),
    ssl_mode: SslMode::Require,
    pool: PoolConfig {
        max_connections: 20,
        min_connections: 5,
        connect_timeout_secs: 5,
        idle_timeout_secs: 300,
        max_lifetime_secs: 1800,
        acquire_timeout_secs: 10,
    },
    query_timeout_secs: 30,
    log_queries: false,
    read_replicas: vec![],
};

// Get connection URL (SecretString protects password)
let url = db_config.connection_url();

// Get read replica URL
if let Some(replica_url) = db_config.replica_url(0) {
    // Use read replica for queries
}
```

### Redis Configuration

```rust
use config_core::{RedisConfig, RedisMode, ConnectionConfig};

// Single instance
let redis_config = RedisConfig {
    mode: RedisMode::Single,
    connection: ConnectionConfig::Single {
        host: "localhost".to_string(),
        port: 6379,
    },
    database: 0,
    password: Some(SecretString::from("redis_password")),
    username: None,
    pool: RedisPoolConfig::default(),
    key_prefix: Some("nova:".to_string()),
    keep_alive: true,
    tls: None,
};

// Redis Cluster
let cluster_config = RedisConfig {
    mode: RedisMode::Cluster,
    connection: ConnectionConfig::Cluster {
        nodes: vec![
            ClusterNode { host: "node1".to_string(), port: 7000 },
            ClusterNode { host: "node2".to_string(), port: 7001 },
        ],
    },
    // ... other fields
};
```

### Kafka Configuration

```rust
use config_core::{KafkaConfig, ProducerConfig, ConsumerConfig};

let kafka_config = KafkaConfig {
    brokers: vec!["localhost:9092".to_string()],
    client_id: "nova-service".to_string(),
    producer: ProducerConfig {
        acks: Acks::All,
        compression: CompressionType::Snappy,
        batch_size: 16384,
        linger_ms: 100,
        max_request_size: 1048576,
        retries: 3,
        enable_idempotence: true,
    },
    consumer: ConsumerConfig {
        group_id: "nova-consumer".to_string(),
        auto_offset_reset: OffsetReset::Latest,
        enable_auto_commit: true,
        auto_commit_interval_ms: 5000,
        session_timeout_ms: 30000,
        max_poll_records: 500,
        fetch_min_bytes: 1,
        fetch_max_wait_ms: 500,
    },
    security: None,
    schema_registry_url: None,
    connection_timeout_secs: 10,
    request_timeout_secs: 30,
};

// Get bootstrap servers
let bootstrap = kafka_config.bootstrap_servers();
```

### Security Configuration

```rust
use config_core::{SecurityConfig, JwtConfig, JwtAlgorithm};

let security_config = SecurityConfig {
    jwt: JwtConfig {
        algorithm: JwtAlgorithm::RS256,
        public_key: SecretString::from(public_key_pem),
        private_key: SecretString::from(private_key_pem),
        secret: None, // Not used with RS256
        expiry_secs: 3600,
        refresh_expiry_secs: 604800,
        issuer: "nova-auth".to_string(),
        audience: "nova-api".to_string(),
        leeway_secs: 60,
    },
    rate_limiting: RateLimitingConfig {
        enabled: true,
        global_limit: 10000,
        per_ip_limit: 100,
        per_user_limit: 1000,
        burst_multiplier: 10,
        window_secs: 60,
        whitelist_ips: vec![],
    },
    // ... other security settings
};

// Validate for production
security_config.validate_for_production()?;
```

### Observability Configuration

```rust
use config_core::{ObservabilityConfig, LoggingConfig, MetricsConfig, TracingConfig};

let observability = ObservabilityConfig {
    logging: LoggingConfig {
        level: LogLevel::Info,
        format: LogFormat::Json,
        output: LogOutput::Stdout,
        enable_colors: false,
        include_location: true,
        include_thread_ids: false,
        include_thread_names: false,
        filters: HashMap::from([
            ("hyper".to_string(), LogLevel::Warn),
            ("tokio".to_string(), LogLevel::Error),
        ]),
        fields: StructuredFields::default(),
    },
    metrics: MetricsConfig {
        enabled: true,
        exporter: MetricsExporter::Prometheus {
            port: 9090,
            path: "/metrics".to_string(),
        },
        export_interval_secs: 10,
        histogram_buckets: vec![0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0],
        runtime_metrics: true,
        labels: HashMap::new(),
    },
    tracing: TracingConfig {
        enabled: true,
        exporter: TracingExporter::OpenTelemetry {
            endpoint: "http://collector:4317".to_string(),
            protocol: OtlpProtocol::Grpc,
        },
        sampling: SamplingConfig {
            strategy: SamplingStrategy::Probabilistic,
            rate: 0.1,
            parent_based: true,
        },
        propagation: PropagationFormat::W3C,
        service_name: Some("my-service".to_string()),
        resource_attributes: HashMap::new(),
    },
    health: HealthConfig::default(),
    profiling: None,
};
```

## Environment Detection

```rust
use config_core::Environment;

let env = Environment::from_str("prod")?;

if env.is_production() {
    // Enable production features
}

if env.is_local() {
    // Enable development features
}
```

## Validation

All configuration is validated on load:

- Range validation for numeric fields
- Required fields enforcement
- Production-specific requirements
- Custom validation logic

```rust
use validator::Validate;

let config = MyServiceConfig::load()?;

// Automatic validation during load
config.validate()?;

// Additional custom validation
if config.base.environment.is_production() {
    // Check production requirements
}
```

## Secret Management

Sensitive values use `SecretString` to prevent accidental exposure:

```rust
use secrecy::{ExposeSecret, SecretString};

let password = SecretString::from("sensitive_password");

// Won't print the actual value
println!("Password: {:?}", password); // Output: Password: SecretString("***")

// Explicitly expose when needed
let actual = password.expose_secret();
```

## Migration Guide

### From Hardcoded Config

Before:
```rust
const DB_HOST: &str = "localhost";
const DB_PORT: u16 = 5432;
```

After:
```rust
let config = BaseConfig::load(None)?;
let db = config.database.as_ref().unwrap();
let host = &db.host;
let port = db.port;
```

### From Multiple Config Files

Before:
```rust
// database.yaml
// redis.conf
// app.properties
```

After:
```toml
# Single config.toml
[database]
host = "localhost"

[redis]
host = "localhost"

[app]
name = "nova-service"
```

## Best Practices

1. **Never commit secrets** - Use environment variables or secret managers
2. **Use environment-specific files** - Keep production config separate
3. **Validate early** - Fail fast on invalid configuration
4. **Log configuration** (without secrets) on startup
5. **Use structured configuration** - Avoid string concatenation
6. **Implement health checks** that verify configuration

## Testing

```rust
#[cfg(test)]
mod tests {
    use tempfile::tempdir;
    use std::fs;

    #[test]
    fn test_config_loading() {
        let dir = tempdir().unwrap();
        let config_path = dir.path().join("config.toml");

        fs::write(&config_path, r#"
            app_name = "test-service"
            environment = "local"

            [http]
            port = 3000
        "#).unwrap();

        let config = BaseConfig::load(Some(&config_path)).unwrap();
        assert_eq!(config.app_name, "test-service");
        assert_eq!(config.http.port, 3000);
    }
}
```

## Performance Considerations

- Configuration is loaded once at startup (minimal overhead)
- Hot reload checks are async and non-blocking
- SecretString has zero runtime overhead
- Validation happens only on load/reload
