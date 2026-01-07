use serde::Serialize;
use serde_json;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
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
    
    // Verify the JSON contains the correct camelCase key
    assert!(json.contains("\"authorAccountType\":\"alias\""), "JSON should contain authorAccountType");
    assert!(json.contains("\"userId\":\"test123\""), "JSON should contain userId");
}
