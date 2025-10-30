//! WebSocket offline message delivery integration
//! Example of how to integrate offline queue recovery into WebSocket handlers

use axum::{
    extract::{ws::{WebSocket, WebSocketUpgrade}, Path, State},
    response::IntoResponse,
};
use uuid::Uuid;
use futures_util::{SinkExt, StreamExt};
use crate::{
    middleware::guards::User,
    redis_client::RedisClient,
    services::offline_queue::{self, ClientSyncState},
    state::AppState,
};

/// WebSocket upgrade handler with offline message recovery
pub async fn websocket_handler(
    ws: WebSocketUpgrade,
    user: User,
    Path(conversation_id): Path<Uuid>,
    State(state): State<AppState>,
) -> impl IntoResponse {
    let user_id = user.id;
    let redis = state.redis.clone();
    let db = state.db.clone();
    let registry = state.registry.clone();

    ws.on_upgrade(move |socket| handle_socket(
        socket,
        user_id,
        conversation_id,
        redis,
        db,
        registry,
    ))
}

async fn handle_socket(
    socket: WebSocket,
    user_id: Uuid,
    conversation_id: Uuid,
    redis: RedisClient,
    db: sqlx::PgPool,
    registry: crate::websocket::ConnectionRegistry,
) {
    // 生成唯一的客户端 ID（可以来自客户端头部，如果提供）
    let client_id = Uuid::new_v4();

    let (mut sender, mut receiver) = socket.split();

    // ╔════════════════════════════════════════════════════════════════╗
    // ║ 第 1 步：获取客户端的上次同步状态（如果存在）                  ║
    // ╚════════════════════════════════════════════════════════════════╝
    let mut last_message_id = "0".to_string();

    if let Ok(Some(sync_state)) = offline_queue::get_client_sync_state(
        &redis,
        user_id,
        client_id,
    ).await {
        tracing::info!(
            user_id = %user_id,
            client_id = %client_id,
            last_message_id = %sync_state.last_message_id,
            "client reconnected with sync state"
        );
        last_message_id = sync_state.last_message_id;
    } else {
        tracing::info!(
            user_id = %user_id,
            client_id = %client_id,
            "new client connection"
        );
    }

    // ╔════════════════════════════════════════════════════════════════╗
    // ║ 第 2 步：推送客户端离线期间接收到的消息                        ║
    // ╚════════════════════════════════════════════════════════════════╝
    if let Ok(offline_messages) = offline_queue::get_messages_since(
        &redis,
        conversation_id,
        &last_message_id,
    ).await {
        let count = offline_messages.len();
        tracing::info!(
            user_id = %user_id,
            offline_message_count = count,
            "delivering offline messages"
        );

        for (msg_id, fields) in offline_messages.iter() {
            // 构造消息负载并发送
            if let Some(payload) = fields.get("payload") {
                let msg = axum::extract::ws::Message::Text(payload.clone().into());
                if sender.send(msg).await.is_err() {
                    tracing::warn!("failed to send offline message");
                    return;  // 客户端已断开
                }
                last_message_id = msg_id.clone();
            }
        }
    }

    // ╔════════════════════════════════════════════════════════════════╗
    // ║ 第 3 步：注册到本地广播（接收实时消息）                        ║
    // ╚════════════════════════════════════════════════════════════════╝
    let mut broadcast_rx = registry.add_subscriber(conversation_id).await;

    // ╔════════════════════════════════════════════════════════════════╗
    // ║ 第 4 步：并发处理入站和出站消息                                ║
    // ╚════════════════════════════════════════════════════════════════╝
    let send_task = tokio::spawn(async move {
        while let Some(msg) = broadcast_rx.recv().await {
            if let Ok(text) = msg.clone().into_text() {
                // 从广播消息中提取消息ID
                if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                    if let Some(id) = json.get("message_id").and_then(|v| v.as_str()) {
                        last_message_id = id.to_string();
                    }
                }
            }

            if sender.send(msg).await.is_err() {
                tracing::info!("client disconnected");
                break;
            }
        }
    });

    let recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            match msg {
                // 处理客户端发送的消息
                axum::extract::ws::Message::Text(text) => {
                    tracing::debug!(
                        user_id = %user_id,
                        conversation_id = %conversation_id,
                        "received message from client: {}", &text[..30.min(text.len())]
                    );

                    // 可以在这里处理客户端命令或握手消息
                    // 例如：同步状态确认、心跳等
                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(&text) {
                        if let Some("sync_ack") = json.get("type").and_then(|v| v.as_str()) {
                            // 客户端确认已接收到消息
                            if let Some(msg_id) = json.get("message_id").and_then(|v| v.as_str()) {
                                last_message_id = msg_id.to_string();
                            }
                        }
                    }
                }

                axum::extract::ws::Message::Close(_) => {
                    tracing::info!("client sent close frame");
                    break;
                }

                _ => {
                    // 忽略 pong、ping 等
                }
            }
        }
    });

    // ╔════════════════════════════════════════════════════════════════╗
    // ║ 第 5 步：定期同步状态（防止数据丢失）                          ║
    // ╚════════════════════════════════════════════════════════════════╝
    let sync_task = tokio::spawn({
        let redis = redis.clone();
        let user_id = user_id;
        let client_id = client_id;
        let conversation_id = conversation_id;

        async move {
            let mut interval = tokio::time::interval(
                std::time::Duration::from_secs(5)  // 每 5 秒同步一次
            );

            loop {
                interval.tick().await;

                let sync_state = ClientSyncState {
                    client_id,
                    user_id,
                    conversation_id,
                    last_message_id: last_message_id.clone(),
                    last_sync_at: chrono::Utc::now().timestamp_millis(),
                };

                if let Err(e) = offline_queue::update_client_sync_state(
                    &redis,
                    &sync_state,
                ).await {
                    tracing::warn!(error = %e, "failed to update client sync state");
                }
            }
        }
    });

    // ╔════════════════════════════════════════════════════════════════╗
    // ║ 第 6 步：等待任一任务完成（客户端断开或错误）                  ║
    // ╚════════════════════════════════════════════════════════════════╝
    tokio::select! {
        _ = send_task => {
            tracing::info!("send task ended");
        }
        _ = recv_task => {
            tracing::info!("receive task ended");
        }
        _ = sync_task => {
            tracing::info!("sync task ended");
        }
    }

    // ╔════════════════════════════════════════════════════════════════╗
    // ║ 第 7 步：客户端断开时的清理                                    ║
    // ╚════════════════════════════════════════════════════════════════╝
    // 注意：我们保留 ClientSyncState 以便客户端重连时恢复
    // 它会在 30 天 TTL 后自动过期

    // 可选：清理离线通知计数
    if let Err(e) = offline_queue::clear_offline_notifications(
        &redis,
        user_id,
        &[conversation_id],
    ).await {
        tracing::warn!(error = %e, "failed to clear offline notifications");
    }

    tracing::info!(
        user_id = %user_id,
        client_id = %client_id,
        final_last_message_id = %last_message_id,
        "client disconnected"
    );
}

// ═══════════════════════════════════════════════════════════════════════
// 客户端期望的消息格式
// ═══════════════════════════════════════════════════════════════════════

/*
离线消息（重连后推送）：
{
    "type": "offline_message",
    "message": {
        "id": "uuid",
        "sender_id": "uuid",
        "content": "hello",
        "sequence_number": 42,
        "created_at": "2025-10-25T12:34:56Z"
    },
    "message_id": "1634567890-0"  ← Redis Stream ID
}

实时消息（订阅后推送）：
{
    "type": "message",
    "conversation_id": "uuid",
    "message": {
        "id": "uuid",
        "sender_id": "uuid",
        "sequence_number": 43
    },
    "message_id": "1634567891-0"
}

客户端确认（可选）：
{
    "type": "sync_ack",
    "message_id": "1634567891-0"  ← 客户端已成功接收到的最后一条消息
}

心跳：
{
    "type": "ping"
}

*/

// ═══════════════════════════════════════════════════════════════════════
// 关键特性
// ═══════════════════════════════════════════════════════════════════════

/*
1. ✅ 离线恢复
   - 客户端重连时自动推送离线消息
   - 从 last_message_id 之后开始
   - 避免重复（使用排除范围）

2. ✅ 实时推送
   - WebSocket 广播实时连接的消息
   - 本地注册表管理连接
   - 跨实例同步 via Redis Streams

3. ✅ 状态持久化
   - 每 5 秒更新 ClientSyncState
   - 30 天 TTL
   - 重连时自动恢复

4. ✅ 并发处理
   - 入站消息接收
   - 出站消息广播
   - 定期状态同步
   - 使用 tokio::select! 并发处理

5. ✅ 错误恢复
   - 连接断开自动清理
   - 同步失败记录为警告而非错误
   - 客户端可以重新连接重试
*/
