//! GraphQL Schema with Federation support
//! ✅ P0-4: Full schema implementation with subscriptions and pagination
//! ✅ P0-5: DataLoader for N+1 query prevention
//! ✅ P0-5: Query complexity analysis

pub mod user;
pub mod content;
pub mod auth;
pub mod subscription;
pub mod pagination;
pub mod loaders;
pub mod complexity;
pub mod backpressure;

use async_graphql::{MergedObject, Schema, dataloader::DataLoader};

use crate::clients::ServiceClients;
use crate::security::{ComplexityLimit, RequestBudget, SecurityConfig};

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
/// ✅ P0-2: Security extensions (complexity limits, request budget)
pub fn build_schema(clients: ServiceClients) -> AppSchema {
    // Load security config from environment
    let security_config = SecurityConfig::from_env().unwrap_or_default();

    tracing::info!(
        max_complexity = security_config.max_complexity,
        max_depth = security_config.max_depth,
        max_backend_calls = security_config.max_backend_calls,
        allow_introspection = security_config.allow_introspection,
        "GraphQL security extensions enabled"
    );

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
    // ✅ P0-2: Security extensions
    .extension(ComplexityLimit::new(
        security_config.max_complexity,
        security_config.max_depth,
    ))
    .extension(RequestBudget::new(security_config.max_backend_calls))
    // Disable introspection in production
    .enable_federation()
    .disable_introspection(if !security_config.allow_introspection {
        tracing::warn!("GraphQL introspection DISABLED for production security");
        true
    } else {
        tracing::warn!("GraphQL introspection ENABLED (development only)");
        false
    })
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
