# Migration Cleanup Status - Phase 8.6

## Overview
User-service migrations have been reorganized to reflect microservices decomposition. Migrations are retained for backward compatibility but documented for their new service locations.

## Migration Status by Domain

### ✅ CORE USER SERVICE (Keep - Active)
These migrations manage core user account and relationship data:
- `001_initial_schema.sql` - Core user, profile tables
- `004_social_graph_schema.sql` - Relationships (follow/unfollow)
- `005_add_deleted_at_to_users.sql` - Soft delete support
- `024_add_privacy_mode.sql` - Privacy settings
- `026_graph_optimizations.sql` - Performance optimizations
- `028_add_user_profile_fields.sql` - User profile enhancements
- `030_database_optimization.sql` - General DB optimization
- `080_performance_optimization_p0.sql` - Performance tuning

### ⚠️  MOVED TO AUTH-SERVICE (Port 8084)
These migrations handle authentication - now managed by auth-service:
- `002_add_auth_logs.sql` - Auth activity logging
- `006_add_two_factor_auth.sql` - 2FA/TOTP support
- `010_jwt_key_rotation.sql` - JWT key management
- `025_jwt_signing_keys_pg.sql` - JWT keys storage
- `038_oauth_encrypted_tokens.sql` - OAuth token encryption

**Status**: Migrations retained for backward compatibility. Auth data should be synced to auth-service PostgreSQL instance during cutover.

### ⚠️  MOVED TO CONTENT-SERVICE (Port 8081)
These migrations handle posts and user-generated content:
- `003_posts_schema.sql` - Posts table and indexes
- `027_post_video_association.sql` - Post-video linking
- `052_add_post_share_and_bookmark.sql` - Post interactions

**Status**: Migrations retained. Post data should be migrated to content-service via CDC during cutover.

### ⚠️  MOVED TO MEDIA-SERVICE (Port 8082)
These migrations handle video, uploads, and transcoding:
- `007_video_schema_postgres.sql` - Video metadata
- `011_videos_table.sql` - Videos table
- `020_video_pipeline_state.sql` - Transcoding state
- `021_video_embeddings_pgvector.sql` - Vector embeddings (pgvector)
- `022_video_schema_postgres_fix.sql` - Schema corrections
- `032_transcoding_progress_enhancements.sql` - Transcoding tracking
- `034_resumable_uploads.sql` - Upload resumption
- `040_reels_schema.sql` - Reels/short videos

**Status**: Migrations retained. Video data should be migrated to media-service via CDC during cutover.

### ⚠️  MOVED TO FEED-SERVICE (Port 8089)
These migrations handle feed, trending, and experiments:
- `033_experiments_schema.sql` - A/B experiment tracking
- `035_trending_system.sql` - Trending content tracking

**Status**: Migrations retained. Experiment/trending data should be synced to feed-service during cutover.

### ⚠️  MOVED TO MESSAGING-SERVICE (Port 8085)
These migrations handle messaging and conversations:
- `012_streaming_extensions.sql` - LiveView/WebSocket
- `013_streaming_stream_table.sql` - Stream sessions
- `014_streaming_stream_key_table.sql` - Stream keys
- `015_streaming_viewer_session_table.sql` - Viewer tracking
- `016_streaming_metrics_table.sql` - Stream metrics
- `017_streaming_quality_level_table.sql` - Quality levels
- `018_messaging_schema.sql` - Messages and conversations
- `019_stories_schema.sql` - Stories ephemeral content
- `023_message_search_index.sql` - Message search indexes
- `029_message_reactions.sql` - Message reactions/emoji
- `031_fix_messages_schema_consistency.sql` - Schema corrections
- `039_message_recall_and_versioning.sql` - Message editing/recall
- `041_add_message_encryption.sql` - E2E encryption support
- `060_create_conversation_counters.sql` - Conversation metrics
- `061_cleanup_message_sequence_system.sql` - Sequence management
- `062_create_notification_jobs.sql` - Notification queue
- `063_create_device_keys_and_key_exchanges.sql` - Encryption keys

**Status**: Migrations retained. Messaging data should be migrated to messaging-service via CDC during cutover.

## Implementation Notes

### Why Retain Migrations?
1. **Backward Compatibility**: Existing PostgreSQL databases may have these migrations already applied
2. **Data History**: Audit trail is preserved
3. **Gradual Cutover**: Allows phased migration of services without breaking existing systems

### RUN_MIGRATIONS Behavior
```bash
# Development (auto-run):
RUN_MIGRATIONS=true cargo run

# Production (disabled to prevent conflicts):
RUN_MIGRATIONS=false ./user-service
```

### Data Migration Strategy
1. **Phase 1**: New services run independently with their own PostgreSQL instances
2. **Phase 2**: CDC pipelines sync data from legacy user-service tables
3. **Phase 3**: Once new services are stable, users are switched via API Gateway routing
4. **Phase 4**: Legacy tables can be archived/dropped after retention period

## Cleanup Checklist

- [x] Migrations categorized by domain
- [x] Service migration destinations documented
- [x] Backward compatibility plan established
- [ ] Data migration scripts created per service
- [ ] CDC pipeline validation completed
- [ ] Cutover runbook prepared
- [ ] Rollback procedures documented

---

**Last Updated**: 2024-10-30  
**Phase**: 8.6 - Migration Cleanup (Documentation)
