// gRPC server implementation for EventsService
use chrono::Utc;
use sqlx::{PgPool, Row};
use std::sync::Arc;
use tonic::{Request, Response, Status};
use tracing::{error, info, warn};
use uuid::Uuid;

pub mod nova {
    pub mod common {
        pub mod v1 {
            tonic::include_proto!("nova.common.v1");
        }
        pub use v1::*;
    }
    pub mod events_service {
        pub mod v1 {
            tonic::include_proto!("nova.events_service.v1");
        }
        pub use v1::*;
    }
}

use nova::events_service::v1::events_service_server::EventsService;
use nova::events_service::v1::*;

// Import proto-generated types with full qualification to avoid conflicts
use nova::events_service::v1::{
    DomainEvent as ProtoDomainEvent, EventSchema as ProtoEventSchema,
    EventSubscription as ProtoEventSubscription, OutboxEvent as ProtoOutboxEvent,
};

/// AppState for gRPC service
#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
}

impl AppState {
    pub fn new(db: PgPool) -> Self {
        Self { db }
    }
}

/// EventsServiceImpl - gRPC service implementation
#[derive(Clone)]
pub struct EventsServiceImpl {
    state: Arc<AppState>,
}

impl EventsServiceImpl {
    pub fn new(state: Arc<AppState>) -> Self {
        Self { state }
    }

    /// Helper: Parse UUID from string
    fn parse_uuid(uuid_str: &str, field_name: &str) -> Result<Uuid, Status> {
        uuid_str
            .parse::<Uuid>()
            .map_err(|_| Status::invalid_argument(format!("Invalid {}: {}", field_name, uuid_str)))
    }

    /// Helper: Parse JSON data
    fn parse_json(json_str: &str, field_name: &str) -> Result<serde_json::Value, Status> {
        serde_json::from_str(json_str)
            .map_err(|e| Status::invalid_argument(format!("Invalid JSON in {}: {}", field_name, e)))
    }

    /// Helper: Validate event type format (should be "domain.action")
    fn validate_event_type(event_type: &str) -> Result<(), Status> {
        if event_type.is_empty() {
            return Err(Status::invalid_argument("event_type cannot be empty"));
        }

        let parts: Vec<&str> = event_type.split('.').collect();
        if parts.len() < 2 {
            return Err(Status::invalid_argument(format!(
                "event_type must follow 'domain.action' pattern, got: {}",
                event_type
            )));
        }

        Ok(())
    }

    /// Helper: Convert database error to gRPC Status
    fn db_error_to_status(err: sqlx::Error) -> Status {
        error!("Database error: {}", err);
        match err {
            sqlx::Error::RowNotFound => Status::not_found("Resource not found"),
            sqlx::Error::Database(e) if e.is_unique_violation() => {
                Status::already_exists("Resource already exists")
            }
            _ => Status::internal(format!("Database error: {}", err)),
        }
    }
}

#[tonic::async_trait]
impl EventsService for EventsServiceImpl {
    /// Publish a single event to the outbox
    ///
    /// Process:
    /// 1. Validate request (event_type, aggregate_id, data)
    /// 2. Parse JSON data
    /// 3. Insert into outbox_events table
    /// 4. Return event metadata
    ///
    /// The OutboxPublisher will asynchronously publish to Kafka
    async fn publish_event(
        &self,
        request: Request<PublishEventRequest>,
    ) -> Result<Response<PublishEventResponse>, Status> {
        let req = request.into_inner();

        // Validate required fields
        if req.event_type.is_empty() {
            return Err(Status::invalid_argument("event_type is required"));
        }
        if req.aggregate_id.is_empty() {
            return Err(Status::invalid_argument("aggregate_id is required"));
        }
        if req.aggregate_type.is_empty() {
            return Err(Status::invalid_argument("aggregate_type is required"));
        }
        if req.data.is_empty() {
            return Err(Status::invalid_argument("data is required"));
        }

        // Validate event type format
        Self::validate_event_type(&req.event_type)?;

        // Parse JSON data
        let data = Self::parse_json(&req.data, "data")?;
        let metadata = if !req.metadata.is_empty() {
            Some(Self::parse_json(&req.metadata, "metadata")?)
        } else {
            None
        };

        // Parse optional correlation_id and causation_id
        let correlation_id = if !req.correlation_id.is_empty() {
            Some(Self::parse_uuid(&req.correlation_id, "correlation_id")?)
        } else {
            None
        };

        let causation_id = if !req.causation_id.is_empty() {
            Some(Self::parse_uuid(&req.causation_id, "causation_id")?)
        } else {
            None
        };

        // Generate event ID and timestamp
        let event_id = Uuid::new_v4();
        let created_at = Utc::now();

        // Insert into outbox_events table
        sqlx::query(
            r#"
            INSERT INTO outbox_events (
                id, event_type, aggregate_id, aggregate_type, data, metadata,
                correlation_id, causation_id, created_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            "#,
        )
        .bind(event_id)
        .bind(&req.event_type)
        .bind(&req.aggregate_id)
        .bind(&req.aggregate_type)
        .bind(&data)
        .bind(&metadata)
        .bind(correlation_id)
        .bind(causation_id)
        .bind(created_at)
        .execute(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        info!(
            "Published event {} (type: {}, aggregate: {})",
            event_id, req.event_type, req.aggregate_id
        );

        // Build response
        let domain_event = ProtoDomainEvent {
            id: event_id.to_string(),
            event_type: req.event_type,
            aggregate_id: req.aggregate_id,
            aggregate_type: req.aggregate_type,
            version: 1,
            data: req.data,
            metadata: req.metadata,
            correlation_id: correlation_id.map(|id| id.to_string()).unwrap_or_default(),
            causation_id: causation_id.map(|id| id.to_string()).unwrap_or_default(),
            created_at: created_at.timestamp(),
            created_by: "".to_string(), // TODO: Extract from auth metadata
        };

        Ok(Response::new(PublishEventResponse {
            event: Some(domain_event),
        }))
    }

    /// Publish multiple events in batch
    async fn publish_events(
        &self,
        request: Request<PublishEventsRequest>,
    ) -> Result<Response<PublishEventsResponse>, Status> {
        let req = request.into_inner();

        if req.events.is_empty() {
            return Err(Status::invalid_argument("events cannot be empty"));
        }

        let mut success_count = 0;
        let mut failed_count = 0;
        let mut published_events = Vec::new();

        // Process each event
        for event_data in req.events {
            // Validate
            if event_data.event_type.is_empty()
                || event_data.aggregate_id.is_empty()
                || event_data.aggregate_type.is_empty()
                || event_data.data.is_empty()
            {
                warn!("Skipping invalid event in batch");
                failed_count += 1;
                continue;
            }

            // Parse JSON
            let data = match Self::parse_json(&event_data.data, "data") {
                Ok(d) => d,
                Err(e) => {
                    warn!("Failed to parse event data: {}", e);
                    failed_count += 1;
                    continue;
                }
            };

            let correlation_id = if !event_data.correlation_id.is_empty() {
                Self::parse_uuid(&event_data.correlation_id, "correlation_id").ok()
            } else {
                None
            };

            // Insert into outbox
            let event_id = Uuid::new_v4();
            let created_at = Utc::now();

            match sqlx::query(
                r#"
                INSERT INTO outbox_events (
                    id, event_type, aggregate_id, aggregate_type, data,
                    correlation_id, created_at
                )
                VALUES ($1, $2, $3, $4, $5, $6, $7)
                "#,
            )
            .bind(event_id)
            .bind(&event_data.event_type)
            .bind(&event_data.aggregate_id)
            .bind(&event_data.aggregate_type)
            .bind(&data)
            .bind(correlation_id)
            .bind(created_at)
            .execute(&self.state.db)
            .await
            {
                Ok(_) => {
                    success_count += 1;
                    published_events.push(ProtoDomainEvent {
                        id: event_id.to_string(),
                        event_type: event_data.event_type,
                        aggregate_id: event_data.aggregate_id,
                        aggregate_type: event_data.aggregate_type,
                        version: 1,
                        data: event_data.data,
                        metadata: "".to_string(),
                        correlation_id: correlation_id.map(|id| id.to_string()).unwrap_or_default(),
                        causation_id: "".to_string(),
                        created_at: created_at.timestamp(),
                        created_by: "".to_string(),
                    });
                }
                Err(e) => {
                    warn!("Failed to insert event: {}", e);
                    failed_count += 1;
                }
            }
        }

        info!(
            "Batch publish completed: {} succeeded, {} failed",
            success_count, failed_count
        );

        Ok(Response::new(PublishEventsResponse {
            events: published_events,
            success_count,
            failed_count,
        }))
    }

    /// Get a single event by ID
    async fn get_event(
        &self,
        request: Request<GetEventRequest>,
    ) -> Result<Response<GetEventResponse>, Status> {
        let req = request.into_inner();

        if req.event_id.is_empty() {
            return Err(Status::invalid_argument("event_id is required"));
        }

        let event_id = Self::parse_uuid(&req.event_id, "event_id")?;

        // Query from domain_events table
        let row = sqlx::query(
            r#"
            SELECT id, event_type, aggregate_id, aggregate_type, event_version,
                   data, metadata, correlation_id, causation_id, created_by, created_at
            FROM domain_events
            WHERE id = $1
            "#,
        )
        .bind(event_id)
        .fetch_optional(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        let row = row.ok_or_else(|| Status::not_found(format!("Event {} not found", event_id)))?;

        let domain_event = ProtoDomainEvent {
            id: row.get::<Uuid, _>("id").to_string(),
            event_type: row.get("event_type"),
            aggregate_id: row.get("aggregate_id"),
            aggregate_type: row.get("aggregate_type"),
            version: row.get("event_version"),
            data: serde_json::to_string(&row.get::<serde_json::Value, _>("data"))
                .unwrap_or_default(),
            metadata: row
                .get::<Option<serde_json::Value>, _>("metadata")
                .map(|m| serde_json::to_string(&m).unwrap_or_default())
                .unwrap_or_default(),
            correlation_id: row
                .get::<Option<Uuid>, _>("correlation_id")
                .map(|id| id.to_string())
                .unwrap_or_default(),
            causation_id: row
                .get::<Option<Uuid>, _>("causation_id")
                .map(|id| id.to_string())
                .unwrap_or_default(),
            created_at: row
                .get::<chrono::DateTime<Utc>, _>("created_at")
                .timestamp(),
            created_by: row
                .get::<Option<String>, _>("created_by")
                .unwrap_or_default(),
        };

        Ok(Response::new(GetEventResponse {
            event: Some(domain_event),
        }))
    }

    /// Get all events for an aggregate
    async fn get_events_by_aggregate(
        &self,
        request: Request<GetEventsByAggregateRequest>,
    ) -> Result<Response<GetEventsByAggregateResponse>, Status> {
        let req = request.into_inner();

        if req.aggregate_id.is_empty() {
            return Err(Status::invalid_argument("aggregate_id is required"));
        }

        let limit = if req.limit > 0 { req.limit } else { 100 };
        let offset = if req.offset >= 0 { req.offset } else { 0 };

        // Query domain_events
        let rows = sqlx::query(
            r#"
            SELECT id, event_type, aggregate_id, aggregate_type, event_version,
                   data, metadata, correlation_id, causation_id, created_by, created_at
            FROM domain_events
            WHERE aggregate_id = $1 AND aggregate_type = $2
            ORDER BY aggregate_version ASC
            LIMIT $3 OFFSET $4
            "#,
        )
        .bind(&req.aggregate_id)
        .bind(&req.aggregate_type)
        .bind(limit as i64)
        .bind(offset as i64)
        .fetch_all(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        let events: Vec<ProtoDomainEvent> = rows
            .iter()
            .map(|row| ProtoDomainEvent {
                id: row.get::<Uuid, _>("id").to_string(),
                event_type: row.get("event_type"),
                aggregate_id: row.get("aggregate_id"),
                aggregate_type: row.get("aggregate_type"),
                version: row.get("event_version"),
                data: serde_json::to_string(&row.get::<serde_json::Value, _>("data"))
                    .unwrap_or_default(),
                metadata: row
                    .get::<Option<serde_json::Value>, _>("metadata")
                    .map(|m| serde_json::to_string(&m).unwrap_or_default())
                    .unwrap_or_default(),
                correlation_id: row
                    .get::<Option<Uuid>, _>("correlation_id")
                    .map(|id| id.to_string())
                    .unwrap_or_default(),
                causation_id: row
                    .get::<Option<Uuid>, _>("causation_id")
                    .map(|id| id.to_string())
                    .unwrap_or_default(),
                created_at: row
                    .get::<chrono::DateTime<Utc>, _>("created_at")
                    .timestamp(),
                created_by: row
                    .get::<Option<String>, _>("created_by")
                    .unwrap_or_default(),
            })
            .collect();

        // Get total count
        let total_count: i64 = sqlx::query_scalar(
            "SELECT COUNT(*) FROM domain_events WHERE aggregate_id = $1 AND aggregate_type = $2",
        )
        .bind(&req.aggregate_id)
        .bind(&req.aggregate_type)
        .fetch_one(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        Ok(Response::new(GetEventsByAggregateResponse {
            events,
            total_count: total_count as i32,
        }))
    }

    /// Get events by type
    async fn get_events_by_type(
        &self,
        request: Request<GetEventsByTypeRequest>,
    ) -> Result<Response<GetEventsByTypeResponse>, Status> {
        let req = request.into_inner();

        if req.event_type.is_empty() {
            return Err(Status::invalid_argument("event_type is required"));
        }

        let limit = if req.limit > 0 { req.limit } else { 100 };
        let offset = if req.offset >= 0 { req.offset } else { 0 };

        let rows = sqlx::query(
            r#"
            SELECT id, event_type, aggregate_id, aggregate_type, event_version,
                   data, metadata, correlation_id, causation_id, created_by, created_at
            FROM domain_events
            WHERE event_type = $1
            ORDER BY created_at DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(&req.event_type)
        .bind(limit as i64)
        .bind(offset as i64)
        .fetch_all(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        let events: Vec<ProtoDomainEvent> = rows
            .iter()
            .map(|row| ProtoDomainEvent {
                id: row.get::<Uuid, _>("id").to_string(),
                event_type: row.get("event_type"),
                aggregate_id: row.get("aggregate_id"),
                aggregate_type: row.get("aggregate_type"),
                version: row.get("event_version"),
                data: serde_json::to_string(&row.get::<serde_json::Value, _>("data"))
                    .unwrap_or_default(),
                metadata: row
                    .get::<Option<serde_json::Value>, _>("metadata")
                    .map(|m| serde_json::to_string(&m).unwrap_or_default())
                    .unwrap_or_default(),
                correlation_id: row
                    .get::<Option<Uuid>, _>("correlation_id")
                    .map(|id| id.to_string())
                    .unwrap_or_default(),
                causation_id: row
                    .get::<Option<Uuid>, _>("causation_id")
                    .map(|id| id.to_string())
                    .unwrap_or_default(),
                created_at: row
                    .get::<chrono::DateTime<Utc>, _>("created_at")
                    .timestamp(),
                created_by: row
                    .get::<Option<String>, _>("created_by")
                    .unwrap_or_default(),
            })
            .collect();

        let total_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM domain_events WHERE event_type = $1")
                .bind(&req.event_type)
                .fetch_one(&self.state.db)
                .await
                .map_err(Self::db_error_to_status)?;

        Ok(Response::new(GetEventsByTypeResponse {
            events,
            total_count: total_count as i32,
        }))
    }

    /// Subscribe to events (simplified implementation)
    async fn subscribe_to_events(
        &self,
        request: Request<SubscribeToEventsRequest>,
    ) -> Result<Response<SubscribeToEventsResponse>, Status> {
        let req = request.into_inner();

        if req.subscriber_service.is_empty() {
            return Err(Status::invalid_argument("subscriber_service is required"));
        }
        if req.event_types.is_empty() {
            return Err(Status::invalid_argument("event_types cannot be empty"));
        }

        let subscription_id = Uuid::new_v4();
        let created_at = Utc::now();

        sqlx::query(
            r#"
            INSERT INTO event_subscriptions (
                id, subscriber_service, event_types, endpoint, subscription_type, created_at
            )
            VALUES ($1, $2, $3, $4, 'kafka_consumer', $5)
            "#,
        )
        .bind(subscription_id)
        .bind(&req.subscriber_service)
        .bind(&req.event_types)
        .bind(&req.endpoint)
        .bind(created_at)
        .execute(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        info!(
            "Created subscription {} for service {}",
            subscription_id, req.subscriber_service
        );

        Ok(Response::new(SubscribeToEventsResponse {
            subscription: Some(ProtoEventSubscription {
                id: subscription_id.to_string(),
                subscriber_service: req.subscriber_service,
                event_types: req.event_types,
                endpoint: req.endpoint,
                is_active: true,
                created_at: created_at.timestamp(),
            }),
        }))
    }

    async fn unsubscribe_from_events(
        &self,
        request: Request<UnsubscribeFromEventsRequest>,
    ) -> Result<Response<UnsubscribeFromEventsResponse>, Status> {
        let req = request.into_inner();

        if req.subscription_id.is_empty() {
            return Err(Status::invalid_argument("subscription_id is required"));
        }

        let subscription_id = Self::parse_uuid(&req.subscription_id, "subscription_id")?;

        let result = sqlx::query("UPDATE event_subscriptions SET is_active = false WHERE id = $1")
            .bind(subscription_id)
            .execute(&self.state.db)
            .await
            .map_err(Self::db_error_to_status)?;

        Ok(Response::new(UnsubscribeFromEventsResponse {
            success: result.rows_affected() > 0,
        }))
    }

    async fn get_subscriptions(
        &self,
        request: Request<GetSubscriptionsRequest>,
    ) -> Result<Response<GetSubscriptionsResponse>, Status> {
        let req = request.into_inner();

        let rows = if req.subscriber_service.is_empty() {
            sqlx::query(
                r#"
                SELECT id, subscriber_service, event_types, endpoint, is_active, created_at
                FROM event_subscriptions
                WHERE is_active = true
                "#,
            )
            .fetch_all(&self.state.db)
            .await
            .map_err(Self::db_error_to_status)?
        } else {
            sqlx::query(
                r#"
                SELECT id, subscriber_service, event_types, endpoint, is_active, created_at
                FROM event_subscriptions
                WHERE subscriber_service = $1 AND is_active = true
                "#,
            )
            .bind(&req.subscriber_service)
            .fetch_all(&self.state.db)
            .await
            .map_err(Self::db_error_to_status)?
        };

        let subscriptions: Vec<ProtoEventSubscription> = rows
            .iter()
            .map(|row| ProtoEventSubscription {
                id: row.get::<Uuid, _>("id").to_string(),
                subscriber_service: row.get("subscriber_service"),
                event_types: row.get("event_types"),
                endpoint: row.get("endpoint"),
                is_active: row.get("is_active"),
                created_at: row
                    .get::<chrono::DateTime<Utc>, _>("created_at")
                    .timestamp(),
            })
            .collect();

        Ok(Response::new(GetSubscriptionsResponse { subscriptions }))
    }

    async fn register_event_schema(
        &self,
        request: Request<RegisterEventSchemaRequest>,
    ) -> Result<Response<RegisterEventSchemaResponse>, Status> {
        let req = request.into_inner();

        if req.event_type.is_empty() {
            return Err(Status::invalid_argument("event_type is required"));
        }
        if req.schema_json.is_empty() {
            return Err(Status::invalid_argument("schema_json is required"));
        }

        let schema_json = Self::parse_json(&req.schema_json, "schema_json")?;
        let schema_id = Uuid::new_v4();
        let created_at = Utc::now();

        // Get next version number
        let version: i32 = sqlx::query_scalar(
            "SELECT COALESCE(MAX(version), 0) + 1 FROM event_schemas WHERE event_type = $1",
        )
        .bind(&req.event_type)
        .fetch_one(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        // Deactivate previous versions if set_as_active
        if req.set_as_active {
            sqlx::query("UPDATE event_schemas SET is_active = false WHERE event_type = $1")
                .bind(&req.event_type)
                .execute(&self.state.db)
                .await
                .map_err(Self::db_error_to_status)?;
        }

        sqlx::query(
            r#"
            INSERT INTO event_schemas (
                id, event_type, version, schema_json, is_active, created_at, updated_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $6)
            "#,
        )
        .bind(schema_id)
        .bind(&req.event_type)
        .bind(version)
        .bind(&schema_json)
        .bind(req.set_as_active)
        .bind(created_at)
        .execute(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        info!(
            "Registered schema {} for event type {} (version {})",
            schema_id, req.event_type, version
        );

        Ok(Response::new(RegisterEventSchemaResponse {
            schema: Some(ProtoEventSchema {
                id: schema_id.to_string(),
                event_type: req.event_type,
                version,
                schema_json: req.schema_json,
                is_active: req.set_as_active,
                created_at: created_at.timestamp(),
            }),
        }))
    }

    async fn get_event_schema(
        &self,
        request: Request<GetEventSchemaRequest>,
    ) -> Result<Response<GetEventSchemaResponse>, Status> {
        let req = request.into_inner();

        if req.event_type.is_empty() {
            return Err(Status::invalid_argument("event_type is required"));
        }

        let row = sqlx::query(
            r#"
            SELECT id, event_type, version, schema_json, is_active, created_at
            FROM event_schemas
            WHERE event_type = $1 AND is_active = true
            LIMIT 1
            "#,
        )
        .bind(&req.event_type)
        .fetch_optional(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        let row = row.ok_or_else(|| {
            Status::not_found(format!(
                "No active schema found for event type: {}",
                req.event_type
            ))
        })?;

        let schema = ProtoEventSchema {
            id: row.get::<Uuid, _>("id").to_string(),
            event_type: row.get("event_type"),
            version: row.get("version"),
            schema_json: serde_json::to_string(&row.get::<serde_json::Value, _>("schema_json"))
                .unwrap_or_default(),
            is_active: row.get("is_active"),
            created_at: row
                .get::<chrono::DateTime<Utc>, _>("created_at")
                .timestamp(),
        };

        Ok(Response::new(GetEventSchemaResponse {
            schema: Some(schema),
        }))
    }

    async fn get_outbox_events(
        &self,
        request: Request<GetOutboxEventsRequest>,
    ) -> Result<Response<GetOutboxEventsResponse>, Status> {
        let req = request.into_inner();

        let status = if req.status.is_empty() {
            "pending"
        } else {
            &req.status
        };

        let limit = if req.limit > 0 { req.limit } else { 100 };

        let rows = sqlx::query(
            r#"
            SELECT id, event_type, aggregate_id, aggregate_type, data,
                   status, retry_count, last_error, created_at, published_at
            FROM outbox_events
            WHERE status = $1
            ORDER BY created_at DESC
            LIMIT $2
            "#,
        )
        .bind(status)
        .bind(limit as i64)
        .fetch_all(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        let events: Vec<ProtoOutboxEvent> = rows
            .iter()
            .map(|row| ProtoOutboxEvent {
                id: row.get::<Uuid, _>("id").to_string(),
                event_type: row.get("event_type"),
                aggregate_id: row.get("aggregate_id"),
                aggregate_type: row.get("aggregate_type"),
                data: serde_json::to_string(&row.get::<serde_json::Value, _>("data"))
                    .unwrap_or_default(),
                status: row.get("status"),
                retry_count: row.get("retry_count"),
                error: row.get::<Option<String>, _>("last_error").map(|e| {
                    nova::common::v1::ErrorStatus {
                        code: "500".to_string(),
                        message: e,
                        metadata: std::collections::HashMap::new(),
                    }
                }),
                created_at: row
                    .get::<chrono::DateTime<Utc>, _>("created_at")
                    .timestamp(),
                published_at: row
                    .get::<Option<chrono::DateTime<Utc>>, _>("published_at")
                    .map(|dt| dt.timestamp())
                    .unwrap_or(0),
            })
            .collect();

        Ok(Response::new(GetOutboxEventsResponse { events }))
    }

    async fn mark_outbox_event_published(
        &self,
        request: Request<MarkOutboxEventPublishedRequest>,
    ) -> Result<Response<MarkOutboxEventPublishedResponse>, Status> {
        let req = request.into_inner();

        if req.outbox_event_id.is_empty() {
            return Err(Status::invalid_argument("outbox_event_id is required"));
        }

        let event_id = Self::parse_uuid(&req.outbox_event_id, "outbox_event_id")?;

        sqlx::query(
            "UPDATE outbox_events SET status = 'published', published_at = NOW() WHERE id = $1",
        )
        .bind(event_id)
        .execute(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        // Fetch updated event
        let row = sqlx::query(
            r#"
            SELECT id, event_type, aggregate_id, aggregate_type, data,
                   status, retry_count, last_error, created_at, published_at
            FROM outbox_events
            WHERE id = $1
            "#,
        )
        .bind(event_id)
        .fetch_one(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        let event = ProtoOutboxEvent {
            id: row.get::<Uuid, _>("id").to_string(),
            event_type: row.get("event_type"),
            aggregate_id: row.get("aggregate_id"),
            aggregate_type: row.get("aggregate_type"),
            data: serde_json::to_string(&row.get::<serde_json::Value, _>("data"))
                .unwrap_or_default(),
            status: row.get("status"),
            retry_count: row.get("retry_count"),
            error: row.get::<Option<String>, _>("last_error").map(|e| {
                nova::common::v1::ErrorStatus {
                    code: "500".to_string(),
                    message: e,
                    metadata: std::collections::HashMap::new(),
                }
            }),
            created_at: row
                .get::<chrono::DateTime<Utc>, _>("created_at")
                .timestamp(),
            published_at: row
                .get::<Option<chrono::DateTime<Utc>>, _>("published_at")
                .map(|dt| dt.timestamp())
                .unwrap_or(0),
        };

        Ok(Response::new(MarkOutboxEventPublishedResponse {
            event: Some(event),
        }))
    }

    async fn retry_outbox_event(
        &self,
        request: Request<RetryOutboxEventRequest>,
    ) -> Result<Response<RetryOutboxEventResponse>, Status> {
        let req = request.into_inner();

        if req.outbox_event_id.is_empty() {
            return Err(Status::invalid_argument("outbox_event_id is required"));
        }

        let event_id = Self::parse_uuid(&req.outbox_event_id, "outbox_event_id")?;

        // Reset to pending for retry
        sqlx::query(
            r#"
            UPDATE outbox_events
            SET status = 'pending', next_retry_at = NULL
            WHERE id = $1
            "#,
        )
        .bind(event_id)
        .execute(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        let row = sqlx::query(
            r#"
            SELECT id, event_type, aggregate_id, aggregate_type, data,
                   status, retry_count, last_error, created_at, published_at
            FROM outbox_events
            WHERE id = $1
            "#,
        )
        .bind(event_id)
        .fetch_one(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        let event = ProtoOutboxEvent {
            id: row.get::<Uuid, _>("id").to_string(),
            event_type: row.get("event_type"),
            aggregate_id: row.get("aggregate_id"),
            aggregate_type: row.get("aggregate_type"),
            data: serde_json::to_string(&row.get::<serde_json::Value, _>("data"))
                .unwrap_or_default(),
            status: row.get("status"),
            retry_count: row.get("retry_count"),
            error: row.get::<Option<String>, _>("last_error").map(|e| {
                nova::common::v1::ErrorStatus {
                    code: "500".to_string(),
                    message: e,
                    metadata: std::collections::HashMap::new(),
                }
            }),
            created_at: row
                .get::<chrono::DateTime<Utc>, _>("created_at")
                .timestamp(),
            published_at: row
                .get::<Option<chrono::DateTime<Utc>>, _>("published_at")
                .map(|dt| dt.timestamp())
                .unwrap_or(0),
        };

        Ok(Response::new(RetryOutboxEventResponse {
            event: Some(event),
        }))
    }

    async fn get_event_stats(
        &self,
        _request: Request<GetEventStatsRequest>,
    ) -> Result<Response<GetEventStatsResponse>, Status> {
        // Get stats from outbox_events
        let total_published: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM outbox_events WHERE status = 'published'")
                .fetch_one(&self.state.db)
                .await
                .map_err(Self::db_error_to_status)?;

        let total_failed: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM outbox_events WHERE status = 'failed'")
                .fetch_one(&self.state.db)
                .await
                .map_err(Self::db_error_to_status)?;

        // Get events by type
        let rows = sqlx::query(
            r#"
            SELECT event_type, COUNT(*) as count
            FROM outbox_events
            WHERE status = 'published'
            GROUP BY event_type
            "#,
        )
        .fetch_all(&self.state.db)
        .await
        .map_err(Self::db_error_to_status)?;

        let mut events_by_type = std::collections::HashMap::new();
        for row in rows {
            events_by_type.insert(
                row.get::<String, _>("event_type"),
                row.get::<i64, _>("count") as i32,
            );
        }

        Ok(Response::new(GetEventStatsResponse {
            total_events_published: total_published as i32,
            total_events_processed: total_published as i32,
            failed_events: total_failed as i32,
            events_by_type,
        }))
    }
}
