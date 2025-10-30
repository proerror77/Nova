use anyhow::{Context, Result};
use redis::aio::ConnectionManager;
use redis::{Client, ConnectionAddr, ConnectionInfo, IntoConnectionInfo, RedisError};
use std::sync::Arc;
use tokio::sync::{watch, Mutex};
use tokio::task::JoinHandle;
use tokio::time::{sleep, Duration};
use tracing::{error, info, warn};

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

/// Redis connection pool with optional Sentinel supervisor.
pub struct RedisPool {
    manager: SharedConnectionManager,
    _sentinel: Option<SentinelSupervisor>,
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
    pub async fn connect(redis_url: &str, sentinel: Option<SentinelConfig>) -> Result<Self> {
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

            let (initial_client, addr_label) =
                resolve_master(&sentinel_cfg, &node_settings).await.context(
                    "failed to resolve Redis master from sentinel during startup",
                )?;

            info!("Redis Sentinel master resolved at {}", addr_label);

            let connection_manager = ConnectionManager::new(initial_client)
                .await
                .context("failed to initialize Redis connection manager")?;
            let manager = Arc::new(Mutex::new(connection_manager));

            let supervisor = SentinelSupervisor::spawn(
                manager.clone(),
                sentinel_cfg,
                node_settings,
                addr_label,
            )
            .await?;

            Ok(Self {
                manager,
                _sentinel: Some(supervisor),
            })
        } else {
            let base_client =
                Client::open(base_info.clone()).context("failed to construct Redis client")?;
            let connection_manager = ConnectionManager::new(base_client)
                .await
                .context("failed to initialize Redis connection manager")?;
            Ok(Self {
                manager: Arc::new(Mutex::new(connection_manager)),
                _sentinel: None,
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
