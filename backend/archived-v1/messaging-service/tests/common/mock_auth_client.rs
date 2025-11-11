//! Mock AuthClient for Integration Tests
//!
//! Provides a mock implementation of AuthClient that doesn't require real gRPC connections.
//! Used for testing batch API and orphan cleaner logic in isolation.

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use uuid::Uuid;

/// Mock AuthClient that simulates auth-service responses
#[derive(Clone)]
pub struct MockAuthClient {
    /// Simulated user database: user_id -> username
    users: Arc<Mutex<HashMap<Uuid, String>>>,
    /// Track number of get_users_by_ids calls for N+1 verification
    batch_call_count: Arc<Mutex<usize>>,
}

impl MockAuthClient {
    /// Create mock client with initial users
    pub fn new(users: Vec<(Uuid, String)>) -> Self {
        Self {
            users: Arc::new(Mutex::new(users.into_iter().collect())),
            batch_call_count: Arc::new(Mutex::new(0)),
        }
    }

    /// Create empty mock client
    pub fn empty() -> Self {
        Self::new(Vec::new())
    }

    /// Add user to mock database
    pub fn add_user(&self, user_id: Uuid, username: String) {
        let mut users = self.users.lock().unwrap();
        users.insert(user_id, username);
    }

    /// Remove user from mock database (simulate soft-delete)
    pub fn remove_user(&self, user_id: Uuid) {
        let mut users = self.users.lock().unwrap();
        users.remove(&user_id);
    }

    /// Check if user exists (filters deleted users)
    pub async fn user_exists(&self, user_id: Uuid) -> Result<bool, String> {
        let users = self.users.lock().unwrap();
        Ok(users.contains_key(&user_id))
    }

    /// Get user by ID
    pub async fn get_user(&self, user_id: Uuid) -> Result<Option<String>, String> {
        let users = self.users.lock().unwrap();
        Ok(users.get(&user_id).cloned())
    }

    /// Batch get users by IDs (simulates grpc-clients::AuthClient::get_users_by_ids)
    pub async fn get_users_by_ids(
        &self,
        user_ids: &[Uuid],
    ) -> Result<HashMap<Uuid, String>, String> {
        // Increment call counter for N+1 verification
        {
            let mut count = self.batch_call_count.lock().unwrap();
            *count += 1;
        }

        let users = self.users.lock().unwrap();
        let result: HashMap<Uuid, String> = user_ids
            .iter()
            .filter_map(|id| users.get(id).map(|name| (*id, name.clone())))
            .collect();

        Ok(result)
    }

    /// Get number of batch API calls (for N+1 test verification)
    pub fn get_batch_call_count(&self) -> usize {
        *self.batch_call_count.lock().unwrap()
    }

    /// Reset batch call counter
    pub fn reset_call_count(&self) {
        let mut count = self.batch_call_count.lock().unwrap();
        *count = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mock_auth_client_basic() {
        let user_id = Uuid::new_v4();
        let mock_client = MockAuthClient::new(vec![(user_id, "test_user".to_string())]);

        // Test user_exists
        assert!(mock_client.user_exists(user_id).await.unwrap());
        assert!(!mock_client.user_exists(Uuid::new_v4()).await.unwrap());

        // Test get_user
        assert_eq!(
            mock_client.get_user(user_id).await.unwrap(),
            Some("test_user".to_string())
        );
        assert_eq!(mock_client.get_user(Uuid::new_v4()).await.unwrap(), None);
    }

    #[tokio::test]
    async fn test_mock_auth_client_batch() {
        let user1 = Uuid::new_v4();
        let user2 = Uuid::new_v4();
        let user3 = Uuid::new_v4();

        let mock_client = MockAuthClient::new(vec![
            (user1, "user1".to_string()),
            (user2, "user2".to_string()),
        ]);

        // Test batch get
        let user_ids = vec![user1, user2, user3];
        let result = mock_client.get_users_by_ids(&user_ids).await.unwrap();

        assert_eq!(result.len(), 2); // Only user1 and user2 exist
        assert_eq!(result.get(&user1), Some(&"user1".to_string()));
        assert_eq!(result.get(&user2), Some(&"user2".to_string()));
        assert_eq!(result.get(&user3), None);

        // Verify call count
        assert_eq!(mock_client.get_batch_call_count(), 1);
    }

    #[tokio::test]
    async fn test_mock_auth_client_add_remove() {
        let user_id = Uuid::new_v4();
        let mock_client = MockAuthClient::empty();

        // Initially no users
        assert!(!mock_client.user_exists(user_id).await.unwrap());

        // Add user
        mock_client.add_user(user_id, "new_user".to_string());
        assert!(mock_client.user_exists(user_id).await.unwrap());

        // Remove user (simulate soft-delete)
        mock_client.remove_user(user_id);
        assert!(!mock_client.user_exists(user_id).await.unwrap());
    }
}
