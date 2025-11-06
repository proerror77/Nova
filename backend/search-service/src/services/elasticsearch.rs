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
    user_index: String,
    comment_index: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostDocument {
    pub id: Uuid,
    pub user_id: Uuid,
    pub title: Option<String>,
    pub content: Option<String>,
    pub tags: Vec<String>,
    pub likes_count: i32,
    pub comments_count: i32,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserDocument {
    pub user_id: Uuid,
    pub username: String,
    pub display_name: String,
    pub bio: Option<String>,
    pub location: Option<String>,
    pub interests: Vec<String>,
    pub is_verified: bool,
    pub follower_count: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommentDocument {
    pub id: Uuid,
    pub post_id: Uuid,
    pub author_id: Uuid,
    pub content: String,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HashtagDocument {
    pub tag: String,
    pub post_count: i32,
    pub usage_count: i32,
    pub trending_status: String,
}

#[derive(Debug)]
pub struct FullTextSearchResults {
    pub posts: Vec<PostDocument>,
    pub users: Vec<UserDocument>,
    pub hashtags: Vec<String>,
}

impl ElasticsearchClient {
    pub async fn new(
        url: &str,
        post_index: &str,
        message_index: &str,
        user_index: &str,
        comment_index: &str,
    ) -> Result<Self, ElasticsearchError> {
        let parsed = Url::parse(url)?;
        let pool = SingleNodeConnectionPool::new(parsed);
        let transport = TransportBuilder::new(pool).build()?;
        let client = Elasticsearch::new(transport);

        let instance = Self {
            client,
            post_index: post_index.to_string(),
            message_index: message_index.to_string(),
            user_index: user_index.to_string(),
            comment_index: comment_index.to_string(),
        };

        instance.ensure_post_index().await?;
        instance.ensure_message_index().await?;
        instance.ensure_user_index().await?;
        instance.ensure_comment_index().await?;

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
            "settings": {
                "number_of_shards": 3,
                "number_of_replicas": 1,
                "analysis": {
                    "analyzer": {
                        "content_analyzer": {
                            "type": "custom",
                            "tokenizer": "standard",
                            "filter": ["lowercase", "english_stop", "english_stemmer"]
                        }
                    },
                    "filter": {
                        "english_stop": {
                            "type": "stop",
                            "stopwords": "_english_"
                        },
                        "english_stemmer": {
                            "type": "stemmer",
                            "language": "english"
                        }
                    }
                }
            },
            "mappings": {
                "properties": {
                    "id": { "type": "keyword" },
                    "user_id": { "type": "keyword" },
                    "title": {
                        "type": "text",
                        "analyzer": "content_analyzer",
                        "boost": 2.0
                    },
                    "content": {
                        "type": "text",
                        "analyzer": "content_analyzer"
                    },
                    "tags": {
                        "type": "keyword"
                    },
                    "likes_count": { "type": "integer" },
                    "comments_count": { "type": "integer" },
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

    async fn ensure_user_index(&self) -> Result<(), ElasticsearchError> {
        let exists_response = self
            .client
            .indices()
            .exists(IndicesExistsParts::Index(&[self.user_index.as_str()]))
            .send()
            .await?;

        if exists_response.status_code().is_success() {
            return Ok(());
        }

        let body = json!({
            "settings": {
                "number_of_shards": 2,
                "number_of_replicas": 1
            },
            "mappings": {
                "properties": {
                    "user_id": { "type": "keyword" },
                    "username": {
                        "type": "text",
                        "fields": {
                            "keyword": { "type": "keyword" }
                        },
                        "boost": 2.0
                    },
                    "display_name": {
                        "type": "text",
                        "analyzer": "english",
                        "boost": 1.5
                    },
                    "bio": {
                        "type": "text",
                        "analyzer": "english"
                    },
                    "location": {
                        "type": "text",
                        "fields": {
                            "keyword": { "type": "keyword" }
                        }
                    },
                    "interests": {
                        "type": "keyword"
                    },
                    "is_verified": { "type": "boolean" },
                    "follower_count": { "type": "integer" }
                }
            }
        });

        self.client
            .indices()
            .create(IndicesCreateParts::Index(&self.user_index))
            .body(body)
            .send()
            .await?;

        Ok(())
    }

    async fn ensure_comment_index(&self) -> Result<(), ElasticsearchError> {
        let exists_response = self
            .client
            .indices()
            .exists(IndicesExistsParts::Index(&[self.comment_index.as_str()]))
            .send()
            .await?;

        if exists_response.status_code().is_success() {
            return Ok(());
        }

        let body = json!({
            "settings": {
                "number_of_shards": 2,
                "number_of_replicas": 1
            },
            "mappings": {
                "properties": {
                    "id": { "type": "keyword" },
                    "post_id": { "type": "keyword" },
                    "author_id": { "type": "keyword" },
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
            .create(IndicesCreateParts::Index(&self.comment_index))
            .body(body)
            .send()
            .await?;

        Ok(())
    }

    pub async fn search_posts(
        &self,
        query: &str,
        limit: i64,
        offset: i64,
    ) -> Result<Vec<PostDocument>, ElasticsearchError> {
        let size = limit.clamp(1, 100);
        let from = offset.max(0);

        let body = json!({
            "size": size,
            "from": from,
            "query": {
                "multi_match": {
                    "query": query,
                    "fields": ["title^2", "content", "tags"],
                    "type": "best_fields"
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

    pub async fn search_users(
        &self,
        query: &str,
        limit: i64,
        offset: i64,
        verified_only: bool,
    ) -> Result<Vec<UserDocument>, ElasticsearchError> {
        let size = limit.clamp(1, 100);
        let from = offset.max(0);

        let must_clauses = vec![
            json!({
                "multi_match": {
                    "query": query,
                    "fields": ["username^2", "display_name^1.5", "bio"],
                    "type": "best_fields"
                }
            })
        ];

        let mut filter_clauses = vec![];
        if verified_only {
            filter_clauses.push(json!({ "term": { "is_verified": true } }));
        }

        let query_body = if filter_clauses.is_empty() {
            json!({ "must": must_clauses })
        } else {
            json!({ "must": must_clauses, "filter": filter_clauses })
        };

        let body = json!({
            "size": size,
            "from": from,
            "query": {
                "bool": query_body
            },
            "sort": [
                { "_score": { "order": "desc" }},
                { "follower_count": { "order": "desc" }}
            ]
        });

        let response = self
            .client
            .search(SearchParts::Index(&[self.user_index.as_str()]))
            .body(body)
            .send()
            .await?;

        let status = response.status_code();
        if status.is_success() {
            let search_response: UserSearchResponse = response.json().await?;
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

    pub async fn search_hashtags(
        &self,
        query: &str,
        limit: i64,
    ) -> Result<Vec<String>, ElasticsearchError> {
        let size = limit.clamp(1, 100);

        // Search for matching hashtags in post tags
        let body = json!({
            "size": 0,
            "query": {
                "wildcard": {
                    "tags": {
                        "value": format!("{}*", query.to_lowercase()),
                        "case_insensitive": true
                    }
                }
            },
            "aggs": {
                "popular_tags": {
                    "terms": {
                        "field": "tags",
                        "size": size,
                        "order": { "_count": "desc" }
                    }
                }
            }
        });

        let response = self
            .client
            .search(SearchParts::Index(&[self.post_index.as_str()]))
            .body(body)
            .send()
            .await?;

        if !response.status_code().is_success() {
            return Ok(vec![]);
        }

        let result: serde_json::Value = response.json().await?;
        let tags = result["aggregations"]["popular_tags"]["buckets"]
            .as_array()
            .unwrap_or(&vec![])
            .iter()
            .filter_map(|bucket| bucket["key"].as_str().map(String::from))
            .collect();

        Ok(tags)
    }

    pub async fn full_text_search(
        &self,
        query: &str,
        limit: i64,
        offset: i64,
    ) -> Result<FullTextSearchResults, ElasticsearchError> {
        // Search across all indices concurrently
        let posts_fut = self.search_posts(query, limit, offset);
        let users_fut = self.search_users(query, limit.min(20), 0, false);
        let hashtags_fut = self.search_hashtags(query, 10);

        let (posts, users, hashtags) = tokio::join!(posts_fut, users_fut, hashtags_fut);

        Ok(FullTextSearchResults {
            posts: posts?,
            users: users?,
            hashtags: hashtags?,
        })
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

    pub async fn index_user(&self, doc: &UserDocument) -> Result<(), ElasticsearchError> {
        self.client
            .index(IndexParts::IndexId(
                &self.user_index,
                doc.user_id.to_string().as_str(),
            ))
            .body(doc)
            .send()
            .await?;
        Ok(())
    }

    pub async fn delete_user(&self, user_id: Uuid) -> Result<(), ElasticsearchError> {
        self.client
            .delete(DeleteParts::IndexId(
                &self.user_index,
                user_id.to_string().as_str(),
            ))
            .send()
            .await?;
        Ok(())
    }

    pub async fn index_comment(&self, doc: &CommentDocument) -> Result<(), ElasticsearchError> {
        self.client
            .index(IndexParts::IndexId(
                &self.comment_index,
                doc.id.to_string().as_str(),
            ))
            .body(doc)
            .send()
            .await?;
        Ok(())
    }

    pub async fn delete_comment(&self, id: Uuid) -> Result<(), ElasticsearchError> {
        self.client
            .delete(DeleteParts::IndexId(
                &self.comment_index,
                id.to_string().as_str(),
            ))
            .send()
            .await?;
        Ok(())
    }

    pub async fn bulk_index_posts(
        &self,
        docs: Vec<PostDocument>,
    ) -> Result<(), ElasticsearchError> {
        if docs.is_empty() {
            return Ok(());
        }

        // Build NDJSON body for bulk operation
        let mut body_lines = Vec::new();
        for doc in docs {
            let action = json!({ "index": { "_index": &self.post_index, "_id": doc.id.to_string() } });
            body_lines.push(serde_json::to_string(&action)?);
            body_lines.push(serde_json::to_string(&doc)?);
        }

        self.client
            .bulk(elasticsearch::BulkParts::None)
            .body(body_lines)
            .send()
            .await?;

        Ok(())
    }

    pub async fn health_check(&self) -> Result<(), ElasticsearchError> {
        let response = self.client.ping().send().await?;
        if response.status_code().is_success() {
            Ok(())
        } else {
            Err(ElasticsearchError::Transport(
                elasticsearch::Error::from(std::io::Error::new(
                    std::io::ErrorKind::Other,
                    "Elasticsearch health check failed"
                )),
            ))
        }
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

#[derive(Debug, Deserialize)]
struct UserSearchResponse {
    hits: UserInnerHits,
}

#[derive(Debug, Deserialize)]
struct UserInnerHits {
    hits: Vec<UserHit>,
}

#[derive(Debug, Deserialize)]
struct UserHit {
    #[serde(rename = "_source")]
    source: Option<UserDocument>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageDocument {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_id: Uuid,
    pub content: String,
    pub created_at: DateTime<Utc>,
}
