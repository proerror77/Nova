//! Integration tests for CDC ClickHouse typed inserts using testcontainers
#![cfg(test)]

use testcontainers::{clients::Cli, images::generic::GenericImage, RunnableImage, core::WaitFor};
use user_service::db::ch_client::ClickHouseClient;
use uuid::Uuid;

#[derive(serde::Serialize, clickhouse::Row)]
struct PostCdcRow {
    id: Uuid,
    user_id: Uuid,
    content: String,
    media_url: Option<String>,
    created_at: chrono::DateTime<chrono::Utc>,
    cdc_timestamp: u64,
    is_deleted: u8,
}

#[derive(clickhouse::Row, serde::Deserialize)]
struct PostCdcRead {
    id: Uuid,
    user_id: Uuid,
    content: String,
    media_url: Option<String>,
    cdc_timestamp: u64,
    is_deleted: u8,
}

#[tokio::test]
async fn test_typed_insert_handles_adversarial_content() {
    let docker = Cli::default();
    // Start ClickHouse
    let image = GenericImage::new("clickhouse/clickhouse-server", "23.8")
        .with_wait_for(WaitFor::message("Ready for connections"));
    let node = docker.run(RunnableImage::from(image));
    let mapped_port = node.get_host_port_ipv4(8123);

    let url = format!("http://127.0.0.1:{}", mapped_port);
    let ch = ClickHouseClient::new_writable(&url, "default", "default", "", 5000);

    // Create minimal table for test
    ch.execute(
        r#"CREATE TABLE IF NOT EXISTS posts_cdc (
            id UUID,
            user_id UUID,
            content String,
            media_url Nullable(String),
            created_at DateTime,
            cdc_timestamp UInt64,
            is_deleted UInt8
        ) ENGINE = ReplacingMergeTree(cdc_timestamp)
        ORDER BY id"#,
    )
    .await
    .expect("failed to create table");

    let row = PostCdcRow {
        id: Uuid::new_v4(),
        user_id: Uuid::new_v4(),
        content: "O'Hara \\ backslash \n new line \t tab ); DROP TABLE --".to_string(),
        media_url: Some("https://cdn.example.com/x?a='&b=1".to_string()),
        created_at: chrono::Utc::now(),
        cdc_timestamp: 1,
        is_deleted: 0,
    };

    ch.insert_row("posts_cdc", &row).await.expect("insert failed");

    // Read back and verify content integrity (no escaping corruption, no SQL errors)
    let q = format!(
        "SELECT id, user_id, content, media_url, cdc_timestamp, is_deleted FROM posts_cdc WHERE id = '{}'",
        row.id
    );
    let rows: Vec<PostCdcRead> = ch.query(&q).await.expect("query failed");
    assert_eq!(rows.len(), 1);
    let got = &rows[0];
    assert_eq!(got.content, row.content);
    assert_eq!(got.media_url, row.media_url);
    assert_eq!(got.is_deleted, 0);
}

