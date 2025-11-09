//! GraphQL Schema with Federation support

pub mod user;
pub mod content;
pub mod auth;

use async_graphql::{
    Context, EmptySubscription, MergedObject, Object, Schema, SchemaBuilder,
};

use crate::clients::ServiceClients;

/// Root query object (federated)
#[derive(MergedObject, Default)]
pub struct QueryRoot(user::UserQuery, content::ContentQuery, auth::AuthQuery);

/// Root mutation object (federated)
#[derive(MergedObject, Default)]
pub struct MutationRoot(user::UserMutation, content::ContentMutation, auth::AuthMutation);

/// Build federated GraphQL schema
pub fn build_schema(clients: ServiceClients) -> Schema<QueryRoot, MutationRoot, EmptySubscription> {
    Schema::build(
        QueryRoot::default(),
        MutationRoot::default(),
        EmptySubscription,
    )
    .data(clients)
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
