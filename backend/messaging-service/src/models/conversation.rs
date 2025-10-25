use serde::{Deserialize, Serialize};
use uuid::Uuid;
use chrono::{DateTime, Utc};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ConversationType { Direct, Group }

/// Marker trait for privacy modes - ensures type safety
/// This prevents mixing E2E and Searchable logic at compile time
pub trait PrivacyMarker: Send + Sync + 'static {
    fn mode_name() -> &'static str;
}

/// Strict E2E: Messages are encrypted, never indexed, admins cannot read
#[derive(Debug, Clone, Copy)]
pub struct StrictE2E;

impl PrivacyMarker for StrictE2E {
    fn mode_name() -> &'static str {
        "strict_e2e"
    }
}

/// Search-enabled: Messages can be indexed after server-side decryption
#[derive(Debug, Clone, Copy)]
pub struct SearchEnabled;

impl PrivacyMarker for SearchEnabled {
    fn mode_name() -> &'static str {
        "search_enabled"
    }
}

/// Generic conversation that enforces privacy mode at compile time
/// This prevents accidental mixing of E2E and searchable logic
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Conversation<T: PrivacyMarker> {
    pub id: Uuid,
    pub kind: ConversationType,
    pub name: Option<String>,
    pub member_count: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
    // Phantom ensures T is used
    #[serde(skip)]
    _privacy: std::marker::PhantomData<T>,
}

// Concrete types for easier use
pub type StrictE2EConversation = Conversation<StrictE2E>;
pub type SearchableConversation = Conversation<SearchEnabled>;

impl<T: PrivacyMarker> Conversation<T> {
    pub fn new(id: Uuid, kind: ConversationType, name: Option<String>, member_count: i32) -> Self {
        let now = Utc::now();
        Self {
            id,
            kind,
            name,
            member_count,
            created_at: now,
            updated_at: now,
            _privacy: std::marker::PhantomData,
        }
    }

    pub fn privacy_mode(&self) -> &'static str {
        T::mode_name()
    }
}

/// Enum for storing conversations - single source of truth
/// This ensures we don't accidentally mix privacy modes in storage
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "privacy_mode")]
pub enum ConversationData {
    #[serde(rename = "strict_e2e")]
    StrictE2E {
        id: Uuid,
        kind: ConversationType,
        name: Option<String>,
        member_count: i32,
        created_at: DateTime<Utc>,
        updated_at: DateTime<Utc>,
    },
    #[serde(rename = "search_enabled")]
    SearchEnabled {
        id: Uuid,
        kind: ConversationType,
        name: Option<String>,
        member_count: i32,
        created_at: DateTime<Utc>,
        updated_at: DateTime<Utc>,
        // Only SearchEnabled conversations have this
        admin_key_version: i32,
    },
}

impl ConversationData {
    pub fn from_db_row(
        id: Uuid,
        kind: &str,
        name: Option<String>,
        member_count: i32,
        privacy_mode: &str,
        admin_key_version: Option<i32>,
        created_at: DateTime<Utc>,
        updated_at: DateTime<Utc>,
    ) -> Self {
        let conversation_type = match kind {
            "direct" => ConversationType::Direct,
            "group" => ConversationType::Group,
            _ => ConversationType::Direct,
        };

        match privacy_mode {
            "strict_e2e" => ConversationData::StrictE2E {
                id,
                kind: conversation_type,
                name,
                member_count,
                created_at,
                updated_at,
            },
            "search_enabled" => ConversationData::SearchEnabled {
                id,
                kind: conversation_type,
                name,
                member_count,
                created_at,
                updated_at,
                admin_key_version: admin_key_version.unwrap_or(1),
            },
            _ => ConversationData::StrictE2E {
                id,
                kind: conversation_type,
                name,
                member_count,
                created_at,
                updated_at,
            },
        }
    }

    pub fn is_searchable(&self) -> bool {
        matches!(self, ConversationData::SearchEnabled { .. })
    }

    pub fn is_strict_e2e(&self) -> bool {
        matches!(self, ConversationData::StrictE2E { .. })
    }

    pub fn id(&self) -> Uuid {
        match self {
            ConversationData::StrictE2E { id, .. } => *id,
            ConversationData::SearchEnabled { id, .. } => *id,
        }
    }
}

