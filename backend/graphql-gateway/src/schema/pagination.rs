//! Relay Cursor-based Pagination Implementation
//! Standard for efficient pagination of large result sets

use async_graphql::SimpleObject;
use base64::{engine::general_purpose, Engine as _};
use serde::{Deserialize, Serialize};

/// Relay connection node wrapper
#[derive(SimpleObject, Clone, Debug, Serialize, Deserialize)]
pub struct Edge<T: async_graphql::OutputType> {
    pub node: T,
    pub cursor: String,
}

/// Page info for cursor pagination
#[derive(SimpleObject, Clone, Debug, Serialize, Deserialize)]
pub struct PageInfo {
    /// Whether there are more items after the current page
    pub has_next_page: bool,
    /// Whether there are items before the current page
    pub has_previous_page: bool,
    /// Cursor pointing to the start of returned items
    pub start_cursor: Option<String>,
    /// Cursor pointing to the end of returned items
    pub end_cursor: Option<String>,
    /// Total count of items (optional, can be expensive)
    pub total_count: Option<i32>,
}

/// Connection wrapper for paginated results (Relay standard)
#[derive(SimpleObject, Clone, Debug)]
pub struct Connection<T: async_graphql::OutputType> {
    pub edges: Vec<Edge<T>>,
    pub page_info: PageInfo,
}

/// Encoding strategy for cursors
/// Allows opaque cursor format that can evolve without breaking clients
pub struct CursorCodec;

impl CursorCodec {
    /// Encode an offset-based cursor
    /// Format: base64("offset:123")
    pub fn encode(offset: i32) -> String {
        let cursor_str = format!("offset:{}", offset);
        general_purpose::STANDARD.encode(cursor_str)
    }

    /// Decode an offset-based cursor
    pub fn decode(cursor: &str) -> Result<i32, String> {
        let decoded = general_purpose::STANDARD
            .decode(cursor)
            .map_err(|e| format!("Invalid cursor format: {}", e))?;

        let cursor_str =
            String::from_utf8(decoded).map_err(|e| format!("Cursor not valid UTF-8: {}", e))?;

        if let Some(offset_str) = cursor_str.strip_prefix("offset:") {
            offset_str
                .parse::<i32>()
                .map_err(|e| format!("Invalid offset: {}", e))
        } else {
            Err("Unknown cursor format".to_string())
        }
    }

    /// Encode a keyset-based cursor (for large datasets)
    /// Format: base64("id:post_123,timestamp:1699632000")
    pub fn encode_keyset(id: &str, timestamp: i64) -> String {
        let cursor_str = format!("id:{},ts:{}", id, timestamp);
        general_purpose::STANDARD.encode(cursor_str)
    }

    /// Decode a keyset-based cursor
    pub fn decode_keyset(cursor: &str) -> Result<(String, i64), String> {
        let decoded = general_purpose::STANDARD
            .decode(cursor)
            .map_err(|e| format!("Invalid cursor format: {}", e))?;

        let cursor_str =
            String::from_utf8(decoded).map_err(|e| format!("Cursor not valid UTF-8: {}", e))?;

        // Parse "id:post_123,ts:1699632000"
        let parts: Vec<&str> = cursor_str.split(',').collect();
        if parts.len() != 2 {
            return Err("Invalid keyset cursor format".to_string());
        }

        let id = parts[0]
            .strip_prefix("id:")
            .ok_or("Missing id prefix")?
            .to_string();

        let timestamp = parts[1]
            .strip_prefix("ts:")
            .ok_or("Missing ts prefix")?
            .parse::<i64>()
            .map_err(|e| format!("Invalid timestamp: {}", e))?;

        Ok((id, timestamp))
    }
}

/// Pagination arguments following Relay specification
#[derive(Clone, Debug, Default)]
pub struct PaginationArgs {
    /// Number of items to return (default: 10, max: 100)
    pub first: Option<i32>,
    /// Cursor to start after
    pub after: Option<String>,
    /// Number of items to return backwards (not recommended with after)
    pub last: Option<i32>,
    /// Cursor to end before
    pub before: Option<String>,
}

impl PaginationArgs {
    /// Validate pagination arguments
    pub fn validate(&self) -> Result<(), String> {
        // Can't specify both first and last
        if self.first.is_some() && self.last.is_some() {
            return Err("Cannot specify both 'first' and 'last'".to_string());
        }

        // Can't specify both after and before without first/last
        if self.after.is_some() && self.before.is_some() {
            return Err("Cannot specify both 'after' and 'before'".to_string());
        }

        // Validate first
        if let Some(first) = self.first {
            if first < 0 {
                return Err("'first' must be non-negative".to_string());
            }
            if first > 100 {
                return Err("'first' cannot exceed 100 items".to_string());
            }
        }

        // Validate last
        if let Some(last) = self.last {
            if last < 0 {
                return Err("'last' must be non-negative".to_string());
            }
            if last > 100 {
                return Err("'last' cannot exceed 100 items".to_string());
            }
        }

        Ok(())
    }

    /// Get effective limit
    pub fn get_limit(&self) -> i32 {
        self.first.or(self.last).unwrap_or(10).min(100).max(1)
    }

    /// Get effective offset from after cursor
    pub fn get_offset(&self) -> Result<i32, String> {
        if let Some(after) = &self.after {
            CursorCodec::decode(after)
        } else {
            Ok(0)
        }
    }
}

/// Builder for constructing Connection results
pub struct ConnectionBuilder<T: async_graphql::OutputType> {
    items: Vec<(T, String)>,
    offset: i32,
    total_count: Option<i32>,
}

impl<T: async_graphql::OutputType> ConnectionBuilder<T> {
    pub fn new(items: Vec<T>, offset: i32) -> Self {
        let items_with_cursors = items
            .into_iter()
            .enumerate()
            .map(|(idx, item)| {
                let cursor = CursorCodec::encode(offset + idx as i32);
                (item, cursor)
            })
            .collect();

        Self {
            items: items_with_cursors,
            offset,
            total_count: None,
        }
    }

    pub fn with_total_count(mut self, count: i32) -> Self {
        self.total_count = Some(count);
        self
    }

    pub fn build(self, args: &PaginationArgs) -> Connection<T> {
        let limit = args.get_limit() as usize;
        let edges: Vec<Edge<T>> = self
            .items
            .into_iter()
            .map(|(node, cursor)| Edge { node, cursor })
            .collect();

        let start_cursor = edges.first().map(|e| e.cursor.clone());
        let end_cursor = edges.last().map(|e| e.cursor.clone());

        let has_next_page = self
            .total_count
            .map(|tc| (self.offset + limit as i32) < tc);
        let has_previous_page = self.offset > 0;

        Connection {
            edges,
            page_info: PageInfo {
                has_next_page: has_next_page.unwrap_or(false),
                has_previous_page,
                start_cursor,
                end_cursor,
                total_count: self.total_count,
            },
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cursor_encode_decode() {
        let cursor = CursorCodec::encode(42);
        assert_eq!(CursorCodec::decode(&cursor).unwrap(), 42);
    }

    #[test]
    fn test_keyset_cursor_encode_decode() {
        let (id, ts) = ("post_123", 1699632000i64);
        let cursor = CursorCodec::encode_keyset(id, ts);
        let (decoded_id, decoded_ts) = CursorCodec::decode_keyset(&cursor).unwrap();
        assert_eq!(decoded_id, id);
        assert_eq!(decoded_ts, ts);
    }

    #[test]
    fn test_pagination_args_validation() {
        let args = PaginationArgs {
            first: Some(10),
            after: None,
            last: None,
            before: None,
        };
        assert!(args.validate().is_ok());

        let invalid = PaginationArgs {
            first: Some(10),
            last: Some(5),
            after: None,
            before: None,
        };
        assert!(invalid.validate().is_err());

        let too_large = PaginationArgs {
            first: Some(500),
            after: None,
            last: None,
            before: None,
        };
        assert!(too_large.validate().is_err());
    }

    #[test]
    fn test_pagination_args_get_limit() {
        let args = PaginationArgs {
            first: Some(25),
            after: None,
            last: None,
            before: None,
        };
        assert_eq!(args.get_limit(), 25);

        let default_args = PaginationArgs::default();
        assert_eq!(default_args.get_limit(), 10);
    }
}
