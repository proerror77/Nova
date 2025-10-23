use messaging_service::middleware::authorization::authorize;

#[test]
fn denies_when_role_missing() {
    let roles = vec!["member".to_string()];
    assert!(!authorize("admin", &roles));
}
