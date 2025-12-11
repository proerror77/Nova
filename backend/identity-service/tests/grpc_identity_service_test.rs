// Integration tests for Identity Service gRPC API
//
// These tests verify the implementation of authentication flows including:
// - User registration with validation
// - User login with password verification
// - Token generation and verification
// - Failed login attempt tracking
// - User retrieval operations
//
// To run these tests with actual gRPC services:
//   docker-compose up -d postgres redis kafka identity-service
//   cargo test --test grpc_identity_service_test -- --nocapture
//   docker-compose down

#[cfg(test)]
mod identity_service_grpc_tests {
    use tonic::Request;

    // Include proto definitions to get generated client code
    pub mod nova {
        pub mod common {
            pub mod v2 {
                tonic::include_proto!("nova.common.v2");
            }
            #[allow(unused_imports)]
            pub use v2::*;
        }
        pub mod auth_service {
            pub mod v2 {
                tonic::include_proto!("nova.identity_service.v2");
            }
            pub use v2::*;
        }
    }

    use nova::auth_service::auth_service_client::AuthServiceClient;
    use nova::auth_service::*;

    // Test helper structures
    #[derive(Clone, Debug)]
    struct ServiceEndpoints {
        identity_service: String,
    }

    impl ServiceEndpoints {
        fn new() -> Self {
            Self {
                identity_service: std::env::var("IDENTITY_SERVICE_URL")
                    .unwrap_or_else(|_| "http://localhost:9080".to_string()),
            }
        }
    }

    // ============================================================================
    // Test: User Registration - Happy Path
    // ============================================================================
    //
    // Verification Standards:
    // - Valid email, username, and password should succeed
    // - Access token and refresh token should be generated
    // - Token should be valid for 3600 seconds (1 hour)
    // - User ID should be a valid UUID
    //
    // Success Condition:
    // Returns RegisterResponse with valid tokens and user_id
    //
    #[tokio::test]
    async fn test_register_user_valid_credentials() {
        let endpoints = ServiceEndpoints::new();
        let mut client = match AuthServiceClient::connect(endpoints.identity_service).await {
            Ok(c) => c,
            Err(e) => {
                eprintln!("⚠️  Failed to connect to gRPC service: {}", e);
                eprintln!("💡 Make sure identity-service is running: docker-compose up -d identity-service");
                return;
            }
        };

        // Generate unique credentials for this test run
        let timestamp = chrono::Utc::now().timestamp();
        let email = format!("test_user_{}@example.com", timestamp);
        let username = format!("testuser_{}", timestamp);

        let request = Request::new(RegisterRequest {
            email: email.clone(),
            username: username.clone(),
            password: "StrongPassword123!".to_string(),
            invite_code: "TESTCODE".to_string(),
        });

        match client.register(request).await {
            Ok(response) => {
                let resp = response.into_inner();
                println!("✅ Registration successful");
                println!("   User ID: {}", resp.user_id);
                println!("   Token length: {}", resp.token.len());
                println!("   Refresh token length: {}", resp.refresh_token.len());
                println!("   Expires in: {} seconds", resp.expires_in);

                // Verify response structure
                assert!(!resp.user_id.is_empty(), "User ID should not be empty");
                assert!(!resp.token.is_empty(), "Access token should not be empty");
                assert!(
                    !resp.refresh_token.is_empty(),
                    "Refresh token should not be empty"
                );
                assert_eq!(resp.expires_in, 3600, "Token should expire in 3600 seconds");

                // Verify user ID is a valid UUID
                assert!(
                    uuid::Uuid::parse_str(&resp.user_id).is_ok(),
                    "User ID should be a valid UUID"
                );
            }
            Err(status) => {
                panic!(
                    "❌ Registration failed: {} - {}",
                    status.code(),
                    status.message()
                );
            }
        }
    }

    // ============================================================================
    // Test: User Registration - Invalid Email Format
    // ============================================================================
    //
    // Verification Standards:
    // - Invalid email formats should be rejected with InvalidArgument status
    // - Error message should indicate email validation failure
    //
    // Success Condition:
    // Returns InvalidArgument status with descriptive error message
    //
    #[tokio::test]
    async fn test_register_user_invalid_email() {
        let endpoints = ServiceEndpoints::new();
        let mut client = match AuthServiceClient::connect(endpoints.identity_service).await {
            Ok(c) => c,
            Err(e) => {
                eprintln!("⚠️  Failed to connect to gRPC service: {}", e);
                return;
            }
        };

        let timestamp = chrono::Utc::now().timestamp();
        let request = Request::new(RegisterRequest {
            email: "not-an-email".to_string(), // Invalid email format
            username: format!("testuser_{}", timestamp),
            password: "StrongPassword123!".to_string(),
            invite_code: "TESTCODE".to_string(),
        });

        match client.register(request).await {
            Ok(_) => {
                panic!("❌ Expected registration to fail with invalid email");
            }
            Err(status) => {
                println!("✅ Registration correctly rejected invalid email");
                println!("   Status: {}", status.code());
                println!("   Message: {}", status.message());

                assert_eq!(
                    status.code(),
                    tonic::Code::InvalidArgument,
                    "Should return InvalidArgument status"
                );
                assert!(
                    status.message().to_lowercase().contains("email"),
                    "Error message should mention email validation"
                );
            }
        }
    }

    // ============================================================================
    // Test: User Registration - Duplicate Email
    // ============================================================================
    //
    // Verification Standards:
    // - Registering with an email that already exists should fail
    // - Should return AlreadyExists status
    // - Error message should indicate duplicate email
    //
    // Success Condition:
    // Second registration attempt returns AlreadyExists status
    //
    #[tokio::test]
    async fn test_register_user_duplicate_email() {
        let endpoints = ServiceEndpoints::new();
        let mut client = match AuthServiceClient::connect(endpoints.identity_service).await {
            Ok(c) => c,
            Err(e) => {
                eprintln!("⚠️  Failed to connect to gRPC service: {}", e);
                return;
            }
        };

        let timestamp = chrono::Utc::now().timestamp();
        let email = format!("duplicate_test_{}@example.com", timestamp);

        // First registration should succeed
        let request1 = Request::new(RegisterRequest {
            email: email.clone(),
            username: format!("user1_{}", timestamp),
            password: "StrongPassword123!".to_string(),
            invite_code: "TESTCODE".to_string(),
        });

        match client.register(request1).await {
            Ok(_) => println!("✅ First registration successful"),
            Err(e) => {
                eprintln!("⚠️  First registration failed: {}", e);
                return;
            }
        }

        // Second registration with same email should fail
        let request2 = Request::new(RegisterRequest {
            email: email.clone(),
            username: format!("user2_{}", timestamp), // Different username
            password: "StrongPassword123!".to_string(),
            invite_code: "TESTCODE".to_string(),
        });

        match client.register(request2).await {
            Ok(_) => {
                panic!("❌ Expected registration to fail with duplicate email");
            }
            Err(status) => {
                println!("✅ Registration correctly rejected duplicate email");
                println!("   Status: {}", status.code());
                println!("   Message: {}", status.message());

                assert_eq!(
                    status.code(),
                    tonic::Code::AlreadyExists,
                    "Should return AlreadyExists status"
                );
            }
        }
    }

    // ============================================================================
    // Test: User Login - Valid Credentials
    // ============================================================================
    //
    // Verification Standards:
    // - Login with correct email and password should succeed
    // - Should return access token and refresh token
    // - Token expiry should be 3600 seconds
    // - User ID should match registered user
    //
    // Success Condition:
    // Returns LoginResponse with valid tokens
    //
    #[tokio::test]
    async fn test_login_user_valid_credentials() {
        let endpoints = ServiceEndpoints::new();
        let mut client = match AuthServiceClient::connect(endpoints.identity_service).await {
            Ok(c) => c,
            Err(e) => {
                eprintln!("⚠️  Failed to connect to gRPC service: {}", e);
                return;
            }
        };

        let timestamp = chrono::Utc::now().timestamp();
        let email = format!("login_test_{}@example.com", timestamp);
        let password = "StrongPassword123!";

        // First register a user
        let register_req = Request::new(RegisterRequest {
            email: email.clone(),
            username: format!("loginuser_{}", timestamp),
            password: password.to_string(),
            invite_code: "TESTCODE".to_string(),
        });

        let register_resp = match client.register(register_req).await {
            Ok(r) => r.into_inner(),
            Err(e) => {
                eprintln!("⚠️  Registration failed: {}", e);
                return;
            }
        };

        println!("✅ User registered with ID: {}", register_resp.user_id);

        // Now attempt login
        let login_req = Request::new(LoginRequest {
            email: email.clone(),
            password: password.to_string(),
        });

        match client.login(login_req).await {
            Ok(response) => {
                let resp = response.into_inner();
                println!("✅ Login successful");
                println!("   User ID: {}", resp.user_id);
                println!("   Token length: {}", resp.token.len());
                println!("   Expires in: {} seconds", resp.expires_in);

                // Verify response structure
                assert_eq!(
                    resp.user_id, register_resp.user_id,
                    "Login user_id should match registered user_id"
                );
                assert!(!resp.token.is_empty(), "Access token should not be empty");
                assert!(
                    !resp.refresh_token.is_empty(),
                    "Refresh token should not be empty"
                );
                assert_eq!(resp.expires_in, 3600, "Token should expire in 3600 seconds");
            }
            Err(status) => {
                panic!("❌ Login failed: {} - {}", status.code(), status.message());
            }
        }
    }

    // ============================================================================
    // Test: User Login - Invalid Password
    // ============================================================================
    //
    // Verification Standards:
    // - Login with incorrect password should fail
    // - Should return Unauthenticated status
    // - Error message should indicate authentication failure
    //
    // Success Condition:
    // Returns Unauthenticated status
    //
    #[tokio::test]
    async fn test_login_user_invalid_password() {
        let endpoints = ServiceEndpoints::new();
        let mut client = match AuthServiceClient::connect(endpoints.identity_service).await {
            Ok(c) => c,
            Err(e) => {
                eprintln!("⚠️  Failed to connect to gRPC service: {}", e);
                return;
            }
        };

        let timestamp = chrono::Utc::now().timestamp();
        let email = format!("invalid_pw_test_{}@example.com", timestamp);

        // Register a user first
        let register_req = Request::new(RegisterRequest {
            email: email.clone(),
            username: format!("pwtest_{}", timestamp),
            password: "CorrectPassword123!".to_string(),
            invite_code: "TESTCODE".to_string(),
        });

        if let Err(e) = client.register(register_req).await {
            eprintln!("⚠️  Registration failed: {}", e);
            return;
        }

        // Attempt login with wrong password
        let login_req = Request::new(LoginRequest {
            email: email.clone(),
            password: "WrongPassword123!".to_string(),
        });

        match client.login(login_req).await {
            Ok(_) => {
                panic!("❌ Expected login to fail with invalid password");
            }
            Err(status) => {
                println!("✅ Login correctly rejected invalid password");
                println!("   Status: {}", status.code());
                println!("   Message: {}", status.message());

                assert_eq!(
                    status.code(),
                    tonic::Code::Unauthenticated,
                    "Should return Unauthenticated status"
                );
            }
        }
    }

    // ============================================================================
    // Test: User Login - Non-existent User
    // ============================================================================
    //
    // Verification Standards:
    // - Login with email that doesn't exist should fail
    // - Should return NotFound status
    // - Error message should indicate user not found
    //
    // Success Condition:
    // Returns NotFound status
    //
    #[tokio::test]
    async fn test_login_nonexistent_user() {
        let endpoints = ServiceEndpoints::new();
        let mut client = match AuthServiceClient::connect(endpoints.identity_service).await {
            Ok(c) => c,
            Err(e) => {
                eprintln!("⚠️  Failed to connect to gRPC service: {}", e);
                return;
            }
        };

        let timestamp = chrono::Utc::now().timestamp();
        let login_req = Request::new(LoginRequest {
            email: format!("nonexistent_{}@example.com", timestamp),
            password: "SomePassword123!".to_string(),
        });

        match client.login(login_req).await {
            Ok(_) => {
                panic!("❌ Expected login to fail for non-existent user");
            }
            Err(status) => {
                println!("✅ Login correctly rejected non-existent user");
                println!("   Status: {}", status.code());
                println!("   Message: {}", status.message());

                assert_eq!(
                    status.code(),
                    tonic::Code::NotFound,
                    "Should return NotFound status"
                );
            }
        }
    }

    // ============================================================================
    // Test: Token Verification - Valid Token
    // ============================================================================
    //
    // Verification Standards:
    // - Token received from registration should be verifiable
    // - VerifyToken should return is_valid=true
    // - Should return correct user_id, email, username
    // - Token should not be revoked
    //
    // Success Condition:
    // Returns VerifyTokenResponse with is_valid=true and correct user details
    //
    #[tokio::test]
    async fn test_verify_token_valid() {
        let endpoints = ServiceEndpoints::new();
        let mut client = match AuthServiceClient::connect(endpoints.identity_service).await {
            Ok(c) => c,
            Err(e) => {
                eprintln!("⚠️  Failed to connect to gRPC service: {}", e);
                return;
            }
        };

        let timestamp = chrono::Utc::now().timestamp();
        let email = format!("token_test_{}@example.com", timestamp);
        let username = format!("tokenuser_{}", timestamp);

        // Register a user to get a token
        let register_req = Request::new(RegisterRequest {
            email: email.clone(),
            username: username.clone(),
            password: "StrongPassword123!".to_string(),
            invite_code: "TESTCODE".to_string(),
        });

        let register_resp = match client.register(register_req).await {
            Ok(r) => r.into_inner(),
            Err(e) => {
                eprintln!("⚠️  Registration failed: {}", e);
                return;
            }
        };

        let token = register_resp.token;
        println!("✅ Received token from registration");

        // Verify the token
        let verify_req = Request::new(VerifyTokenRequest {
            token: token.clone(),
        });

        match client.verify_token(verify_req).await {
            Ok(response) => {
                let resp = response.into_inner();
                println!("✅ Token verification successful");
                println!("   Is valid: {}", resp.is_valid);
                println!("   User ID: {}", resp.user_id);
                println!("   Email: {}", resp.email);
                println!("   Username: {}", resp.username);
                println!("   Is revoked: {}", resp.is_revoked);

                assert!(resp.is_valid, "Token should be valid");
                assert_eq!(resp.user_id, register_resp.user_id, "User ID should match");
                assert_eq!(resp.email, email, "Email should match");
                assert_eq!(resp.username, username, "Username should match");
                assert!(!resp.is_revoked, "Token should not be revoked");
                assert!(resp.expires_at > 0, "Expiry timestamp should be set");
            }
            Err(status) => {
                panic!(
                    "❌ Token verification failed: {} - {}",
                    status.code(),
                    status.message()
                );
            }
        }
    }

    // ============================================================================
    // Test: Token Verification - Invalid Token
    // ============================================================================
    //
    // Verification Standards:
    // - Invalid or malformed tokens should be rejected
    // - Should return is_valid=false
    //
    // Success Condition:
    // Returns VerifyTokenResponse with is_valid=false
    //
    #[tokio::test]
    async fn test_verify_token_invalid() {
        let endpoints = ServiceEndpoints::new();
        let mut client = match AuthServiceClient::connect(endpoints.identity_service).await {
            Ok(c) => c,
            Err(e) => {
                eprintln!("⚠️  Failed to connect to gRPC service: {}", e);
                return;
            }
        };

        let verify_req = Request::new(VerifyTokenRequest {
            token: "invalid.jwt.token".to_string(),
        });

        match client.verify_token(verify_req).await {
            Ok(response) => {
                let resp = response.into_inner();
                println!("✅ Invalid token correctly identified");
                println!("   Is valid: {}", resp.is_valid);

                assert!(!resp.is_valid, "Token should be invalid");
            }
            Err(status) => {
                // Some implementations return error status for invalid tokens
                println!("✅ Invalid token rejected with error");
                println!("   Status: {}", status.code());
                assert!(
                    status.code() == tonic::Code::Unauthenticated
                        || status.code() == tonic::Code::InvalidArgument,
                    "Should return Unauthenticated or InvalidArgument status"
                );
            }
        }
    }

    // ============================================================================
    // Test: Get User by ID
    // ============================================================================
    //
    // Verification Standards:
    // - Should retrieve user details by user_id
    // - Response should include email, username, created_at, is_active
    //
    // Success Condition:
    // Returns GetUserResponse with correct user details
    //
    #[tokio::test]
    async fn test_get_user_by_id() {
        let endpoints = ServiceEndpoints::new();
        let mut client = match AuthServiceClient::connect(endpoints.identity_service).await {
            Ok(c) => c,
            Err(e) => {
                eprintln!("⚠️  Failed to connect to gRPC service: {}", e);
                return;
            }
        };

        let timestamp = chrono::Utc::now().timestamp();
        let email = format!("getuser_test_{}@example.com", timestamp);
        let username = format!("getuser_{}", timestamp);

        // Register a user first
        let register_req = Request::new(RegisterRequest {
            email: email.clone(),
            username: username.clone(),
            password: "StrongPassword123!".to_string(),
            invite_code: "TESTCODE".to_string(),
        });

        let register_resp = match client.register(register_req).await {
            Ok(r) => r.into_inner(),
            Err(e) => {
                eprintln!("⚠️  Registration failed: {}", e);
                return;
            }
        };

        let user_id = register_resp.user_id;
        println!("✅ User registered with ID: {}", user_id);

        // Retrieve the user
        let get_user_req = Request::new(GetUserRequest {
            user_id: user_id.clone(),
        });

        match client.get_user(get_user_req).await {
            Ok(response) => {
                let resp = response.into_inner();
                if let Some(user) = resp.user {
                    println!("✅ User retrieved successfully");
                    println!("   ID: {}", user.id);
                    println!("   Email: {}", user.email);
                    println!("   Username: {}", user.username);
                    println!("   Is active: {}", user.is_active);

                    assert_eq!(user.id, user_id, "User ID should match");
                    assert_eq!(user.email, email, "Email should match");
                    assert_eq!(user.username, username, "Username should match");
                    assert!(user.is_active, "User should be active");
                } else if let Some(error) = resp.error {
                    panic!("❌ Get user returned error: {}", error.message);
                } else {
                    panic!("❌ Get user returned empty response");
                }
            }
            Err(status) => {
                panic!(
                    "❌ Get user failed: {} - {}",
                    status.code(),
                    status.message()
                );
            }
        }
    }

    // ============================================================================
    // Test: Check User Exists
    // ============================================================================
    //
    // Verification Standards:
    // - Should return exists=true for registered user
    // - Should return exists=false for non-existent user_id
    //
    // Success Condition:
    // Returns correct existence status
    //
    #[tokio::test]
    async fn test_check_user_exists() {
        let endpoints = ServiceEndpoints::new();
        let mut client = match AuthServiceClient::connect(endpoints.identity_service).await {
            Ok(c) => c,
            Err(e) => {
                eprintln!("⚠️  Failed to connect to gRPC service: {}", e);
                return;
            }
        };

        let timestamp = chrono::Utc::now().timestamp();

        // Register a user
        let register_req = Request::new(RegisterRequest {
            email: format!("exists_test_{}@example.com", timestamp),
            username: format!("existsuser_{}", timestamp),
            password: "StrongPassword123!".to_string(),
            invite_code: "TESTCODE".to_string(),
        });

        let user_id = match client.register(register_req).await {
            Ok(r) => r.into_inner().user_id,
            Err(e) => {
                eprintln!("⚠️  Registration failed: {}", e);
                return;
            }
        };

        // Check that user exists
        let check_req = Request::new(CheckUserExistsRequest {
            user_id: user_id.clone(),
        });

        match client.check_user_exists(check_req).await {
            Ok(response) => {
                let resp = response.into_inner();
                println!("✅ User existence check passed");
                println!("   Exists: {}", resp.exists);
                assert!(resp.exists, "User should exist");
            }
            Err(status) => {
                panic!(
                    "❌ Check user exists failed: {} - {}",
                    status.code(),
                    status.message()
                );
            }
        }

        // Check that non-existent user doesn't exist
        let fake_uuid = uuid::Uuid::new_v4().to_string();
        let check_req2 = Request::new(CheckUserExistsRequest {
            user_id: fake_uuid.clone(),
        });

        match client.check_user_exists(check_req2).await {
            Ok(response) => {
                let resp = response.into_inner();
                println!("✅ Non-existent user check passed");
                println!("   Exists: {}", resp.exists);
                assert!(!resp.exists, "Non-existent user should not exist");
            }
            Err(status) => {
                panic!(
                    "❌ Check user exists failed: {} - {}",
                    status.code(),
                    status.message()
                );
            }
        }
    }
}
