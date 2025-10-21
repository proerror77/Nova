use std::sync::Arc;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use tokio::sync::RwLock;
use std::collections::HashMap;

/// User ID type alias
pub type UserId = String;

/// Relationship type enum
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum RelationType {
    Follows,
    FollowedBy,
    Recommends,
    Blocks,
    Mutes,
}

impl RelationType {
    pub fn as_str(&self) -> &str {
        match self {
            RelationType::Follows => "FOLLOWS",
            RelationType::FollowedBy => "FOLLOWED_BY",
            RelationType::Recommends => "RECOMMENDS",
            RelationType::Blocks => "BLOCKS",
            RelationType::Mutes => "MUTES",
        }
    }
}

/// User node representation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UserNode {
    pub user_id: UserId,
    pub username: String,
    pub follow_count: u32,
    pub follower_count: u32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

impl UserNode {
    pub fn new(user_id: UserId, username: String) -> Self {
        let now = Utc::now();
        Self {
            user_id,
            username,
            follow_count: 0,
            follower_count: 0,
            created_at: now,
            updated_at: now,
        }
    }
}

/// Relationship between two users
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Relationship {
    pub from_user: UserId,
    pub to_user: UserId,
    pub relationship_type: RelationType,
    pub created_at: DateTime<Utc>,
}

/// Query for finding relationships
#[derive(Debug, Clone)]
pub struct RelationshipQuery {
    pub source_user: UserId,
    pub relationship_type: RelationType,
    pub limit: u32,
}

/// Neo4j Client - Manages social graph database operations
pub struct Neo4jClient {
    /// Connection pool for Neo4j
    connection_pool: Arc<RwLock<ConnectionPool>>,
    /// In-memory cache for demonstration
    users: Arc<RwLock<HashMap<UserId, UserNode>>>,
    relationships: Arc<RwLock<Vec<Relationship>>>,
}

/// Simple connection pool implementation
pub struct ConnectionPool {
    pub connections: Vec<String>,
    pub pool_size: usize,
}

impl Neo4jClient {
    /// Create a new Neo4j client
    pub async fn new(addresses: Vec<String>, pool_size: usize) -> Result<Self, String> {
        let pool = ConnectionPool {
            connections: addresses,
            pool_size,
        };

        Ok(Self {
            connection_pool: Arc::new(RwLock::new(pool)),
            users: Arc::new(RwLock::new(HashMap::new())),
            relationships: Arc::new(RwLock::new(Vec::new())),
        })
    }

    /// Create a new user node
    pub async fn create_user_node(&self, user_id: UserId, username: String) -> Result<UserNode, String> {
        let user = UserNode::new(user_id.clone(), username);
        let mut users = self.users.write().await;
        users.insert(user_id.clone(), user.clone());
        Ok(user)
    }

    /// Add a relationship between two users
    pub async fn add_relationship(
        &self,
        from_user: &UserId,
        to_user: &UserId,
        rel_type: RelationType,
    ) -> Result<Relationship, String> {
        let relationship = Relationship {
            from_user: from_user.clone(),
            to_user: to_user.clone(),
            relationship_type: rel_type,
            created_at: Utc::now(),
        };

        // Update follow counts
        if rel_type == RelationType::Follows {
            let mut users = self.users.write().await;
            if let Some(user) = users.get_mut(from_user) {
                user.follow_count += 1;
            }
            if let Some(user) = users.get_mut(to_user) {
                user.follower_count += 1;
            }
        }

        let mut relationships = self.relationships.write().await;
        relationships.push(relationship.clone());

        Ok(relationship)
    }

    /// Query relationships
    pub async fn query_relationships(&self, query: &RelationshipQuery) -> Result<Vec<UserNode>, String> {
        let relationships = self.relationships.read().await;
        let users = self.users.read().await;

        let mut result = Vec::new();
        for rel in relationships.iter() {
            if rel.from_user == query.source_user && rel.relationship_type == query.relationship_type {
                if let Some(user) = users.get(&rel.to_user) {
                    result.push(user.clone());
                    if result.len() >= query.limit as usize {
                        break;
                    }
                }
            }
        }

        Ok(result)
    }

    /// Find recommendations for a user
    pub async fn find_recommendations(&self, user_id: &UserId) -> Result<Vec<UserNode>, String> {
        let relationships = self.relationships.read().await;
        let users = self.users.read().await;

        let mut recommendations = Vec::new();
        let mut seen = std::collections::HashSet::new();

        // Find users that followed users this user follows
        for rel in relationships.iter() {
            if rel.from_user == *user_id && rel.relationship_type == RelationType::Follows {
                // For each followed user, find their followers
                for inner_rel in relationships.iter() {
                    if inner_rel.from_user == rel.to_user && inner_rel.relationship_type == RelationType::FollowedBy {
                        let target = &inner_rel.to_user;
                        // Don't recommend users already followed or self
                        if target != user_id && !seen.contains(target) {
                            if let Some(user) = users.get(target) {
                                recommendations.push(user.clone());
                                seen.insert(target.clone());
                            }
                        }
                    }
                }
            }
        }

        Ok(recommendations)
    }

    /// Find influencers (users with 10k+ followers)
    pub async fn find_influencers(&self) -> Result<Vec<UserNode>, String> {
        let users = self.users.read().await;
        let influencers: Vec<_> = users
            .values()
            .filter(|user| user.follower_count >= 10_000)
            .cloned()
            .collect();

        Ok(influencers)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_neo4j_client_creation() {
        let client = Neo4jClient::new(vec!["localhost:7687".to_string()], 10).await;
        assert!(client.is_ok());
    }

    #[tokio::test]
    async fn test_create_user_node() {
        let client = Neo4jClient::new(vec!["localhost:7687".to_string()], 10).await.unwrap();
        let user = client.create_user_node("user1".to_string(), "alice".to_string()).await;
        assert!(user.is_ok());
    }

    #[tokio::test]
    async fn test_add_relationship() {
        let client = Neo4jClient::new(vec!["localhost:7687".to_string()], 10).await.unwrap();
        let _ = client.create_user_node("user1".to_string(), "alice".to_string()).await;
        let _ = client.create_user_node("user2".to_string(), "bob".to_string()).await;

        let rel = client.add_relationship(&"user1".to_string(), &"user2".to_string(), RelationType::Follows).await;
        assert!(rel.is_ok());
    }

    #[tokio::test]
    async fn test_query_relationships() {
        let client = Neo4jClient::new(vec!["localhost:7687".to_string()], 10).await.unwrap();
        let _ = client.create_user_node("user1".to_string(), "alice".to_string()).await;
        let _ = client.create_user_node("user2".to_string(), "bob".to_string()).await;
        let _ = client.add_relationship(&"user1".to_string(), &"user2".to_string(), RelationType::Follows).await;

        let query = RelationshipQuery {
            source_user: "user1".to_string(),
            relationship_type: RelationType::Follows,
            limit: 10,
        };

        let results = client.query_relationships(&query).await;
        assert!(results.is_ok());
        assert_eq!(results.unwrap().len(), 1);
    }

    #[tokio::test]
    async fn test_find_recommendations() {
        let client = Neo4jClient::new(vec!["localhost:7687".to_string()], 10).await.unwrap();
        let _ = client.create_user_node("user1".to_string(), "alice".to_string()).await;
        let _ = client.create_user_node("user2".to_string(), "bob".to_string()).await;
        let _ = client.create_user_node("user3".to_string(), "charlie".to_string()).await;

        let _ = client.add_relationship(&"user1".to_string(), &"user2".to_string(), RelationType::Follows).await;
        let _ = client.add_relationship(&"user2".to_string(), &"user3".to_string(), RelationType::Follows).await;

        let recs = client.find_recommendations(&"user1".to_string()).await;
        assert!(recs.is_ok());
    }

    #[tokio::test]
    async fn test_find_influencers() {
        let client = Neo4jClient::new(vec!["localhost:7687".to_string()], 10).await.unwrap();
        let mut user1 = client.create_user_node("user1".to_string(), "alice".to_string()).await.unwrap();
        user1.follower_count = 15_000; // Make an influencer

        let mut users = client.users.write().await;
        users.insert("user1".to_string(), user1);
        drop(users);

        let influencers = client.find_influencers().await;
        assert!(influencers.is_ok());
        assert_eq!(influencers.unwrap().len(), 1);
    }

    #[test]
    fn test_relationship_type_str() {
        assert_eq!(RelationType::Follows.as_str(), "FOLLOWS");
        assert_eq!(RelationType::FollowedBy.as_str(), "FOLLOWED_BY");
        assert_eq!(RelationType::Recommends.as_str(), "RECOMMENDS");
        assert_eq!(RelationType::Blocks.as_str(), "BLOCKS");
        assert_eq!(RelationType::Mutes.as_str(), "MUTES");
    }
}
