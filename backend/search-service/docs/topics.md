## Kafka Topics & Schemas (Search Service)

- message_persisted: { message_id, conversation_id, sender_id, content (if search_enabled), created_at }
- message_deleted: { message_id, conversation_id, deleted_at }
- reaction_added: { target_type: "message"|"story", target_id, user_id, emoji, created_at }
- reaction_removed: { target_type, target_id, user_id, emoji, removed_at }
- mention_created: { conversation_id, message_id, mentioned_user_id, created_at }

Notes:
- Strict E2E conversations are excluded from indexing. Producers MUST NOT include plaintext content for E2E conversations.
- Schemas to be formalized via schema registry in future iteration.
