use actix_web::{web, App, HttpServer};
use async_graphql::{EmptyMutation, EmptySubscription, Schema};
use async_graphql_actix_web::{GraphQLRequest, GraphQLResponse};
use tracing::info;

mod config;

// Temporary empty query root until full implementation
#[derive(Default)]
struct QueryRoot;

#[async_graphql::Object]
impl QueryRoot {
    async fn health(&self) -> &str {
        "ok"
    }
}

type AppSchema = Schema<QueryRoot, EmptyMutation, EmptySubscription>;

async fn graphql_handler(
    schema: web::Data<AppSchema>,
    req: GraphQLRequest,
) -> GraphQLResponse {
    schema.execute(req.into_inner()).await.into()
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_env_filter("info")
        .init();

    info!("Starting GraphQL Gateway...");

    // Build GraphQL schema
    let schema = Schema::build(QueryRoot::default(), EmptyMutation, EmptySubscription)
        .finish();

    info!("GraphQL Gateway starting on http://0.0.0.0:8080");

    // Start HTTP server
    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(schema.clone()))
            .route("/graphql", web::post().to(graphql_handler))
            .route("/health", web::get().to(|| async { "ok" }))
    })
    .bind("0.0.0.0:8080")?
    .run()
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_health_query() {
        let schema = Schema::build(QueryRoot::default(), EmptyMutation, EmptySubscription)
            .finish();

        let query = "{ health }";
        let result = schema.execute(query).await;

        assert!(result.errors.is_empty());
        assert_eq!(result.data.to_string(), r#"{health: "ok"}"#);
    }
}
