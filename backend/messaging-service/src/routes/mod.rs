use axum::{routing::{get, post, put, delete}, Router};
use crate::state::AppState;
pub mod conversations;
use conversations::{create_conversation, get_conversation, mark_as_read};
pub mod messages;
use messages::{send_message, get_message_history, update_message, delete_message, search_messages};
pub mod groups;
use groups::{add_member, remove_member, update_member_role};
pub mod reactions;
use reactions::{add_reaction, remove_reaction, get_reactions};
pub mod attachments;
use attachments::{upload_attachment, get_attachments, delete_attachment};
pub mod wsroute;
use wsroute::ws_handler;

pub fn build_router() -> Router<AppState> {
    let router = Router::new()
        .route("/health", get(|| async { "OK" }))
        .route("/conversations", post(create_conversation))
        .route("/conversations/:id", get(get_conversation))
        .route("/conversations/:id/messages", post(send_message))
        .route("/conversations/:id/messages", get(get_message_history))
        .route("/conversations/:id/messages/search", get(search_messages))
        .route("/conversations/:id/read", post(mark_as_read))
        // Group management routes
        .route("/conversations/:id/members", post(add_member))
        .route("/conversations/:id/members/:user_id", delete(remove_member))
        .route("/conversations/:id/members/:user_id", put(update_member_role))
        // Message reactions routes
        .route("/messages/:id/reactions", post(add_reaction))
        .route("/messages/:id/reactions", get(get_reactions))
        .route("/messages/:id/reactions/:user_id", delete(remove_reaction))
        // File attachments routes
        .route("/conversations/:id/messages/:message_id/attachments", post(upload_attachment))
        .route("/messages/:id/attachments", get(get_attachments))
        .route("/messages/:id/attachments/:attachment_id", delete(delete_attachment))
        .route("/messages/:id", put(update_message))
        .route("/messages/:id", delete(delete_message))
        .route("/ws", get(ws_handler));

    crate::middleware::with_defaults(router)
}
