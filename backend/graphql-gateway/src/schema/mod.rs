//! GraphQL Schema with Federation support
//! ✅ P0-4: Full schema implementation with subscriptions and pagination
//! ✅ P0-5: DataLoader for N+1 query prevention

pub mod user;
pub mod content;
pub mod auth;
pub mod subscription;
pub mod pagination;
pub mod loaders;

use async_graphql::{MergedObject, Schema, dataloader::DataLoader};

use crate::clients::ServiceClients;

/// Root query object (federated)
#[derive(MergedObject, Default)]
pub struct QueryRoot(user::UserQuery, content::ContentQuery, auth::AuthQuery);

/// Root mutation object (federated)
#[derive(MergedObject, Default)]
pub struct MutationRoot(user::UserMutation, content::ContentMutation, auth::AuthMutation);

/// GraphQL App Schema type with WebSocket subscriptions
pub type AppSchema = Schema<QueryRoot, MutationRoot, subscription::SubscriptionRoot>;

/// Build federated GraphQL schema with subscriptions and DataLoaders
/// ✅ P0-5: DataLoaders prevent N+1 queries by batching database loads
pub fn build_schema(clients: ServiceClients) -> AppSchema {
    Schema::build(
        QueryRoot::default(),
        MutationRoot::default(),
        subscription::SubscriptionRoot::default(),
    )
    .data(clients)
    // ✅ P0-5: Add DataLoaders for batch loading
    // DataLoaders prevent N+1 queries by batching database requests
    .data(DataLoader::new(loaders::UserIdLoader::new(), tokio::task::spawn))
    .data(DataLoader::new(loaders::PostIdLoader::new(), tokio::task::spawn))
    .data(DataLoader::new(loaders::IdCountLoader::new(), tokio::task::spawn))
    .data(DataLoader::new(loaders::LikeCountLoader::new(), tokio::task::spawn))
    .data(DataLoader::new(loaders::FollowCountLoader::new(), tokio::task::spawn))
    .enable_federation()
    .finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_schema_builds() {
        // Test schema compilation
        let clients = ServiceClients::default();
        let schema = build_schema(clients);
        assert!(schema.sdl().contains("type Query"));
    }
}
