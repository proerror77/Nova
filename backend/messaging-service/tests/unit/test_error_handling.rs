use messaging_service::middleware::error_handling::map_error;
use messaging_service::error::AppError;

#[test]
fn maps_config_error_to_500() {
    let (status, msg) = map_error(&AppError::Config("missing".into()));
    assert_eq!(status.as_u16(), 500);
    assert!(msg.contains("config"));
}

