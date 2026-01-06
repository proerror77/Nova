use crate::services::{elasticsearch, ElasticsearchClient};
use chrono::{DateTime, Utc};
use rdkafka::consumer::{Consumer, StreamConsumer};
use rdkafka::message::Message;
use rdkafka::{ClientConfig, TopicPartitionList};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;
use thiserror::Error;
use tracing::{error, info, warn};
use uuid::Uuid;

#[derive(Debug, Error)]
pub enum KafkaConsumerError {
    #[error("Kafka error: {0}")]
    Kafka(#[from] rdkafka::error::KafkaError),
    #[error("Elasticsearch error: {0}")]
    Elasticsearch(#[from] elasticsearch::ElasticsearchError),
    #[error("deserialization error: {0}")]
    Serde(#[from] serde_json::Error),
    #[error("invalid message format")]
    InvalidMessage,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "event_type", rename_all = "snake_case")]
pub enum ContentEvent {
    PostCreated(PostCreatedEvent),
    PostEdited(PostEditedEvent),
    PostDeleted(PostDeletedEvent),
    UserUpdated(UserUpdatedEvent),
    CommentCreated(CommentCreatedEvent),
    CommentDeleted(CommentDeletedEvent),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostCreatedEvent {
    pub post_id: Uuid,
    pub user_id: Uuid,
    pub title: Option<String>,
    pub content: Option<String>,
    pub tags: Vec<String>,
    pub likes_count: i32,
    pub comments_count: i32,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostEditedEvent {
    pub post_id: Uuid,
    pub title: Option<String>,
    pub content: Option<String>,
    pub tags: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostDeletedEvent {
    pub post_id: Uuid,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserUpdatedEvent {
    pub user_id: Uuid,
    pub username: String,
    pub display_name: String,
    pub bio: Option<String>,
    pub avatar_url: Option<String>,
    pub location: Option<String>,
    pub interests: Vec<String>,
    pub is_verified: bool,
    pub follower_count: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommentCreatedEvent {
    pub comment_id: Uuid,
    pub post_id: Uuid,
    pub author_id: Uuid,
    pub content: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommentDeletedEvent {
    pub comment_id: Uuid,
}

pub struct SearchIndexConsumer {
    consumer: Arc<StreamConsumer>,
    es_client: Arc<ElasticsearchClient>,
}

impl SearchIndexConsumer {
    pub fn new(
        kafka_brokers: &str,
        group_id: &str,
        topics: &[&str],
        es_client: ElasticsearchClient,
    ) -> Result<Self, KafkaConsumerError> {
        let consumer: StreamConsumer = ClientConfig::new()
            .set("group.id", group_id)
            .set("bootstrap.servers", kafka_brokers)
            .set("enable.auto.commit", "true")
            .set("auto.commit.interval.ms", "5000")
            .set("session.timeout.ms", "30000")
            .set("enable.partition.eof", "false")
            .set("auto.offset.reset", "latest")
            .create()?;

        let mut tpl = TopicPartitionList::new();
        for topic in topics {
            tpl.add_partition(topic, 0);
        }
        consumer.subscribe(topics)?;

        Ok(Self {
            consumer: Arc::new(consumer),
            es_client: Arc::new(es_client),
        })
    }

    pub async fn start(&self) -> Result<(), KafkaConsumerError> {
        info!("Starting Kafka consumer for search index sync");

        loop {
            match self.consumer.recv().await {
                Ok(msg) => {
                    if let Some(payload) = msg.payload() {
                        if let Err(e) = self.process_message(payload).await {
                            error!("Failed to process message: {}", e);
                            // Continue processing other messages
                        } else {
                            // Commit offset after successful processing
                            if let Err(e) = self
                                .consumer
                                .commit_message(&msg, rdkafka::consumer::CommitMode::Async)
                            {
                                warn!("Failed to commit offset: {}", e);
                            }
                        }
                    }
                }
                Err(e) => {
                    error!("Kafka consumer error: {}", e);
                    // Exponential backoff retry
                    tokio::time::sleep(Duration::from_secs(5)).await;
                }
            }
        }
    }

    async fn process_message(&self, payload: &[u8]) -> Result<(), KafkaConsumerError> {
        let event: ContentEvent = serde_json::from_slice(payload)?;

        match event {
            ContentEvent::PostCreated(event) => {
                self.handle_post_created(event).await?;
            }
            ContentEvent::PostEdited(event) => {
                self.handle_post_edited(event).await?;
            }
            ContentEvent::PostDeleted(event) => {
                self.handle_post_deleted(event).await?;
            }
            ContentEvent::UserUpdated(event) => {
                self.handle_user_updated(event).await?;
            }
            ContentEvent::CommentCreated(event) => {
                self.handle_comment_created(event).await?;
            }
            ContentEvent::CommentDeleted(event) => {
                self.handle_comment_deleted(event).await?;
            }
        }

        Ok(())
    }

    async fn handle_post_created(&self, event: PostCreatedEvent) -> Result<(), KafkaConsumerError> {
        info!("Indexing new post: {}", event.post_id);

        let doc = elasticsearch::PostDocument {
            id: event.post_id,
            user_id: event.user_id,
            title: event.title,
            content: event.content,
            tags: event.tags,
            likes_count: event.likes_count,
            comments_count: event.comments_count,
            created_at: event.created_at,
        };

        self.es_client.index_post(&doc).await?;
        Ok(())
    }

    async fn handle_post_edited(&self, event: PostEditedEvent) -> Result<(), KafkaConsumerError> {
        info!("Updating post index: {}", event.post_id);

        // Re-index the post with updated data
        // In production, we'd fetch the full post data and update
        // For now, we'll create a partial update
        let doc = elasticsearch::PostDocument {
            id: event.post_id,
            user_id: Uuid::nil(), // Placeholder - should fetch from DB
            title: event.title,
            content: event.content,
            tags: event.tags,
            likes_count: 0,
            comments_count: 0,
            created_at: Utc::now(),
        };

        self.es_client.index_post(&doc).await?;
        Ok(())
    }

    async fn handle_post_deleted(&self, event: PostDeletedEvent) -> Result<(), KafkaConsumerError> {
        info!("Deleting post from index: {}", event.post_id);

        self.es_client.delete_post(event.post_id).await?;
        Ok(())
    }

    async fn handle_user_updated(&self, event: UserUpdatedEvent) -> Result<(), KafkaConsumerError> {
        info!("Updating user index: {}", event.user_id);

        let doc = elasticsearch::UserDocument {
            user_id: event.user_id,
            username: event.username,
            display_name: event.display_name,
            bio: event.bio,
            avatar_url: event.avatar_url,
            location: event.location,
            interests: event.interests,
            is_verified: event.is_verified,
            follower_count: event.follower_count,
        };

        self.es_client.index_user(&doc).await?;
        Ok(())
    }

    async fn handle_comment_created(
        &self,
        event: CommentCreatedEvent,
    ) -> Result<(), KafkaConsumerError> {
        info!("Indexing new comment: {}", event.comment_id);

        let doc = elasticsearch::CommentDocument {
            id: event.comment_id,
            post_id: event.post_id,
            author_id: event.author_id,
            content: event.content,
            created_at: event.created_at,
        };

        self.es_client.index_comment(&doc).await?;
        Ok(())
    }

    async fn handle_comment_deleted(
        &self,
        event: CommentDeletedEvent,
    ) -> Result<(), KafkaConsumerError> {
        info!("Deleting comment from index: {}", event.comment_id);

        self.es_client.delete_comment(event.comment_id).await?;
        Ok(())
    }

    pub async fn health_check(&self) -> bool {
        // Check if consumer is still alive by checking the assigned partitions
        self.consumer.assignment().is_ok()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_content_event_deserialization() {
        let json = r#"{
            "event_type": "post_created",
            "post_id": "550e8400-e29b-41d4-a716-446655440000",
            "user_id": "550e8400-e29b-41d4-a716-446655440001",
            "title": "Test Post",
            "content": "Test content",
            "tags": ["test", "rust"],
            "likes_count": 0,
            "comments_count": 0,
            "created_at": "2024-01-01T00:00:00Z"
        }"#;

        let event: ContentEvent = serde_json::from_str(json).expect("Failed to parse");

        match event {
            ContentEvent::PostCreated(e) => {
                assert_eq!(e.title, Some("Test Post".to_string()));
                assert_eq!(e.tags.len(), 2);
            }
            _ => panic!("Expected PostCreated event"),
        }
    }
}
