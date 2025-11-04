use redis::aio::ConnectionManager;
use redis::AsyncCommands;

/// Rate limiting configuration
#[derive(Clone)]
pub struct RateLimitConfig {
    /// Maximum number of requests per window
    pub max_requests: u32,
    /// Time window in seconds (default: 15 minutes = 900 seconds)
    pub window_seconds: u64,
}

impl Default for RateLimitConfig {
    fn default() -> Self {
        Self {
            max_requests: 5,
            window_seconds: 900, // 15 minutes
        }
    }
}

/// Rate limit check result with observability data
#[derive(Debug, Clone)]
pub struct RateLimitResult {
    /// Current request count
    pub count: u32,
    /// Time-to-live remaining on the key in seconds (0 if key doesn't exist)
    pub ttl_remaining: i64,
    /// Whether this client is rate limited
    pub is_limited: bool,
}

/// Rate limiter utility for checking if a request should be rate limited
pub struct RateLimiter {
    redis: ConnectionManager,
    config: RateLimitConfig,
}

impl RateLimiter {
    pub fn new(redis: ConnectionManager, config: RateLimitConfig) -> Self {
        Self { redis, config }
    }

    /// Check if client has exceeded rate limit and return observability data
    /// Returns RateLimitResult with count, TTL, and is_limited flag
    pub async fn check_rate_limit(
        &self,
        client_id: &str,
    ) -> Result<RateLimitResult, Box<dyn std::error::Error>> {
        let rate_limit_key = format!("rate_limit:{}", client_id);
        let mut conn = self.redis.clone();

        // Atomic INCR + set TTL once, return both count and TTL
        // Lua script: increment counter, set TTL on first increment, return both values
        const LUA: &str = r#"
            local current = redis.call('INCR', KEYS[1])
            if current == 1 then
                redis.call('EXPIRE', KEYS[1], ARGV[1])
            end
            local ttl = redis.call('TTL', KEYS[1])
            return {current, ttl}
        "#;

        let result: (i64, i64) = redis::cmd("EVAL")
            .arg(LUA)
            .arg(1)
            .arg(&rate_limit_key)
            .arg(self.config.window_seconds as i64)
            .query_async(&mut conn)
            .await?;

        let count = result.0 as u32;
        let ttl = result.1;
        let is_limited = count > self.config.max_requests;

        Ok(RateLimitResult {
            count,
            ttl_remaining: ttl,
            is_limited,
        })
    }

    /// Check if client has exceeded rate limit (backward compatible)
    /// Returns true if rate limit is exceeded, false otherwise
    pub async fn is_rate_limited(
        &self,
        client_id: &str,
    ) -> Result<bool, Box<dyn std::error::Error>> {
        let result = self.check_rate_limit(client_id).await?;
        Ok(result.is_limited)
    }

    /// Get current request count for a client
    pub async fn get_request_count(
        &self,
        client_id: &str,
    ) -> Result<u32, Box<dyn std::error::Error>> {
        let rate_limit_key = format!("rate_limit:{}", client_id);
        let mut conn = self.redis.clone();
        let count: u32 = conn.get(&rate_limit_key).await.unwrap_or(0);
        Ok(count)
    }

    /// Reset rate limit for a client
    pub async fn reset_rate_limit(
        &self,
        client_id: &str,
    ) -> Result<(), Box<dyn std::error::Error>> {
        let rate_limit_key = format!("rate_limit:{}", client_id);
        let mut conn = self.redis.clone();
        let _: () = conn
            .del(&rate_limit_key)
            .await
            .map_err(|e| Box::new(e) as Box<dyn std::error::Error>)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rate_limit_config_defaults() {
        let config = RateLimitConfig::default();
        assert_eq!(config.max_requests, 5);
        assert_eq!(config.window_seconds, 900);
    }

    #[test]
    fn test_rate_limit_config_custom() {
        let config = RateLimitConfig {
            max_requests: 10,
            window_seconds: 600,
        };
        assert_eq!(config.max_requests, 10);
        assert_eq!(config.window_seconds, 600);
    }

    #[test]
    fn test_rate_limit_key_format() {
        let ip = "192.168.1.1";
        let key = format!("rate_limit:{}", ip);
        assert_eq!(key, "rate_limit:192.168.1.1");
    }

    #[test]
    fn test_rate_limit_config_is_clone() {
        let config1 = RateLimitConfig::default();
        let config2 = config1.clone();
        assert_eq!(config1.max_requests, config2.max_requests);
        assert_eq!(config1.window_seconds, config2.window_seconds);
    }
}
