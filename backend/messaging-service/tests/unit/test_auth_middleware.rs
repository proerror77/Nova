use messaging_service::middleware::auth::verify_jwt;

#[tokio::test]
async fn rejects_invalid_token() {
    // invalid token should return Err
    let token = "not_a_jwt";
    let res = verify_jwt(token).await;
    assert!(res.is_err(), "invalid token must be rejected");
}
