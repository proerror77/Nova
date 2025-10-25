use redis::AsyncCommands;
use redis::Client;
use crate::websocket::ConnectionRegistry;
use uuid::Uuid;
use axum::extract::ws::Message;

fn channel_for_conversation(id: Uuid) -> String { format!("conversation:{}", id) }

pub async fn publish(client: &Client, conversation_id: Uuid, payload: &str) -> redis::RedisResult<()> {
    let mut conn = client.get_multiplexed_async_connection().await?;
    let ch = channel_for_conversation(conversation_id);
    conn.publish::<_, _, ()>(ch, payload).await
}

pub async fn start_psub_listener(client: Client, registry: ConnectionRegistry) -> redis::RedisResult<()> {
    // PubSub requires a dedicated connection, not multiplexed
    let conn = client.get_async_connection().await?;
    let mut pubsub = conn.into_pubsub();
    pubsub.psubscribe("conversation:*").await?;
    let mut stream = pubsub.on_message();
    use futures_util::StreamExt;
    while let Some(msg) = stream.next().await {
        let channel: String = msg.get_channel_name().into();
        let payload: String = msg.get_payload()?;
        if let Some(rest) = channel.strip_prefix("conversation:") {
            // Accept both `conversation:<uuid>` and `conversation:<uuid>:<suffix>`
            let id_part = rest.split(':').next().unwrap_or(rest);
            if let Ok(uuid) = Uuid::parse_str(id_part) {
                registry.broadcast(uuid, Message::Text(payload.clone())).await;
            }
        }
    }
    Ok(())
}
