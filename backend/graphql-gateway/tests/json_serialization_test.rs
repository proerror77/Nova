use serde::Serialize;
use serde_json;

#[derive(Debug, Serialize)]
#[serde(rename_all = "snake_case")]
struct TestFeedPost {
    author_account_type: String,
    user_id: String,
}

#[test]
fn test_author_account_type_serialization() {
    let post = TestFeedPost {
        author_account_type: "alias".to_string(),
        user_id: "test123".to_string(),
    };
    let json = serde_json::to_string(&post).unwrap();
    println!("JSON: {}", json);

    // Verify the JSON contains the correct snake_case keys (for iOS .convertFromSnakeCase decoder)
    assert!(json.contains("\"author_account_type\":\"alias\""), "JSON should contain author_account_type (snake_case)");
    assert!(json.contains("\"user_id\":\"test123\""), "JSON should contain user_id (snake_case)");
}
