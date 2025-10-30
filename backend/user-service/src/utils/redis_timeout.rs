use once_cell::sync::OnceCell;
use redis::RedisError;
use std::time::Duration;
use tokio::time::timeout;

const DEFAULT_REDIS_COMMAND_TIMEOUT_MS: u64 = 3_000;

fn redis_command_timeout() -> Duration {
    static TIMEOUT: OnceCell<Duration> = OnceCell::new();
    *TIMEOUT.get_or_init(|| {
        let ms = std::env::var("REDIS_COMMAND_TIMEOUT_MS")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(DEFAULT_REDIS_COMMAND_TIMEOUT_MS)
            .max(500);
        Duration::from_millis(ms)
    })
}

pub async fn run_with_timeout<F, T>(future: F) -> Result<T, RedisError>
where
    F: std::future::Future<Output = Result<T, RedisError>>,
{
    match timeout(redis_command_timeout(), future).await {
        Ok(res) => res,
        Err(_) => Err(RedisError::from((
            redis::ErrorKind::IoError,
            "redis command timed out",
        ))),
    }
}
