#[path = "mock_encoder.rs"]
mod mock_encoder;

#[path = "integration/support.rs"]
mod support;

#[path = "integration/broadcaster_connect_test.rs"]
mod broadcaster_connect_test;

#[path = "integration/websocket_test.rs"]
mod websocket_test;

#[path = "integration/viewer_session_test.rs"]
mod viewer_session_test;

#[path = "integration/e2e_broadcaster_viewer_test.rs"]
mod e2e_broadcaster_viewer_test;
