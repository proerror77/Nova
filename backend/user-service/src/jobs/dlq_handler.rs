//! Dead Letter Queue (DLQ) Handler
//!
//! 处理失败的 job 执行,记录到 Kafka DLQ topic
//!
//! # 功能
//! - 捕获 job 执行失败的详细信息
//! - 发送到 Kafka topic: `jobs-dlq`
//! - 提供重试机制和失败统计

use anyhow::{Context, Result};
use chrono::{DateTime, Utc};
use rdkafka::producer::{FutureProducer, FutureRecord};
use rdkafka::ClientConfig;
use serde::{Deserialize, Serialize};
use tracing::{debug, error, warn};
use uuid::Uuid;

/// DLQ 消息格式
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DlqMessage {
    /// 失败的 job 名称
    pub job_name: String,
    /// 错误信息
    pub error: String,
    /// 失败时间戳
    pub timestamp: DateTime<Utc>,
    /// 重试次数
    pub retry_count: u32,
    /// Correlation ID
    pub correlation_id: String,
    /// 额外的上下文信息
    #[serde(skip_serializing_if = "Option::is_none")]
    pub context: Option<serde_json::Value>,
}

impl DlqMessage {
    pub fn new(job_name: String, error: String, correlation_id: String) -> Self {
        Self {
            job_name,
            error,
            timestamp: Utc::now(),
            retry_count: 0,
            correlation_id,
            context: None,
        }
    }

    pub fn with_retry_count(mut self, count: u32) -> Self {
        self.retry_count = count;
        self
    }

    pub fn with_context(mut self, context: serde_json::Value) -> Self {
        self.context = Some(context);
        self
    }
}

/// DLQ Handler 配置
#[derive(Debug, Clone)]
pub struct DlqConfig {
    /// Kafka brokers
    pub kafka_brokers: String,
    /// DLQ topic 名称
    pub topic: String,
    /// 消息发送超时(毫秒)
    pub timeout_ms: i64,
}

impl Default for DlqConfig {
    fn default() -> Self {
        Self {
            kafka_brokers: "localhost:9092".to_string(),
            topic: "jobs-dlq".to_string(),
            timeout_ms: 5000,
        }
    }
}

/// DLQ Handler
pub struct DlqHandler {
    config: DlqConfig,
    producer: FutureProducer,
}

impl DlqHandler {
    /// 创建新的 DLQ Handler
    pub fn new(config: DlqConfig) -> Result<Self> {
        let producer: FutureProducer = ClientConfig::new()
            .set("bootstrap.servers", &config.kafka_brokers)
            .set("message.timeout.ms", config.timeout_ms.to_string())
            .set("queue.buffering.max.messages", "10000")
            .set("queue.buffering.max.kbytes", "1048576")
            .set("batch.num.messages", "1000")
            .create()
            .context("Failed to create Kafka producer for DLQ")?;

        Ok(Self { config, producer })
    }

    /// 将失败的 job 发送到 DLQ
    pub async fn send(&self, message: DlqMessage) -> Result<()> {
        let payload = serde_json::to_string(&message).context("Failed to serialize DLQ message")?;

        let key = format!("{}-{}", message.job_name, message.correlation_id);

        debug!(
            job_name = %message.job_name,
            correlation_id = %message.correlation_id,
            retry_count = message.retry_count,
            "Sending job failure to DLQ"
        );

        let record = FutureRecord::to(&self.config.topic)
            .key(&key)
            .payload(&payload);

        match self
            .producer
            .send(
                record,
                std::time::Duration::from_millis(self.config.timeout_ms as u64),
            )
            .await
        {
            Ok((partition, offset)) => {
                debug!(
                    topic = %self.config.topic,
                    partition = partition,
                    offset = offset,
                    job_name = %message.job_name,
                    "Successfully sent job failure to DLQ"
                );
                Ok(())
            }
            Err((e, _)) => {
                error!(
                    error = %e,
                    job_name = %message.job_name,
                    "Failed to send job failure to DLQ (Kafka error)"
                );
                Err(anyhow::anyhow!("Kafka send error: {}", e))
            }
        }
    }

    /// 批量发送失败消息
    pub async fn send_batch(&self, messages: Vec<DlqMessage>) -> Result<(usize, usize)> {
        if messages.is_empty() {
            return Ok((0, 0));
        }

        let mut success_count = 0;
        let mut failure_count = 0;

        for message in messages {
            match self.send(message).await {
                Ok(()) => success_count += 1,
                Err(e) => {
                    warn!(error = %e, "Failed to send message to DLQ");
                    failure_count += 1;
                }
            }
        }

        Ok((success_count, failure_count))
    }
}

/// 辅助函数: 从 job 错误创建 DLQ 消息
pub fn create_dlq_message_from_error(
    job_name: &str,
    error: &anyhow::Error,
    correlation_id: &str,
    retry_count: u32,
) -> DlqMessage {
    DlqMessage::new(
        job_name.to_string(),
        format!("{:#}", error), // 使用 alternate format 获取完整错误链
        correlation_id.to_string(),
    )
    .with_retry_count(retry_count)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dlq_message_creation() {
        let msg = DlqMessage::new(
            "test_job".to_string(),
            "test error".to_string(),
            Uuid::new_v4().to_string(),
        );

        assert_eq!(msg.job_name, "test_job");
        assert_eq!(msg.error, "test error");
        assert_eq!(msg.retry_count, 0);
        assert!(msg.context.is_none());
    }

    #[test]
    fn test_dlq_message_with_retry() {
        let msg = DlqMessage::new(
            "test_job".to_string(),
            "test error".to_string(),
            Uuid::new_v4().to_string(),
        )
        .with_retry_count(3);

        assert_eq!(msg.retry_count, 3);
    }

    #[test]
    fn test_dlq_message_serialization() {
        let msg = DlqMessage::new(
            "test_job".to_string(),
            "test error".to_string(),
            Uuid::new_v4().to_string(),
        )
        .with_context(serde_json::json!({"extra": "data"}));

        let json = serde_json::to_string(&msg).unwrap();
        assert!(json.contains("test_job"));
        assert!(json.contains("test error"));
        assert!(json.contains("extra"));
    }

    #[test]
    fn test_default_config() {
        let config = DlqConfig::default();
        assert_eq!(config.kafka_brokers, "localhost:9092");
        assert_eq!(config.topic, "jobs-dlq");
        assert_eq!(config.timeout_ms, 5000);
    }

    #[test]
    fn test_create_dlq_message_from_error() {
        let err = anyhow::anyhow!("test error");
        let msg = create_dlq_message_from_error("my_job", &err, "corr-123", 5);

        assert_eq!(msg.job_name, "my_job");
        assert!(msg.error.contains("test error"));
        assert_eq!(msg.correlation_id, "corr-123");
        assert_eq!(msg.retry_count, 5);
    }
}
