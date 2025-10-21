use awc::{ws, Client};
use futures_util::StreamExt;
use streaming_delivery::status_publisher::StreamStatusPublisher;
use streaming_delivery::websocket_hub::WebSocketHub;
use uuid::Uuid;

use super::support::start_websocket_server;

#[actix_rt::test]
async fn websocket_receives_status_updates() {
    let hub = WebSocketHub::new();
    let publisher = StreamStatusPublisher::new(hub.clone());
    let (addr, handle) = start_websocket_server(hub.clone(), publisher.clone())
        .await
        .expect("start websocket server");
    let stream_id = Uuid::new_v4();
    let client = Client::new();
    let (_resp, mut connection) = client
        .ws(format!("http://{addr}/ws/stream/{stream_id}"))
        .connect()
        .await
        .expect("connect websocket client");

    publisher.stream_started(stream_id);

    let frame = connection.next().await.expect("frame").expect("frame data");
    match frame {
        ws::Frame::Text(bytes) => {
            let text = String::from_utf8(bytes.to_vec()).unwrap();
            assert!(text.contains("ACTIVE"));
        }
        other => panic!("unexpected frame: {other:?}"),
    }
    handle.stop(true).await;
}
