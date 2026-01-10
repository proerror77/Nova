use anyhow::{anyhow, Context as _, Result};
use chrono::{DateTime, TimeZone as _, Utc};
use matrix_sdk::room::MessagesOptions;
use matrix_sdk::ruma::events::room::encrypted::Relation as EncryptedRelation;
use matrix_sdk::ruma::events::room::message::Relation as MessageRelation;
use matrix_sdk::ruma::events::{AnySyncMessageLikeEvent, AnySyncTimelineEvent};
use matrix_sdk::ruma::{MilliSecondsSinceUnixEpoch, OwnedRoomId, RoomId, UInt};
use realtime_chat_service::config::Config;
use realtime_chat_service::services::matrix_admin::{AdminCredentials, MatrixAdminClient};
use realtime_chat_service::services::matrix_client::MatrixClient;
use realtime_chat_service::services::matrix_user::extract_nova_user_id_from_matrix;
use realtime_chat_service::services::message_service::{MatrixMessageMetadata, MessageService};
use realtime_chat_service::{db, services::matrix_db};
use std::env;
use tracing::{info, warn};
use uuid::Uuid;

#[derive(Debug)]
struct Args {
    all: bool,
    conversation_id: Option<Uuid>,
    room_id: Option<String>,
    page_size: u64,
    max_events: Option<u64>,
    resequence: bool,
}

impl Default for Args {
    fn default() -> Self {
        Self {
            all: false,
            conversation_id: None,
            room_id: None,
            page_size: 500,
            max_events: None,
            resequence: true,
        }
    }
}

fn ts_to_utc(ts: Option<MilliSecondsSinceUnixEpoch>) -> DateTime<Utc> {
    let Some(ts) = ts else {
        return Utc::now();
    };

    let ms: i64 = ts.get().into();
    Utc.timestamp_millis_opt(ms).single().unwrap_or_else(Utc::now)
}

fn parse_args() -> Result<Args> {
    let mut args = Args::default();
    let mut it = env::args().skip(1);

    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--all" => args.all = true,
            "--no-resequence" => args.resequence = false,
            "--conversation" => {
                let v = it.next().ok_or_else(|| anyhow!("--conversation requires a UUID"))?;
                args.conversation_id = Some(Uuid::parse_str(&v).context("invalid --conversation UUID")?);
            }
            "--room" => {
                let v = it.next().ok_or_else(|| anyhow!("--room requires a Matrix room id"))?;
                args.room_id = Some(v);
            }
            "--page-size" => {
                let v = it.next().ok_or_else(|| anyhow!("--page-size requires a number"))?;
                args.page_size = v.parse().context("invalid --page-size")?;
            }
            "--max-events" => {
                let v = it.next().ok_or_else(|| anyhow!("--max-events requires a number"))?;
                args.max_events = Some(v.parse().context("invalid --max-events")?);
            }
            "--help" | "-h" => {
                println!(
                    "\
matrix-backfill

Backfill Matrix history into Nova DB as metadata-only rows (matrix_event_id + sender_id + created_at).

Usage:
  matrix-backfill --all [--page-size N] [--max-events N] [--no-resequence]
  matrix-backfill --conversation <uuid> [--page-size N] [--max-events N] [--no-resequence]
  matrix-backfill --room <room_id> [--page-size N] [--max-events N] [--no-resequence]
"
                );
                std::process::exit(0);
            }
            other => return Err(anyhow!("Unknown arg: {other}")),
        }
    }

    let selected = args.all as u8 + args.conversation_id.is_some() as u8 + args.room_id.is_some() as u8;
    if selected != 1 {
        return Err(anyhow!(
            "Select exactly one: --all | --conversation <uuid> | --room <room_id>"
        ));
    }

    if args.page_size == 0 {
        return Err(anyhow!("--page-size must be > 0"));
    }

    Ok(args)
}

fn should_ingest(raw: &matrix_sdk::ruma::serde::Raw<AnySyncTimelineEvent>) -> bool {
    let event_type = raw.get_field::<String>("type").ok().flatten();
    match event_type.as_deref() {
        Some("m.room.message") => match raw.deserialize() {
            Ok(AnySyncTimelineEvent::MessageLike(AnySyncMessageLikeEvent::RoomMessage(ev))) => ev
                .as_original()
                .is_some_and(|o| !matches!(o.content.relates_to, Some(MessageRelation::Replacement(_)))),
            _ => false,
        },
        Some("m.room.encrypted") => match raw.deserialize() {
            Ok(AnySyncTimelineEvent::MessageLike(AnySyncMessageLikeEvent::RoomEncrypted(ev))) => ev
                .as_original()
                .is_some_and(|o| !matches!(o.content.relates_to, Some(EncryptedRelation::Replacement(_)))),
            _ => false,
        },
        _ => false,
    }
}

async fn backfill_one(
    cfg: &Config,
    db_pool: &deadpool_postgres::Pool,
    matrix: &MatrixClient,
    admin: Option<&MatrixAdminClient>,
    conversation_id: Uuid,
    room_id: &RoomId,
    args: &Args,
) -> Result<()> {
    if let Some(admin) = admin {
        if let Err(e) = admin.join_room_as_user(room_id.as_str(), &cfg.matrix.service_user).await {
            warn!(error = %e, room_id = %room_id, "Admin join failed; continuing anyway");
        }
    }

    let room = matrix
        .get_or_join_room(room_id)
        .await
        .with_context(|| format!("get/join room: {room_id}"))?;

    let mut from: Option<String> = None;
    let mut total_seen: u64 = 0;
    let mut total_inserted: u64 = 0;

    loop {
        let mut opts = MessagesOptions::forward();
        opts.from = from.clone();
        opts.limit = UInt::new(args.page_size).unwrap_or_else(|| UInt::new(100).unwrap());

        let messages = room.messages(opts).await.context("room.messages")?;
        from = messages.end.clone();

        let mut batch: Vec<MatrixMessageMetadata> = Vec::new();
        for ev in messages.chunk {
            if args.max_events.is_some_and(|m| total_seen >= m) {
                break;
            }

            total_seen += 1;

            if !should_ingest(ev.kind.raw()) {
                continue;
            }

            let Some(event_id) = ev.kind.event_id() else {
                continue;
            };

            let Some(sender) = ev.kind.raw().get_field("sender").ok().flatten() else {
                continue;
            };

            let Some(sender_id) = extract_nova_user_id_from_matrix(&sender) else {
                continue;
            };

            batch.push(MatrixMessageMetadata {
                sender_id,
                matrix_event_id: event_id.to_string(),
                created_at: ts_to_utc(ev.timestamp),
            });
        }

        let inserted =
            MessageService::store_matrix_message_metadata_batch_db(db_pool, conversation_id, &batch)
                .await
                .context("store batch")?;
        total_inserted += inserted;

        info!(
            conversation_id = %conversation_id,
            room_id = %room_id,
            seen = total_seen,
            inserted = total_inserted,
            "Backfill progress"
        );

        if args.max_events.is_some_and(|m| total_seen >= m) {
            break;
        }

        if from.is_none() {
            break;
        }
    }

    if args.resequence {
        MessageService::resequence_conversation_messages_db(db_pool, conversation_id)
            .await
            .context("resequence conversation")?;
    }

    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .init();

    let args = parse_args()?;
    let cfg = Config::from_env().context("load config")?;

    let db_pool = db::init_pool(&cfg.database_url).await.context("init db pool")?;
    let matrix = MatrixClient::new(cfg.matrix.clone()).await.context("init matrix client")?;

    let admin = cfg.matrix.admin_token.clone().map(|token| {
        let creds = match (cfg.matrix.admin_username.clone(), cfg.matrix.admin_password.clone()) {
            (Some(username), Some(password)) => Some(AdminCredentials { username, password }),
            _ => None,
        };
        MatrixAdminClient::new(
            cfg.matrix.homeserver_url.clone(),
            token,
            cfg.matrix.server_name.clone(),
            creds,
        )
    });

    let targets: Vec<(Uuid, OwnedRoomId)> = if args.all {
        matrix_db::load_all_room_mappings(&db_pool)
            .await
            .context("load all room mappings")?
    } else if let Some(conversation_id) = args.conversation_id {
        let room_id = matrix_db::load_room_mapping(&db_pool, conversation_id)
            .await
            .context("load room mapping")?
            .ok_or_else(|| anyhow!("No matrix_room_mapping for conversation {conversation_id}"))?;
        vec![(conversation_id, room_id)]
    } else {
        let room_str = args.room_id.clone().expect("validated");
        let room_id =
            OwnedRoomId::try_from(room_str.clone()).map_err(|e| anyhow!("Invalid room id {room_str}: {e}"))?;
        let conversation_id = matrix_db::lookup_conversation_by_room_id(&db_pool, room_id.as_str())
            .await
            .context("lookup conversation by room")?
            .ok_or_else(|| anyhow!("No conversation mapping for room {room_id}"))?;
        vec![(conversation_id, room_id)]
    };

    info!("Starting backfill for {} room(s)", targets.len());
    for (conversation_id, room_id) in targets {
        info!(conversation_id = %conversation_id, room_id = %room_id, "Backfilling room");
        backfill_one(
            &cfg,
            &db_pool,
            &matrix,
            admin.as_ref(),
            conversation_id,
            &room_id,
            &args,
        )
        .await
        .with_context(|| format!("backfill failed for conversation={conversation_id} room={room_id}"))?;
    }

    Ok(())
}

