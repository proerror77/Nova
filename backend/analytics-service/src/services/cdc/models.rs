use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::error::{AnalyticsError, Result};

/// CDC operation types from Debezium
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum CdcOperation {
    /// Insert operation (c = create)
    #[serde(rename = "c")]
    Insert,
    /// Update operation (u = update)
    #[serde(rename = "u")]
    Update,
    /// Delete operation (d = delete)
    #[serde(rename = "d")]
    Delete,
    /// Read operation (r = read, initial snapshot)
    #[serde(rename = "r")]
    Read,
}

impl CdcOperation {
    /// Check if operation modifies data (excludes Read)
    pub fn is_mutating(&self) -> bool {
        matches!(self, Self::Insert | Self::Update | Self::Delete)
    }
}

/// CDC message structure from Debezium
///
/// When `value.converter.schemas.enable = false`, Debezium sends the payload directly
/// without a wrapper object. This struct handles both formats.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum CdcMessage {
    /// Format with schema wrapper (value.converter.schemas.enable = true)
    WithSchema { payload: CdcPayload },
    /// Format without schema wrapper (value.converter.schemas.enable = false)
    WithoutSchema(CdcPayload),
}

impl CdcMessage {
    /// Get the payload regardless of message format
    pub fn payload(&self) -> &CdcPayload {
        match self {
            CdcMessage::WithSchema { payload } => payload,
            CdcMessage::WithoutSchema(payload) => payload,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CdcPayload {
    /// State before the change (null for Insert, populated for Update/Delete)
    pub before: Option<Value>,

    /// State after the change (populated for Insert/Update, null for Delete)
    pub after: Option<Value>,

    /// Source metadata (database, table, timestamp, etc.)
    pub source: CdcSource,

    /// Operation type (c/u/d/r)
    pub op: CdcOperation,

    /// Transaction timestamp in milliseconds since epoch
    pub ts_ms: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CdcSource {
    /// Debezium connector version
    pub version: String,

    /// Connector type (e.g., "postgresql")
    pub connector: String,

    /// Logical name of the database server
    pub name: String,

    /// Timestamp in milliseconds
    pub ts_ms: i64,

    /// Database name
    pub db: String,

    /// Schema name (for PostgreSQL)
    pub schema: Option<String>,

    /// Table name
    pub table: String,
}

impl CdcMessage {
    /// Validate the CDC message structure
    pub fn validate(&self) -> Result<()> {
        let payload = self.payload();
        let op = &payload.op;
        let before = &payload.before;
        let after = &payload.after;

        match op {
            CdcOperation::Insert | CdcOperation::Read => {
                if after.is_none() {
                    return Err(AnalyticsError::Validation(format!(
                        "CDC {:?} operation requires 'after' field",
                        op
                    )));
                }
            }
            CdcOperation::Update => {
                if after.is_none() {
                    return Err(AnalyticsError::Validation(
                        "CDC Update operation requires 'after' field".to_string(),
                    ));
                }
            }
            CdcOperation::Delete => {
                if before.is_none() {
                    return Err(AnalyticsError::Validation(
                        "CDC Delete operation requires 'before' field".to_string(),
                    ));
                }
            }
        }

        // Validate timestamp is reasonable (not in distant past/future)
        let now = Utc::now().timestamp_millis();
        let ts_diff = (now - payload.ts_ms).abs();

        // Allow 1 year tolerance (clock skew + data migration)
        const ONE_YEAR_MS: i64 = 365 * 24 * 60 * 60 * 1000;
        if ts_diff > ONE_YEAR_MS {
            return Err(AnalyticsError::Validation(format!(
                "CDC timestamp {} is too far from current time {}",
                payload.ts_ms, now
            )));
        }

        Ok(())
    }

    /// Get the table name from the CDC message
    pub fn table(&self) -> &str {
        &self.payload().source.table
    }

    /// Get the operation type
    pub fn operation(&self) -> &CdcOperation {
        &self.payload().op
    }

    /// Get the timestamp as DateTime
    pub fn timestamp(&self) -> DateTime<Utc> {
        DateTime::from_timestamp_millis(self.payload().ts_ms).unwrap_or_else(Utc::now)
    }

    /// Extract a field from the 'after' or 'before' payload
    pub fn get_field(&self, field_name: &str) -> Option<&Value> {
        let payload = self.payload();
        payload
            .after
            .as_ref()
            .or(payload.before.as_ref())
            .and_then(|v| v.get(field_name))
    }

    /// Extract a field as a specific type
    pub fn get_field_as<T>(&self, field_name: &str) -> Result<T>
    where
        T: serde::de::DeserializeOwned,
    {
        self.get_field(field_name)
            .ok_or_else(|| AnalyticsError::Validation(format!("Field '{}' not found", field_name)))
            .and_then(|v| {
                serde_json::from_value(v.clone()).map_err(|e| {
                    AnalyticsError::Validation(format!(
                        "Failed to deserialize field '{}': {}",
                        field_name, e
                    ))
                })
            })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn create_test_source() -> CdcSource {
        CdcSource {
            version: "2.0.0.Final".to_string(),
            connector: "postgresql".to_string(),
            name: "nova-db".to_string(),
            ts_ms: Utc::now().timestamp_millis(),
            db: "nova".to_string(),
            schema: Some("public".to_string()),
            table: "posts".to_string(),
        }
    }

    #[test]
    fn test_cdc_insert_validation() {
        let msg = CdcMessage {
            payload: CdcPayload {
                before: None,
                after: Some(json!({"id": 1, "content": "test"})),
                source: create_test_source(),
                op: CdcOperation::Insert,
                ts_ms: Utc::now().timestamp_millis(),
            },
        };

        assert!(msg.validate().is_ok());
    }

    #[test]
    fn test_cdc_delete_validation() {
        let msg = CdcMessage {
            payload: CdcPayload {
                before: Some(json!({"id": 1, "content": "test"})),
                after: None,
                source: create_test_source(),
                op: CdcOperation::Delete,
                ts_ms: Utc::now().timestamp_millis(),
            },
        };

        assert!(msg.validate().is_ok());
    }
}
