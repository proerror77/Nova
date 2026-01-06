use anyhow::{Context, Result};
use once_cell::sync::OnceCell;
use redis::aio::ConnectionManager;
use redis::{Client, ConnectionAddr, ConnectionInfo, IntoConnectionInfo, RedisError};
use std::sync::Arc;
use tokio::sync::{watch, Mutex};
use tokio::task::JoinHandle;
use tokio::time::{sleep, timeout, Duration};
use tracing::{debug, error, info, warn};

/// Shared Redis connection manager guarded by a Tokio mutex.
pub type SharedConnectionManager = Arc<Mutex<ConnectionManager>>;

/// Sentinel configuration.
#[derive(Clone, Debug)]
pub struct SentinelConfig {
    pub endpoints: Vec<String>,
    pub master_name: String,
    pub poll_interval: Duration,
}

impl SentinelConfig {
    pub fn new(endpoints: Vec<String>, master_name: String, poll_interval: Duration) -> Self {
        Self {
            endpoints,
            master_name,
            poll_interval,
        }
    }
}

/// Keepalive configuration to prevent idle connection timeouts.
///
/// Kubernetes and cloud load balancers often have TCP idle timeouts (typically 10-30 minutes).
/// When a connection is idle longer than this, it gets silently dropped, causing "Broken pipe" errors.
/// The keepalive sends periodic PING commands to prevent this.
#[derive(Clone, Debug)]
pub struct KeepaliveConfig {
    /// Interval between PING commands (default: 30 seconds)
    pub interval: Duration,
    /// Whether keepalive is enabled (default: true)
    pub enabled: bool,
}

impl Default for KeepaliveConfig {
    fn default() -> Self {
        Self {
            interval: Duration::from_secs(30),
            enabled: true,
        }
    }
}

impl KeepaliveConfig {
    /// Create keepalive config from environment variables
    ///
    /// - `REDIS_KEEPALIVE_ENABLED`: "true" or "false" (default: true)
    /// - `REDIS_KEEPALIVE_INTERVAL_SECS`: interval in seconds (default: 30)
    pub fn from_env() -> Self {
        let enabled = std::env::var("REDIS_KEEPALIVE_ENABLED")
            .map(|v| v.eq_ignore_ascii_case("true") || v == "1")
            .unwrap_or(true);

        let interval_secs = std::env::var("REDIS_KEEPALIVE_INTERVAL_SECS")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(30)
            .max(5); // Minimum 5 seconds

        Self {
            interval: Duration::from_secs(interval_secs),
            enabled,
        }
    }
}

/// Redis connection pool with optional Sentinel supervisor and keepalive.
pub struct RedisPool {
    manager: SharedConnectionManager,
    _sentinel: Option<SentinelSupervisor>,
    _keepalive: Option<KeepaliveTask>,
}

#[derive(Clone, Copy)]
enum RedisTlsMode {
    None,
    Secure,
    Insecure,
}

#[derive(Clone)]
struct NodeConnectionSettings {
    redis: redis::RedisConnectionInfo,
    tls: RedisTlsMode,
}

impl RedisPool {
    /// Connect to Redis with default keepalive settings (enabled, 30s interval)
    pub async fn connect(redis_url: &str, sentinel: Option<SentinelConfig>) -> Result<Self> {
        Self::connect_with_keepalive(redis_url, sentinel, KeepaliveConfig::from_env()).await
    }

    /// Connect to Redis with custom keepalive configuration
    pub async fn connect_with_keepalive(
        redis_url: &str,
        sentinel: Option<SentinelConfig>,
        keepalive: KeepaliveConfig,
    ) -> Result<Self> {
        let base_info: ConnectionInfo = redis_url
            .into_connection_info()
            .context("failed to parse REDIS_URL connection string")?;

        let redis_info = base_info.redis.clone();
        let tls_mode = match &base_info.addr {
            ConnectionAddr::TcpTls { insecure, .. } => {
                if *insecure {
                    RedisTlsMode::Insecure
                } else {
                    RedisTlsMode::Secure
                }
            }
            _ => RedisTlsMode::None,
        };

        if let Some(sentinel_cfg) = sentinel {
            let node_settings = NodeConnectionSettings {
                redis: redis_info.clone(),
                tls: tls_mode,
            };

            let (initial_client, addr_label) = resolve_master(&sentinel_cfg, &node_settings)
                .await
                .context("failed to resolve Redis master from sentinel during startup")?;

            info!("Redis Sentinel master resolved at {}", addr_label);

            let connection_manager = ConnectionManager::new(initial_client)
                .await
                .context("failed to initialize Redis connection manager")?;
            let manager = Arc::new(Mutex::new(connection_manager));

            let supervisor =
                SentinelSupervisor::spawn(manager.clone(), sentinel_cfg, node_settings, addr_label)
                    .await?;

            // Spawn keepalive task
            let keepalive_task = if keepalive.enabled {
                info!(
                    "Redis keepalive enabled with {}s interval",
                    keepalive.interval.as_secs()
                );
                Some(KeepaliveTask::spawn(manager.clone(), keepalive))
            } else {
                None
            };

            Ok(Self {
                manager,
                _sentinel: Some(supervisor),
                _keepalive: keepalive_task,
            })
        } else {
            let base_client =
                Client::open(base_info.clone()).context("failed to construct Redis client")?;
            let connection_manager = ConnectionManager::new(base_client)
                .await
                .context("failed to initialize Redis connection manager")?;
            let manager = Arc::new(Mutex::new(connection_manager));

            // Spawn keepalive task
            let keepalive_task = if keepalive.enabled {
                info!(
                    "Redis keepalive enabled with {}s interval",
                    keepalive.interval.as_secs()
                );
                Some(KeepaliveTask::spawn(manager.clone(), keepalive))
            } else {
                None
            };

            Ok(Self {
                manager,
                _sentinel: None,
                _keepalive: keepalive_task,
            })
        }
    }

    pub fn manager(&self) -> SharedConnectionManager {
        self.manager.clone()
    }
}

struct SentinelSupervisor {
    shutdown_tx: watch::Sender<()>,
    handle: JoinHandle<()>,
}

impl SentinelSupervisor {
    async fn spawn(
        manager: SharedConnectionManager,
        sentinel_config: SentinelConfig,
        node_settings: NodeConnectionSettings,
        initial_addr: String,
    ) -> Result<Self> {
        let (shutdown_tx, shutdown_rx) = watch::channel(());

        let handle = tokio::spawn(async move {
            sentinel_monitor(
                manager,
                sentinel_config,
                node_settings,
                initial_addr,
                shutdown_rx,
            )
            .await;
        });

        Ok(Self {
            shutdown_tx,
            handle,
        })
    }
}

impl Drop for SentinelSupervisor {
    fn drop(&mut self) {
        let _ = self.shutdown_tx.send(());
        self.handle.abort();
    }
}

/// Background task that sends periodic PING commands to keep Redis connections alive.
struct KeepaliveTask {
    shutdown_tx: watch::Sender<()>,
    handle: JoinHandle<()>,
}

impl KeepaliveTask {
    fn spawn(manager: SharedConnectionManager, config: KeepaliveConfig) -> Self {
        let (shutdown_tx, shutdown_rx) = watch::channel(());

        let handle = tokio::spawn(async move {
            keepalive_loop(manager, config.interval, shutdown_rx).await;
        });

        Self {
            shutdown_tx,
            handle,
        }
    }
}

impl Drop for KeepaliveTask {
    fn drop(&mut self) {
        let _ = self.shutdown_tx.send(());
        self.handle.abort();
    }
}

/// Keepalive loop that sends periodic PING commands
async fn keepalive_loop(
    manager: SharedConnectionManager,
    interval: Duration,
    mut shutdown: watch::Receiver<()>,
) {
    let mut consecutive_failures = 0u32;
    const MAX_FAILURES_BEFORE_WARN: u32 = 3;

    loop {
        tokio::select! {
            _ = shutdown.changed() => {
                debug!("Redis keepalive task shutting down");
                break;
            }
            _ = sleep(interval) => {
                // Send PING to keep connection alive
                let result: Result<String, RedisError> = {
                    let mut conn = manager.lock().await;
                    redis::cmd("PING").query_async(&mut *conn).await
                };

                match result {
                    Ok(response) => {
                        if response == "PONG" {
                            debug!("Redis keepalive PING successful");
                            consecutive_failures = 0;
                        } else {
                            warn!("Redis keepalive received unexpected response: {}", response);
                        }
                    }
                    Err(err) => {
                        consecutive_failures += 1;
                        if consecutive_failures >= MAX_FAILURES_BEFORE_WARN {
                            warn!(
                                "Redis keepalive PING failed ({} consecutive failures): {}",
                                consecutive_failures, err
                            );
                        } else {
                            debug!("Redis keepalive PING failed (will retry): {}", err);
                        }
                        // ConnectionManager should auto-reconnect on next command
                    }
                }
            }
        }
    }
}

async fn sentinel_monitor(
    manager: SharedConnectionManager,
    sentinel_config: SentinelConfig,
    node_settings: NodeConnectionSettings,
    mut current_addr: String,
    mut shutdown: watch::Receiver<()>,
) {
    loop {
        tokio::select! {
            _ = shutdown.changed() => {
                info!("Redis Sentinel supervisor shutting down");
                break;
            }
            _ = sleep(sentinel_config.poll_interval) => {
                match resolve_master(&sentinel_config, &node_settings).await {
                    Ok((client, addr_label)) => {
                        if addr_label != current_addr {
                            match ConnectionManager::new(client).await {
                                Ok(new_manager) => {
                                    {
                                        let mut guard = manager.lock().await;
                                        *guard = new_manager;
                                    }
                                    info!("Redis Sentinel switched master to {}", addr_label);
                                    current_addr = addr_label;
                                }
                                Err(err) => {
                                    error!("Failed to rebuild Redis connection manager after sentinel update: {}", err);
                                }
                            }
                        }
                    }
                    Err(err) => {
                        warn!("Redis Sentinel master lookup failed: {}", err);
                    }
                }
            }
        }
    }
}

async fn resolve_master(
    config: &SentinelConfig,
    node_settings: &NodeConnectionSettings,
) -> Result<(Client, String), RedisError> {
    let mut last_err: Option<RedisError> = None;

    for endpoint in &config.endpoints {
        match Client::open(endpoint.as_str()) {
            Ok(sentinel_client) => match sentinel_client.get_multiplexed_async_connection().await {
                Ok(mut conn) => {
                    let response: Vec<String> = redis::cmd("SENTINEL")
                        .arg("GET-MASTER-ADDR-BY-NAME")
                        .arg(&config.master_name)
                        .query_async(&mut conn)
                        .await?;

                    if response.len() < 2 {
                        continue;
                    }

                    let host = response[0].clone();
                    let port = match response[1].parse::<u16>() {
                        Ok(p) => p,
                        Err(_) => continue,
                    };

                    let addr = match node_settings.tls {
                        RedisTlsMode::Secure => ConnectionAddr::TcpTls {
                            host: host.clone(),
                            port,
                            insecure: false,
                            tls_params: None,
                        },
                        RedisTlsMode::Insecure => ConnectionAddr::TcpTls {
                            host: host.clone(),
                            port,
                            insecure: true,
                            tls_params: None,
                        },
                        RedisTlsMode::None => ConnectionAddr::Tcp(host.clone(), port),
                    };

                    let connection_info = ConnectionInfo {
                        addr,
                        redis: node_settings.redis.clone(),
                    };

                    match Client::open(connection_info) {
                        Ok(client) => {
                            return Ok((client, format!("{}:{}", host, port)));
                        }
                        Err(err) => {
                            last_err = Some(err);
                        }
                    }
                }
                Err(err) => {
                    last_err = Some(err);
                }
            },
            Err(err) => {
                last_err = Some(err);
            }
        }
    }

    Err(last_err.unwrap_or_else(|| {
        RedisError::from((
            redis::ErrorKind::IoError,
            "unable to resolve redis master via sentinel",
        ))
    }))
}

/// Build sentinel configuration from comma separated endpoints.
pub fn parse_sentinel_endpoints(raw: &str) -> Vec<String> {
    raw.split(',')
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .map(|s| {
            if s.starts_with("redis://") || s.starts_with("rediss://") {
                s.to_string()
            } else {
                format!("redis://{}", s)
            }
        })
        .collect()
}

// Redis command timeout configuration
const DEFAULT_REDIS_COMMAND_TIMEOUT_MS: u64 = 3_000; // 3 seconds
const MIN_REDIS_COMMAND_TIMEOUT_MS: u64 = 500; // 500ms minimum

/// Get Redis command timeout from environment or default
fn redis_command_timeout() -> Duration {
    static TIMEOUT: OnceCell<Duration> = OnceCell::new();
    *TIMEOUT.get_or_init(|| {
        let ms = std::env::var("REDIS_COMMAND_TIMEOUT_MS")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(DEFAULT_REDIS_COMMAND_TIMEOUT_MS)
            .max(MIN_REDIS_COMMAND_TIMEOUT_MS);

        info!("Redis command timeout set to {}ms", ms);
        Duration::from_millis(ms)
    })
}

/// Wrap Redis command with timeout protection
///
/// **Usage**:
/// ```ignore
/// use redis_utils::with_timeout;
///
/// let result = with_timeout(async {
///     redis::cmd("GET")
///         .arg("key")
///         .query_async(&mut conn)
///         .await
/// }).await?;
/// ```
pub async fn with_timeout<F, T>(future: F) -> Result<T, RedisError>
where
    F: std::future::Future<Output = Result<T, RedisError>>,
{
    match timeout(redis_command_timeout(), future).await {
        Ok(res) => res,
        Err(_) => {
            error!(
                "Redis command timed out after {:?}",
                redis_command_timeout()
            );
            Err(RedisError::from((
                redis::ErrorKind::IoError,
                "redis command timed out",
            )))
        }
    }
}
