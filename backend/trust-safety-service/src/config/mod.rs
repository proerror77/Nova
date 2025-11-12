use serde::Deserialize;
use std::env;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    // Server configuration
    pub grpc_port: u16,
    pub health_port: u16,

    // Database configuration
    pub database_url: String,
    pub db_max_connections: u32,

    // Model paths
    pub nsfw_model_path: String,
    pub sensitive_words_path: String,

    // Moderation thresholds
    pub nsfw_threshold: f32,
    pub toxicity_threshold: f32,
    pub spam_threshold: f32,
    pub overall_threshold: f32,

    // Service configuration
    pub service_name: String,
    pub environment: String,
}

impl Config {
    pub fn from_env() -> Result<Self, envy::Error> {
        dotenv::dotenv().ok();

        Ok(Self {
            grpc_port: env::var("GRPC_PORT")
                .unwrap_or_else(|_| "50056".to_string())
                .parse()
                .unwrap_or(50056),
            health_port: env::var("HEALTH_PORT")
                .unwrap_or_else(|_| "8086".to_string())
                .parse()
                .unwrap_or(8086),
            database_url: env::var("DATABASE_URL").expect("DATABASE_URL must be set"),
            db_max_connections: env::var("DB_MAX_CONNECTIONS")
                .unwrap_or_else(|_| "50".to_string())
                .parse()
                .unwrap_or(50),
            nsfw_model_path: env::var("NSFW_MODEL_PATH")
                .unwrap_or_else(|_| "models/resnet50_nsfw.onnx".to_string()),
            sensitive_words_path: env::var("SENSITIVE_WORDS_PATH")
                .unwrap_or_else(|_| "data/sensitive_words.txt".to_string()),
            nsfw_threshold: env::var("NSFW_THRESHOLD")
                .unwrap_or_else(|_| "0.7".to_string())
                .parse()
                .unwrap_or(0.7),
            toxicity_threshold: env::var("TOXICITY_THRESHOLD")
                .unwrap_or_else(|_| "0.8".to_string())
                .parse()
                .unwrap_or(0.8),
            spam_threshold: env::var("SPAM_THRESHOLD")
                .unwrap_or_else(|_| "0.6".to_string())
                .parse()
                .unwrap_or(0.6),
            overall_threshold: env::var("OVERALL_THRESHOLD")
                .unwrap_or_else(|_| "0.5".to_string())
                .parse()
                .unwrap_or(0.5),
            service_name: env::var("SERVICE_NAME")
                .unwrap_or_else(|_| "trust-safety-service".to_string()),
            environment: env::var("ENVIRONMENT").unwrap_or_else(|_| "development".to_string()),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        env::set_var("DATABASE_URL", "postgres://test");
        let config = Config::from_env().unwrap();
        assert_eq!(config.grpc_port, 50056);
        assert_eq!(config.overall_threshold, 0.5);
    }
}
