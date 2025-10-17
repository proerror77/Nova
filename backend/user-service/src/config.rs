use serde::Deserialize;
use std::env;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub app: AppConfig,
    pub database: DatabaseConfig,
    pub redis: RedisConfig,
    pub jwt: JwtConfig,
    pub email: EmailConfig,
    pub rate_limit: RateLimitConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct AppConfig {
    #[serde(default = "default_app_env")]
    pub env: String,

    #[serde(default = "default_app_host")]
    pub host: String,

    #[serde(default = "default_app_port")]
    pub port: u16,
}

#[derive(Debug, Clone, Deserialize)]
pub struct DatabaseConfig {
    pub url: String,

    #[serde(default = "default_db_max_connections")]
    pub max_connections: u32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RedisConfig {
    pub url: String,

    #[serde(default = "default_redis_pool_size")]
    pub pool_size: u32,
}

#[derive(Debug, Clone, Deserialize)]
pub struct JwtConfig {
    pub secret: String,

    #[serde(default = "default_jwt_access_ttl")]
    pub access_token_ttl: i64,

    #[serde(default = "default_jwt_refresh_ttl")]
    pub refresh_token_ttl: i64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EmailConfig {
    pub smtp_host: String,

    #[serde(default = "default_smtp_port")]
    pub smtp_port: u16,

    #[serde(default)]
    pub smtp_username: String,

    #[serde(default)]
    pub smtp_password: String,

    pub smtp_from: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct RateLimitConfig {
    #[serde(default = "default_rate_limit_max_requests")]
    pub max_requests: u32,

    #[serde(default = "default_rate_limit_window_secs")]
    pub window_secs: u64,
}

// Default value functions
fn default_app_env() -> String {
    "development".to_string()
}

fn default_app_host() -> String {
    "0.0.0.0".to_string()
}

fn default_app_port() -> u16 {
    8080
}

fn default_db_max_connections() -> u32 {
    20
}

fn default_redis_pool_size() -> u32 {
    10
}

fn default_jwt_access_ttl() -> i64 {
    900 // 15 minutes
}

fn default_jwt_refresh_ttl() -> i64 {
    604800 // 7 days
}

fn default_smtp_port() -> u16 {
    587
}

fn default_rate_limit_max_requests() -> u32 {
    100
}

fn default_rate_limit_window_secs() -> u64 {
    60
}

impl Config {
    pub fn from_env() -> Result<Self, envy::Error> {
        dotenv::dotenv().ok();

        let app = AppConfig {
            env: env::var("APP_ENV").unwrap_or_else(|_| default_app_env()),
            host: env::var("APP_HOST").unwrap_or_else(|_| default_app_host()),
            port: env::var("APP_PORT")
                .unwrap_or_else(|_| default_app_port().to_string())
                .parse()
                .unwrap_or(default_app_port()),
        };

        let database = DatabaseConfig {
            url: env::var("DATABASE_URL")
                .expect("DATABASE_URL must be set"),
            max_connections: env::var("DATABASE_MAX_CONNECTIONS")
                .unwrap_or_else(|_| default_db_max_connections().to_string())
                .parse()
                .unwrap_or(default_db_max_connections()),
        };

        let redis = RedisConfig {
            url: env::var("REDIS_URL")
                .expect("REDIS_URL must be set"),
            pool_size: env::var("REDIS_POOL_SIZE")
                .unwrap_or_else(|_| default_redis_pool_size().to_string())
                .parse()
                .unwrap_or(default_redis_pool_size()),
        };

        let jwt = JwtConfig {
            secret: env::var("JWT_SECRET")
                .expect("JWT_SECRET must be set"),
            access_token_ttl: env::var("JWT_ACCESS_TOKEN_TTL")
                .unwrap_or_else(|_| default_jwt_access_ttl().to_string())
                .parse()
                .unwrap_or(default_jwt_access_ttl()),
            refresh_token_ttl: env::var("JWT_REFRESH_TOKEN_TTL")
                .unwrap_or_else(|_| default_jwt_refresh_ttl().to_string())
                .parse()
                .unwrap_or(default_jwt_refresh_ttl()),
        };

        let email = EmailConfig {
            smtp_host: env::var("SMTP_HOST")
                .unwrap_or_else(|_| "localhost".to_string()),
            smtp_port: env::var("SMTP_PORT")
                .unwrap_or_else(|_| default_smtp_port().to_string())
                .parse()
                .unwrap_or(default_smtp_port()),
            smtp_username: env::var("SMTP_USERNAME").unwrap_or_default(),
            smtp_password: env::var("SMTP_PASSWORD").unwrap_or_default(),
            smtp_from: env::var("SMTP_FROM")
                .unwrap_or_else(|_| "noreply@nova.dev".to_string()),
        };

        let rate_limit = RateLimitConfig {
            max_requests: env::var("RATE_LIMIT_MAX_REQUESTS")
                .unwrap_or_else(|_| default_rate_limit_max_requests().to_string())
                .parse()
                .unwrap_or(default_rate_limit_max_requests()),
            window_secs: env::var("RATE_LIMIT_WINDOW_SECS")
                .unwrap_or_else(|_| default_rate_limit_window_secs().to_string())
                .parse()
                .unwrap_or(default_rate_limit_window_secs()),
        };

        Ok(Config {
            app,
            database,
            redis,
            jwt,
            email,
            rate_limit,
        })
    }

    pub fn is_production(&self) -> bool {
        self.app.env == "production"
    }

    pub fn is_development(&self) -> bool {
        self.app.env == "development"
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_values() {
        assert_eq!(default_app_env(), "development");
        assert_eq!(default_app_host(), "0.0.0.0");
        assert_eq!(default_app_port(), 8080);
        assert_eq!(default_db_max_connections(), 20);
        assert_eq!(default_redis_pool_size(), 10);
        assert_eq!(default_jwt_access_ttl(), 900);
        assert_eq!(default_jwt_refresh_ttl(), 604800);
    }
}
