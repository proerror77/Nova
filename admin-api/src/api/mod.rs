mod auth;
mod users;
mod content;
mod dashboard;

use axum::Router;
use crate::AppState;

pub fn routes() -> Router<AppState> {
    Router::new()
        .nest("/auth", auth::routes())
        .nest("/dashboard", dashboard::routes())
        .nest("/users", users::routes())
        .nest("/content", content::routes())
}
