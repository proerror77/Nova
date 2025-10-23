use axum::{routing::{get, post, put, delete}, Router};
use crate::state::AppState;
pub mod conversations;
use conversations::{create_conversation, get_conversation};
pub mod messages;
use messages::{send_message, get_message_history, update_message, delete_message};
pub mod wsroute;
use wsroute::ws_handler;

pub fn build_router() -> Router<AppState> {
    Router::new()
        .route("/health", get(|| async { "OK" }))
        .route("/conversations", post(create_conversation))
        .route("/conversations/:id", get(get_conversation))
        .route("/conversations/:id/messages", post(send_message))
        .route("/conversations/:id/messages", get(get_message_history))
        .route("/messages/:id", put(update_message))
        .route("/messages/:id", delete(delete_message))
        .route("/ws", get(ws_handler))
}
