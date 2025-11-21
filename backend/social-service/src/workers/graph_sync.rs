use std::sync::Arc;
use tonic::transport::Channel;
use tonic::Request;
use tracing::{error, info, warn};
use transactional_outbox::{OutboxEvent, OutboxRepository, SqlxOutboxRepository};

use grpc_clients::nova::graph_service::v2::{
    graph_service_client::GraphServiceClient, CreateFollowRequest, DeleteFollowRequest,
};

/// GraphSyncConsumer: consumes outbox events and synchronizes edges to graph-service.
pub struct GraphSyncConsumer {
    repo: Arc<SqlxOutboxRepository>,
    graph_client: GraphServiceClient<Channel>,
    write_token: String,
}

impl GraphSyncConsumer {
    pub fn new(
        repo: Arc<SqlxOutboxRepository>,
        graph_client: GraphServiceClient<Channel>,
        write_token: String,
    ) -> Self {
        Self {
            repo,
            graph_client,
            write_token,
        }
    }

    pub async fn run(mut self) {
        info!("Starting graph-sync consumer");
        loop {
            let events = match self.repo.get_unpublished(50).await {
                Ok(evts) => evts,
                Err(e) => {
                    error!("graph-sync: failed to fetch unpublished events: {}", e);
                    tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                    continue;
                }
            };

            if events.is_empty() {
                tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                continue;
            }

            for event in events {
                if let Err(e) = self.process_event(&event).await {
                    warn!("graph-sync: failed to process event {}: {}", event.id, e);
                    if let Err(m) = self.repo.mark_failed(event.id, &format!("{}", e)).await {
                        error!("graph-sync: mark_failed error: {}", m);
                    }
                } else if let Err(m) = self.repo.mark_published(event.id).await {
                    error!("graph-sync: mark_published error: {}", m);
                }
            }
        }
    }

    async fn process_event(&mut self, evt: &OutboxEvent) -> anyhow::Result<()> {
        match evt.event_type.as_str() {
            "social.follow.created" => {
                let follower_id = self.get_str(&evt.payload, "follower_id")?;
                let followee_id = self.get_str(&evt.payload, "followee_id")?;
                self.create_follow(follower_id, followee_id).await?;
            }
            "social.follow.deleted" => {
                let follower_id = self.get_str(&evt.payload, "follower_id")?;
                let followee_id = self.get_str(&evt.payload, "followee_id")?;
                self.delete_follow(follower_id, followee_id).await?;
            }
            _ => {
                // Ignore unrelated events
            }
        }
        Ok(())
    }

    fn get_str<'a>(&self, payload: &'a serde_json::Value, key: &str) -> anyhow::Result<&'a str> {
        payload
            .get(key)
            .and_then(|v| v.as_str())
            .ok_or_else(|| anyhow::anyhow!("missing payload key: {}", key))
    }

    async fn create_follow(&mut self, follower_id: &str, followee_id: &str) -> anyhow::Result<()> {
        let mut client = self.graph_client.clone();
        let mut req = Request::new(CreateFollowRequest {
            follower_id: follower_id.to_string(),
            followee_id: followee_id.to_string(),
        });
        let token_md = tonic::metadata::MetadataValue::try_from(self.write_token.as_str())?;
        req.metadata_mut().insert("x-internal-token", token_md);
        client.create_follow(req).await?;
        Ok(())
    }

    async fn delete_follow(&mut self, follower_id: &str, followee_id: &str) -> anyhow::Result<()> {
        let mut client = self.graph_client.clone();
        let mut req = Request::new(DeleteFollowRequest {
            follower_id: follower_id.to_string(),
            followee_id: followee_id.to_string(),
        });
        let token_md = tonic::metadata::MetadataValue::try_from(self.write_token.as_str())?;
        req.metadata_mut().insert("x-internal-token", token_md);
        client.delete_follow(req).await?;
        Ok(())
    }
}
