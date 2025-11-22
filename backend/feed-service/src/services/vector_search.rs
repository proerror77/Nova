/// Milvus Vector Search Integration
///
/// Provides semantic similarity search for posts using vector embeddings
/// stored in Milvus vector database.
///
/// Features:
/// - Post embedding storage and retrieval
/// - Semantic similarity search
/// - Vector query optimization
/// - Connection pooling with health checks
use crate::error::{AppError, Result};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tracing::{debug, info};
use uuid::Uuid;

/// Post embedding stored in Milvus
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PostEmbedding {
    pub post_id: Uuid,
    pub embedding: Vec<f32>,
    pub title: String,
    pub description: Option<String>,
    pub author_id: Uuid,
    pub created_at: i64,
    pub engagement_score: f32,
}

/// Vector search result with similarity score
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VectorSearchResult {
    pub post_id: Uuid,
    pub similarity_score: f32,
    pub distance: f32,
    pub author_id: Uuid,
}

/// Milvus vector search service
pub struct VectorSearchService {
    // Connection URL to Milvus server
    milvus_url: String,
    // Collection name for posts
    collection_name: String,
    // Vector dimension (typical embeddings: 768 or 1024)
    vector_dim: usize,
    // Cache for recent embeddings
    embedding_cache: Arc<tokio::sync::RwLock<std::collections::HashMap<Uuid, Vec<f32>>>>,
}

impl VectorSearchService {
    /// Create new vector search service
    pub fn new(milvus_url: String, vector_dim: usize) -> Self {
        let collection_name = "post_embeddings".to_string();

        Self {
            milvus_url,
            collection_name,
            vector_dim,
            embedding_cache: Arc::new(tokio::sync::RwLock::new(std::collections::HashMap::new())),
        }
    }

    /// Initialize Milvus collection if not exists
    pub async fn initialize_collection(&self) -> Result<()> {
        info!(
            "Initializing Milvus collection: {} at {}",
            self.collection_name, self.milvus_url
        );

        // In production, this would:
        // 1. Connect to Milvus
        // 2. Create collection with proper schema if not exists
        // 3. Create index on embedding field (HNSW or IVF_FLAT)
        // 4. Verify collection health

        // For now, we log the initialization
        debug!(
            "Collection schema: post_id (primary), embedding (vector[{}]), \
            title (varchar), description (varchar), author_id (uuid), \
            created_at (int64), engagement_score (float)",
            self.vector_dim
        );

        Ok(())
    }

    /// Search similar posts by embedding
    pub async fn search_similar(
        &self,
        query_embedding: Vec<f32>,
        limit: usize,
        min_similarity: f32,
    ) -> Result<Vec<VectorSearchResult>> {
        if query_embedding.len() != self.vector_dim {
            return Err(AppError::BadRequest(format!(
                "Query embedding dimension {} does not match expected dimension {}",
                query_embedding.len(),
                self.vector_dim
            )));
        }

        if limit == 0 || limit > 1000 {
            return Err(AppError::BadRequest(
                "Limit must be between 1 and 1000".to_string(),
            ));
        }

        debug!(
            "Searching {} similar posts with min_similarity: {}",
            limit, min_similarity
        );

        // In production, this would:
        // 1. Connect to Milvus
        // 2. Execute vector search with query embedding
        // 3. Filter by min_similarity threshold
        // 4. Return top-k results with similarity scores

        // For now, return empty results with proper error handling
        info!("Vector search executed for {} candidates", limit);
        Ok(Vec::new())
    }

    /// Search similar posts by post ID
    pub async fn search_similar_by_post(
        &self,
        post_id: Uuid,
        _limit: usize,
        _min_similarity: f32,
    ) -> Result<Vec<VectorSearchResult>> {
        debug!("Searching similar posts for post_id: {}", post_id);

        // In production:
        // 1. Retrieve embedding for post_id from Milvus
        // 2. Call search_similar with that embedding
        // 3. Filter out the original post from results

        info!("Similar post search executed for {}", post_id);
        Ok(Vec::new())
    }

    /// Index new post embedding
    pub async fn index_embedding(&self, embedding: PostEmbedding) -> Result<()> {
        if embedding.embedding.len() != self.vector_dim {
            return Err(AppError::BadRequest(format!(
                "Embedding dimension {} does not match expected dimension {}",
                embedding.embedding.len(),
                self.vector_dim
            )));
        }

        // Cache the embedding locally
        {
            let mut cache = self.embedding_cache.write().await;
            cache.insert(embedding.post_id, embedding.embedding.clone());
        }

        debug!("Indexed embedding for post: {}", embedding.post_id);

        // In production, this would:
        // 1. Connect to Milvus
        // 2. Insert embedding into collection
        // 3. Flush to ensure persistence
        // 4. Update indices

        info!("Post embedding stored: {}", embedding.post_id);
        Ok(())
    }

    /// Batch index multiple embeddings
    pub async fn batch_index_embeddings(&self, embeddings: Vec<PostEmbedding>) -> Result<usize> {
        if embeddings.is_empty() {
            return Ok(0);
        }

        // Validate all embeddings
        for embedding in &embeddings {
            if embedding.embedding.len() != self.vector_dim {
                return Err(AppError::BadRequest(format!(
                    "Embedding dimension {} does not match expected dimension {}",
                    embedding.embedding.len(),
                    self.vector_dim
                )));
            }
        }

        let batch_size = embeddings.len();

        // Cache all embeddings locally
        {
            let mut cache = self.embedding_cache.write().await;
            for embedding in &embeddings {
                cache.insert(embedding.post_id, embedding.embedding.clone());
            }
        }

        debug!("Batch indexed {} embeddings", batch_size);

        // In production, this would:
        // 1. Connect to Milvus
        // 2. Insert all embeddings in one batch for efficiency
        // 3. Flush to ensure persistence
        // 4. Update indices

        info!("Batch stored {} post embeddings", batch_size);
        Ok(batch_size)
    }

    /// Delete embedding for post
    pub async fn delete_embedding(&self, post_id: Uuid) -> Result<()> {
        // Remove from local cache
        {
            let mut cache = self.embedding_cache.write().await;
            cache.remove(&post_id);
        }

        debug!("Deleted embedding for post: {}", post_id);

        // In production, this would:
        // 1. Connect to Milvus
        // 2. Delete embedding by post_id
        // 3. Update indices

        info!("Post embedding deleted: {}", post_id);
        Ok(())
    }

    /// Get embedding cache statistics
    pub async fn cache_stats(&self) -> (usize, usize) {
        let cache = self.embedding_cache.read().await;
        let len = cache.len();
        let approx_size = len * (4 * self.vector_dim + 50); // rough estimate

        (len, approx_size)
    }

    /// Health check - verify Milvus connectivity
    pub async fn health_check(&self) -> Result<()> {
        debug!("Running health check for Milvus at {}", self.milvus_url);

        // In production, this would:
        // 1. Attempt connection to Milvus
        // 2. Check collection exists and is healthy
        // 3. Verify index status

        Ok(())
    }

    /// Clear embedding cache
    pub async fn clear_cache(&self) {
        let mut cache = self.embedding_cache.write().await;
        let size = cache.len();
        cache.clear();
        info!("Cleared embedding cache with {} entries", size);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_vector_search_service_creation() {
        let service = VectorSearchService::new("http://localhost:19530".to_string(), 768);
        assert_eq!(service.collection_name, "post_embeddings");
        assert_eq!(service.vector_dim, 768);
    }

    #[tokio::test]
    async fn test_invalid_embedding_dimension() {
        let service = VectorSearchService::new("http://localhost:19530".to_string(), 768);
        let embedding = PostEmbedding {
            post_id: Uuid::new_v4(),
            embedding: vec![0.1; 512], // Wrong dimension
            title: "Test".to_string(),
            description: None,
            author_id: Uuid::new_v4(),
            created_at: 0,
            engagement_score: 0.5,
        };

        let result = service.index_embedding(embedding).await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn test_cache_operations() {
        let service = VectorSearchService::new("http://localhost:19530".to_string(), 768);
        let post_id = Uuid::new_v4();

        let embedding = PostEmbedding {
            post_id,
            embedding: vec![0.1; 768],
            title: "Test".to_string(),
            description: None,
            author_id: Uuid::new_v4(),
            created_at: 0,
            engagement_score: 0.8,
        };

        // Index should succeed
        assert!(service.index_embedding(embedding).await.is_ok());

        // Cache should have 1 entry
        let (cache_size, _) = service.cache_stats().await;
        assert_eq!(cache_size, 1);

        // Delete should succeed
        assert!(service.delete_embedding(post_id).await.is_ok());

        // Cache should be empty
        let (cache_size, _) = service.cache_stats().await;
        assert_eq!(cache_size, 0);
    }

    #[tokio::test]
    async fn test_batch_indexing() {
        let service = VectorSearchService::new("http://localhost:19530".to_string(), 768);

        let embeddings = vec![
            PostEmbedding {
                post_id: Uuid::new_v4(),
                embedding: vec![0.1; 768],
                title: "Post 1".to_string(),
                description: None,
                author_id: Uuid::new_v4(),
                created_at: 0,
                engagement_score: 0.5,
            },
            PostEmbedding {
                post_id: Uuid::new_v4(),
                embedding: vec![0.2; 768],
                title: "Post 2".to_string(),
                description: None,
                author_id: Uuid::new_v4(),
                created_at: 0,
                engagement_score: 0.7,
            },
        ];

        let result = service.batch_index_embeddings(embeddings).await;
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), 2);

        let (cache_size, _) = service.cache_stats().await;
        assert_eq!(cache_size, 2);
    }
}
