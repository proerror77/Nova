use uuid::Uuid;
use sqlx::{Pool, Postgres, Row};

pub struct ConversationDetails {
    pub id: Uuid,
    pub member_count: i32,
    pub last_message_id: Option<Uuid>,
}

pub struct ConversationService;

impl ConversationService {
    pub async fn create_direct_conversation(db: &Pool<Postgres>, a: Uuid, b: Uuid) -> Result<Uuid, crate::error::AppError> {
        let id = Uuid::new_v4();
        let mut tx = db.begin().await.map_err(|e| crate::error::AppError::StartServer(format!("tx: {e}")))?;
        // kind: 'direct'
        sqlx::query(
            "INSERT INTO conversations (id, kind, member_count) VALUES ($1, 'direct', 2)"
        )
        .bind(id)
        .execute(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert conversation: {e}")))?;
        sqlx::query(
            "INSERT INTO conversation_members (conversation_id, user_id, role) VALUES ($1, $2, 'member'), ($1, $3, 'member')"
        )
        .bind(id)
        .bind(a)
        .bind(b)
        .execute(&mut *tx)
        .await
        .map_err(|e| crate::error::AppError::StartServer(format!("insert members: {e}")))?;
        tx.commit().await.map_err(|e| crate::error::AppError::StartServer(format!("commit: {e}")))?;
        Ok(id)
    }

    pub async fn get_conversation_db(db: &Pool<Postgres>, id: Uuid) -> Result<ConversationDetails, crate::error::AppError> {
        let r = sqlx::query("SELECT id, member_count, last_message_id FROM conversations WHERE id = $1")
            .bind(id)
            .fetch_one(db)
            .await
            .map_err(|e| crate::error::AppError::StartServer(format!("get conversation: {e}")))?;
        let id: Uuid = r.get("id");
        let member_count: i32 = r.get("member_count");
        let last_message_id: Option<Uuid> = r.try_get("last_message_id").ok();
        Ok(ConversationDetails { id, member_count, last_message_id })
    }

    pub async fn list_conversations(_user_id: Uuid) -> Result<Vec<Uuid>, crate::error::AppError> {
        Err(crate::error::AppError::Config("not implemented".into()))
    }
}
