use axum::{extract::{ws::{WebSocketUpgrade, WebSocket, Message}, State, Query}, response::IntoResponse};
use futures_util::{StreamExt, SinkExt};
use serde::Deserialize;
use uuid::Uuid;
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct WsParams { pub conversation_id: Uuid, pub user_id: Uuid }

pub async fn ws_handler(
    State(state): State<AppState>,
    Query(params): Query<WsParams>,
    ws: WebSocketUpgrade,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_socket(state, params, socket))
}

async fn handle_socket(state: AppState, params: WsParams, mut socket: WebSocket) {
    // Subscribe to conversation and split socket
    let mut rx = state.registry.add_subscriber(params.conversation_id).await;
    let (mut sender, mut receiver) = socket.split();

    // Single loop to multiplex outgoing (rx) and incoming (receiver)
    loop {
        tokio::select! {
            maybe = rx.recv() => {
                match maybe {
                    Some(msg) => { if sender.send(msg).await.is_err() { break; } }
                    None => break,
                }
            }
            incoming = receiver.next() => {
                match incoming {
                    Some(Ok(Message::Text(txt))) => {
                        let _ = state.registry.broadcast(params.conversation_id, Message::Text(txt)).await;
                    }
                    Some(Ok(Message::Ping(data))) => { let _ = sender.send(Message::Pong(data)).await; }
                    Some(Ok(Message::Close(_))) | None => break,
                    _ => {}
                }
            }
        }
    }
}
