//! Handler adapter for StreamActor
//!
//! Provides convenient methods for handlers to send commands to the StreamActor
//! and await responses without dealing with oneshot channels directly.

use super::commands::StreamCommand;
use super::models::*;
use tokio::sync::mpsc;
use uuid::Uuid;

/// Generic helper to send a command and await its response
pub async fn send_command<T>(
    tx: &mpsc::Sender<StreamCommand>,
    f: impl FnOnce(tokio::sync::oneshot::Sender<anyhow::Result<T>>) -> StreamCommand,
) -> anyhow::Result<T> {
    let (responder_tx, responder_rx) = tokio::sync::oneshot::channel();
    let cmd = f(responder_tx);
    tx.send(cmd).await.map_err(|e| {
        anyhow::anyhow!("Failed to send command to stream actor: {}", e)
    })?;
    responder_rx.await.map_err(|e| {
        anyhow::anyhow!("Stream actor dropped the responder: {}", e)
    })?
}

// Convenience methods for common operations

pub async fn create_stream(
    tx: &mpsc::Sender<StreamCommand>,
    creator_id: Uuid,
    request: CreateStreamRequest,
) -> anyhow::Result<CreateStreamResponse> {
    send_command(tx, |responder| StreamCommand::CreateStream {
        creator_id,
        request,
        responder,
    })
    .await
}

pub async fn start_stream(
    tx: &mpsc::Sender<StreamCommand>,
    stream_key: &str,
) -> anyhow::Result<()> {
    send_command(tx, |responder| StreamCommand::StartStream {
        stream_key: stream_key.to_string(),
        responder,
    })
    .await
}

pub async fn end_stream(
    tx: &mpsc::Sender<StreamCommand>,
    stream_key: &str,
) -> anyhow::Result<()> {
    send_command(tx, |responder| StreamCommand::EndStream {
        stream_key: stream_key.to_string(),
        responder,
    })
    .await
}

pub async fn join_stream(
    tx: &mpsc::Sender<StreamCommand>,
    stream_id: Uuid,
    user_id: Uuid,
) -> anyhow::Result<JoinStreamResponse> {
    send_command(tx, |responder| StreamCommand::JoinStream {
        stream_id,
        user_id,
        responder,
    })
    .await
}

pub async fn leave_stream(
    tx: &mpsc::Sender<StreamCommand>,
    stream_id: Uuid,
    user_id: Uuid,
) -> anyhow::Result<()> {
    send_command(tx, |responder| StreamCommand::LeaveStream {
        stream_id,
        user_id,
        responder,
    })
    .await
}

pub async fn get_stream_details(
    tx: &mpsc::Sender<StreamCommand>,
    stream_id: Uuid,
) -> anyhow::Result<StreamDetails> {
    send_command(tx, |responder| StreamCommand::GetStreamDetails {
        stream_id,
        responder,
    })
    .await
}

pub async fn list_live_streams(
    tx: &mpsc::Sender<StreamCommand>,
    category: Option<StreamCategory>,
    page: i32,
    limit: i32,
) -> anyhow::Result<StreamListResponse> {
    send_command(tx, |responder| StreamCommand::ListLiveStreams {
        category,
        page,
        limit,
        responder,
    })
    .await
}

pub async fn post_comment(
    tx: &mpsc::Sender<StreamCommand>,
    comment: StreamComment,
) -> anyhow::Result<StreamComment> {
    send_command(tx, |responder| StreamCommand::PostComment { comment, responder }).await
}

pub async fn recent_comments(
    tx: &mpsc::Sender<StreamCommand>,
    stream_id: Uuid,
    limit: usize,
) -> anyhow::Result<Vec<StreamComment>> {
    send_command(tx, |responder| StreamCommand::RecentComments {
        stream_id,
        limit,
        responder,
    })
    .await
}
