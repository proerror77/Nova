//! Mock AuthClient for Integration Tests
//!
//! Provides a mock implementation of AuthClient that doesn't require real gRPC connections.
//! Used for testing batch API and content cleaner logic in isolation.

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

    /// Batch get users by IDs (simulates grpc_clients::AuthClient::get_users_by_ids)
    pub async fn get_users_by_ids(&self, user_ids: &[Uuid]) -> Result<HashMap<Uuid, String>, String> {
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
}
