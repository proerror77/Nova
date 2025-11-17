//! Integration tests for Events typed inserts using testcontainers
#![cfg(test)]

use testcontainers::{clients::Cli, core::WaitFor, images::generic::GenericImage, RunnableImage};
use user_service::db::ch_client::ClickHouseClient;

#[derive(serde::Serialize, clickhouse::Row)]
struct EventRow<'a> {
    event_id: &'a str,
    event_type: &'a str,
    user_id: i64,
    timestamp: i64,
    properties: String,
}

#[derive(clickhouse::Row, serde::Deserialize)]
struct EventRead {
    event_id: String,
    event_type: String,
    user_id: i64,
    timestamp: i64,
    properties: String,
}

#[tokio::test]
async fn test_events_typed_insert_handles_adversarial_content() {
    let docker = Cli::default();
    let image = GenericImage::new("clickhouse/clickhouse-server", "23.8")
        .with_wait_for(WaitFor::message("Ready for connections"));
    let node = docker.run(RunnableImage::from(image));
    let mapped_port = node.get_host_port_ipv4(8123);

    let url = format!("http://127.0.0.1:{}", mapped_port);
    let ch = ClickHouseClient::new_writable(&url, "default", "default", "", 5_000);

    // Create minimal table schema for events
    ch.execute(
        r#"CREATE TABLE IF NOT EXISTS events (
            event_id String,
            event_type String,
            user_id Int64,
            timestamp Int64,
            properties String
        ) ENGINE = MergeTree()
        ORDER BY (event_id)"#,
    )
    .await
    .expect("failed to create events table");

    let row = EventRow {
        event_id: "abc-def",
        event_type: "post_created",
        user_id: 42,
        timestamp: 1,
        properties: "{\"payload\":\"O'Hara \\ backslash \\n+ new line \\t tab ); DROP TABLE --\"}".to_string(),
    };

    ch.insert_rows("events", &[row]).await.expect("insert failed");

    let q = "SELECT event_id, event_type, user_id, timestamp, properties FROM events WHERE event_id = 'abc-def'";
    let rows: Vec<EventRead> = ch.query(q).await.expect("query failed");
    assert_eq!(rows.len(), 1);
    let got = &rows[0];
    assert_eq!(got.event_type, "post_created");
    assert_eq!(got.user_id, 42);
    assert!(got.properties.contains("O'Hara"));
}

