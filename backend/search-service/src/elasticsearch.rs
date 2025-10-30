use chrono::{DateTime, Utc};
use elasticsearch::{
    http::transport::{BuildError, SingleNodeConnectionPool, TransportBuilder},
    indices::{IndicesCreateParts, IndicesExistsParts},
    DeleteParts, Elasticsearch, IndexParts, SearchParts,
};
use serde::{Deserialize, Serialize};
use serde_json::json;
use thiserror::Error;
use url::Url;
use uuid::Uuid;

#[derive(Debug, Error)]
pub enum ElasticsearchError {
    #[error("invalid Elasticsearch URL: {0}")]
    InvalidUrl(#[from] url::ParseError),
    #[error("failed to build transport: {0}")]
    TransportBuild(#[from] BuildError),
    #[error("transport error: {0}")]
    Transport(#[from] elasticsearch::Error),
    #[error("serialization error: {0}")]
    Serde(#[from] serde_json::Error),
}

#[derive(Clone)]
pub struct ElasticsearchClient {
    client: Elasticsearch,
    post_index: String,
    message_index: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostDocument {
    pub id: Uuid,
    pub user_id: Uuid,
    pub caption: Option<String>,
    pub created_at: Option<DateTime<Utc>>,
}

impl ElasticsearchClient {
    pub async fn new(
        url: &str,
        post_index: &str,
        message_index: &str,
    ) -> Result<Self, ElasticsearchError> {
        let parsed = Url::parse(url)?;
        let pool = SingleNodeConnectionPool::new(parsed);
        let transport = TransportBuilder::new(pool).build()?;
        let client = Elasticsearch::new(transport);

        let instance = Self {
            client,
            post_index: post_index.to_string(),
            message_index: message_index.to_string(),
        };

        instance.ensure_post_index().await?;
        instance.ensure_message_index().await?;

        Ok(instance)
    }

    async fn ensure_post_index(&self) -> Result<(), ElasticsearchError> {
        let exists_response = self
            .client
            .indices()
            .exists(IndicesExistsParts::Index(&[self.post_index.as_str()]))
            .send()
            .await?;

        if exists_response.status_code().is_success() {
            return Ok(());
        }

        let body = json!({
            "mappings": {
                "properties": {
                    "id": { "type": "keyword" },
                    "user_id": { "type": "keyword" },
                    "caption": {
                        "type": "text",
                        "analyzer": "english"
                    },
                    "created_at": { "type": "date" }
                }
            }
        });

        self.client
            .indices()
            .create(IndicesCreateParts::Index(&self.post_index))
            .body(body)
            .send()
            .await?;

        Ok(())
    }

    async fn ensure_message_index(&self) -> Result<(), ElasticsearchError> {
        let exists_response = self
            .client
            .indices()
            .exists(IndicesExistsParts::Index(&[self.message_index.as_str()]))
            .send()
            .await?;

        if exists_response.status_code().is_success() {
            return Ok(());
        }

        let body = json!({
            "mappings": {
                "properties": {
                    "id": { "type": "keyword" },
                    "conversation_id": { "type": "keyword" },
                    "sender_id": { "type": "keyword" },
                    "content": {
                        "type": "text",
                        "analyzer": "english"
                    },
                    "created_at": { "type": "date" }
                }
            }
        });

        self.client
            .indices()
            .create(IndicesCreateParts::Index(&self.message_index))
            .body(body)
            .send()
            .await?;

        Ok(())
    }

    pub async fn search_posts(
        &self,
        query: &str,
        limit: i64,
    ) -> Result<Vec<PostDocument>, ElasticsearchError> {
        let size = limit.clamp(1, 100) as i64;
        let body = json!({
            "size": size,
            "query": {
                "multi_match": {
                    "query": query,
                    "fields": ["caption^2"],
                    "type": "best_fields",
                    "operator": "and"
                }
            },
            "sort": [
                { "_score": { "order": "desc" }},
                { "created_at": { "order": "desc" }}
            ]
        });

        let response = self
            .client
            .search(SearchParts::Index(&[self.post_index.as_str()]))
            .body(body)
            .send()
            .await?;

        let status = response.status_code();
        if status.is_success() {
            let search_response: SearchResponse = response.json().await?;
            let docs = search_response
                .hits
                .hits
                .into_iter()
                .filter_map(|hit| hit.source)
                .collect();
            Ok(docs)
        } else {
            Ok(vec![])
        }
    }

    pub async fn index_post(&self, doc: &PostDocument) -> Result<(), ElasticsearchError> {
        self.client
            .index(IndexParts::IndexId(
                &self.post_index,
                doc.id.to_string().as_str(),
            ))
            .body(doc)
            .send()
            .await?;
        Ok(())
    }

    pub async fn delete_post(&self, id: Uuid) -> Result<(), ElasticsearchError> {
        self.client
            .delete(DeleteParts::IndexId(
                &self.post_index,
                id.to_string().as_str(),
            ))
            .send()
            .await?;
        Ok(())
    }

    pub async fn index_message(&self, doc: &MessageDocument) -> Result<(), ElasticsearchError> {
        self.client
            .index(IndexParts::IndexId(
                &self.message_index,
                doc.id.to_string().as_str(),
            ))
            .body(doc)
            .send()
            .await?;
        Ok(())
    }

    pub async fn delete_message(&self, id: Uuid) -> Result<(), ElasticsearchError> {
        self.client
            .delete(DeleteParts::IndexId(
                &self.message_index,
                id.to_string().as_str(),
            ))
            .send()
            .await?;
        Ok(())
    }
}

#[derive(Debug, Deserialize)]
struct SearchResponse {
    hits: InnerHits,
}

#[derive(Debug, Deserialize)]
struct InnerHits {
    hits: Vec<PostHit>,
}

#[derive(Debug, Deserialize)]
struct PostHit {
    #[serde(rename = "_source")]
    source: Option<PostDocument>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageDocument {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    pub content: String,
    pub created_at: DateTime<Utc>,
}
