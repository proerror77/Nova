//! Kafka correlation ID helpers for rdkafka
use rdkafka::message::{Header, OwnedHeaders};
use crate::correlation::{KAFKA_CORRELATION_ID_HEADER, CorrelationContext};

pub fn inject_headers(mut headers: OwnedHeaders, correlation_id: &str) -> OwnedHeaders {
    headers = headers.insert(Header { key: KAFKA_CORRELATION_ID_HEADER, value: Some(correlation_id.as_bytes()) });
    headers
}

pub async fn extract_to_context<M: rdkafka::message::BorrowedMessage<'static>>(msg: &M, ctx: &CorrelationContext) {
    if let Some(hdrs) = msg.headers() {
        for i in 0..hdrs.count() {
            if let Some(h) = hdrs.get(i) {
                if h.key == KAFKA_CORRELATION_ID_HEADER {
                    if let Some(v) = h.value {
                        if let Ok(s) = std::str::from_utf8(v) {
                            ctx.set(s.to_string()).await;
                        }
                    }
                }
            }
        }
    }
}

