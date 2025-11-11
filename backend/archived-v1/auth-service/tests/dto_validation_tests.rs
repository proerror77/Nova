use auth_service::models::user::{LoginRequest, RegisterRequest};
use validator::Validate;

#[test]
fn test_register_request_validation_email() {
    let mut req = RegisterRequest {
        email: "invalid".to_string(),
        username: "valid_user".to_string(),
        password: "SecurePass123!".to_string(),
    };
    assert!(req.validate().is_err());

    req.email = "user@example.com".to_string();
    assert!(req.validate().is_ok());
}

#[test]
fn test_register_request_validation_username_bounds() {
    let mut req = RegisterRequest {
        email: "user@example.com".to_string(),
        username: "ab".to_string(),
        password: "SecurePass123!".to_string(),
    };
    assert!(req.validate().is_err());
    req.username = "a".repeat(33);
    assert!(req.validate().is_err());
    req.username = "good_name".to_string();
    assert!(req.validate().is_ok());
}

#[test]
fn test_register_request_validation_password_len() {
    let mut req = RegisterRequest {
        email: "user@example.com".to_string(),
        username: "valid_user".to_string(),
        password: "short1!".to_string(),
    };
    assert!(req.validate().is_err());
    req.password = "SecurePass123!".to_string();
    assert!(req.validate().is_ok());
}

#[test]
fn test_login_request_validation() {
    let mut req = LoginRequest {
        email: "invalid".to_string(),
        password: "p".to_string(),
    };
    assert!(req.validate().is_err());
    req.email = "user@example.com".to_string();
    assert!(req.validate().is_ok());
}
