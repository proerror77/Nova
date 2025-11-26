//! GraphQL Schema with Federation support
//! ✅ P0-4: Full schema implementation with subscriptions and pagination
//! ✅ P0-5: DataLoader for N+1 query prevention
//! ✅ P0-5: Query complexity analysis

pub mod auth;
pub mod backpressure;
pub mod complexity;
pub mod content;
pub mod loaders;
pub mod pagination;
pub mod subscription;
// user module temporarily disabled - user-service is deprecated
// pub mod user;

use async_graphql::{dataloader::DataLoader, MergedObject, Schema};

use crate::clients::ServiceClients;
use crate::security::{ComplexityLimit, RequestBudget, SecurityConfig};

/// Root query object (federated)
/// user::UserQuery temporarily disabled - user-service is deprecated
#[derive(MergedObject, Default)]
pub struct QueryRoot(content::ContentQuery, auth::AuthQuery);

/// Root mutation object (federated)
///
/// Each mutation type (ContentMutation, AuthMutation) must:
/// - Implement #[Object] on their impl block
/// - Have #[derive(Default)] on the struct
/// - Be owned types (not references) in the MergedObject tuple
///
/// Note: user::UserMutation temporarily disabled - user-service is deprecated
#[derive(MergedObject, Default)]
pub struct MutationRoot(auth::AuthMutation, content::ContentMutation);

/// GraphQL App Schema type with WebSocket subscriptions
pub type AppSchema = Schema<QueryRoot, MutationRoot, subscription::SubscriptionRoot>;

/// Build federated GraphQL schema with subscriptions and DataLoaders
/// ✅ P0-5: DataLoaders prevent N+1 queries by batching database loads
/// ✅ P0-2: Security extensions (complexity limits, request budget, persisted queries)
pub fn build_schema(clients: ServiceClients) -> AppSchema {
    // Load security config from environment
    let security_config = SecurityConfig::from_env().unwrap_or_default();

    tracing::info!(
        max_complexity = security_config.max_complexity,
        max_depth = security_config.max_depth,
        max_backend_calls = security_config.max_backend_calls,
        allow_introspection = security_config.allow_introspection,
        use_persisted_queries = security_config.use_persisted_queries,
        allow_arbitrary_queries = security_config.allow_arbitrary_queries,
        enable_apq = security_config.enable_apq,
        "GraphQL security extensions enabled"
    );

    let schema_builder = Schema::build(
        QueryRoot::default(),
        MutationRoot::default(),
        subscription::SubscriptionRoot,
    )
    .data(clients)
    // ✅ P0-5: Add DataLoaders for batch loading
    // DataLoaders prevent N+1 queries by batching database requests
    // UserIdLoader temporarily disabled - user-service is deprecated
    // .data(DataLoader::new(
    //     loaders::UserIdLoader::new(),
    //     tokio::task::spawn,
    // ))
    .data(DataLoader::new(
        loaders::PostIdLoader::new(),
        tokio::task::spawn,
    ))
    .data(DataLoader::new(
        loaders::IdCountLoader::new(),
        tokio::task::spawn,
    ))
    .data(DataLoader::new(
        loaders::LikeCountLoader::new(),
        tokio::task::spawn,
    ))
    // FollowCountLoader temporarily disabled - user-service is deprecated
    // .data(DataLoader::new(
    //     loaders::FollowCountLoader::new(),
    //     tokio::task::spawn,
    // ))
    // ✅ P0-2: Security extensions
    .extension(ComplexityLimit::new(
        security_config.max_complexity,
        security_config.max_depth,
    ))
    .extension(RequestBudget::new(security_config.max_backend_calls));

    // Note: Persisted Queries are implemented as actix-web middleware
    // See middleware/persisted_queries.rs for implementation

    // Disable introspection in production
    if !security_config.allow_introspection {
        tracing::warn!("GraphQL introspection DISABLED for production security");
        schema_builder
            .enable_federation()
            .disable_introspection()
            .finish()
    } else {
        tracing::warn!("GraphQL introspection ENABLED (development only)");
        schema_builder.enable_federation().finish()
    }
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
