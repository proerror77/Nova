# 测试覆盖率修复方案 - 代码示例

**目标**: 在2周内将关键服务的测试覆盖率从 0% 提升到可接受水平

---

## 1. P0 修复：Identity Service - 认证流程测试

### 1.1 问题诊断

```
当前状态:
- identity-service 是 auth-service 的替代品
- 但只有4行配置单元测试
- 零gRPC集成测试
- 核心认证流程完全未验证

风险:
- JWT生成/验证逻辑无测试
- 登录/注册流程未端到端验证
- Token刷新逻辑无测试
```

### 1.2 修复步骤

#### 第1步：创建基础集成测试框架

**文件**: `/Users/proerror/Documents/nova/backend/identity-service/tests/identity_grpc_integration_test.rs`

```rust
#[cfg(test)]
mod identity_integration_tests {
    use identity_service::grpc::IdentityServiceServer;
    use tonic::transport::Server;
    use tokio::sync::mpsc;
    use uuid::Uuid;
    use std::net::SocketAddr;

    /// 测试服务器启动工具
    struct TestServer {
        addr: SocketAddr,
        shutdown_tx: mpsc::Sender<()>,
    }

    impl TestServer {
        async fn start() -> Self {
            let addr = "127.0.0.1:0".parse().unwrap();

            let service = IdentityServiceServer::new(/* 初始化服务 */);

            let (shutdown_tx, shutdown_rx) = mpsc::channel(1);

            // 在后台启动服务器
            tokio::spawn(async move {
                Server::builder()
                    .add_service(service)
                    .serve_with_shutdown(addr, async {
                        let _ = shutdown_rx.recv().await;
                    })
                    .await
                    .expect("Server failed");
            });

            Self { addr, shutdown_tx }
        }

        async fn shutdown(self) {
            let _ = self.shutdown_tx.send(()).await;
        }
    }

    #[tokio::test]
    async fn test_user_registration_success() {
        let server = TestServer::start().await;

        // 创建客户端
        let mut client = IdentityServiceClient::connect(
            format!("http://{}", server.addr)
        )
        .await
        .expect("Failed to connect");

        // 执行注册请求
        let request = RegisterRequest {
            email: "test@example.com".to_string(),
            password: "SecurePass123!".to_string(),
            username: "testuser".to_string(),
        };

        let response = client.register(request).await;

        // 验证成功
        assert!(response.is_ok());
        let result = response.unwrap().into_inner();
        assert!(!result.user_id.is_empty());
        assert!(!result.access_token.is_empty());

        server.shutdown().await;
    }

    #[tokio::test]
    async fn test_user_registration_duplicate_email() {
        let server = TestServer::start().await;

        let mut client = IdentityServiceClient::connect(
            format!("http://{}", server.addr)
        )
        .await
        .unwrap();

        // 第一次注册成功
        let request1 = RegisterRequest {
            email: "duplicate@example.com".to_string(),
            password: "Pass123!".to_string(),
            username: "user1".to_string(),
        };

        let _ = client.register(request1).await;

        // 第二次用同样email应该失败
        let request2 = RegisterRequest {
            email: "duplicate@example.com".to_string(),
            password: "DifferentPass123!".to_string(),
            username: "user2".to_string(),
        };

        let response = client.register(request2).await;
        assert!(response.is_err());

        server.shutdown().await;
    }

    #[tokio::test]
    async fn test_login_with_valid_credentials() {
        let server = TestServer::start().await;
        let mut client = IdentityServiceClient::connect(
            format!("http://{}", server.addr)
        )
        .await
        .unwrap();

        // 先注册用户
        let email = "login_test@example.com";
        let password = "SecurePass123!";

        client.register(RegisterRequest {
            email: email.to_string(),
            password: password.to_string(),
            username: "loginuser".to_string(),
        })
        .await
        .unwrap();

        // 现在尝试登录
        let login_response = client.login(LoginRequest {
            email: email.to_string(),
            password: password.to_string(),
        })
        .await;

        assert!(login_response.is_ok());
        let result = login_response.unwrap().into_inner();
        assert!(!result.access_token.is_empty());
        assert!(!result.refresh_token.is_empty());
    }

    #[tokio::test]
    async fn test_login_with_invalid_password() {
        let server = TestServer::start().await;
        let mut client = IdentityServiceClient::connect(
            format!("http://{}", server.addr)
        )
        .await
        .unwrap();

        let email = "wrongpass_test@example.com";

        client.register(RegisterRequest {
            email: email.to_string(),
            password: "CorrectPass123!".to_string(),
            username: "wrongpassuser".to_string(),
        })
        .await
        .unwrap();

        // 用错误密码登录应该失败
        let login_response = client.login(LoginRequest {
            email: email.to_string(),
            password: "WrongPass123!".to_string(),
        })
        .await;

        assert!(login_response.is_err());
    }

    #[tokio::test]
    async fn test_verify_token_valid() {
        let server = TestServer::start().await;
        let mut client = IdentityServiceClient::connect(
            format!("http://{}", server.addr)
        )
        .await
        .unwrap();

        // 注册并登录获取token
        let reg_response = client.register(RegisterRequest {
            email: "token_test@example.com".to_string(),
            password: "Pass123!".to_string(),
            username: "tokenuser".to_string(),
        })
        .await
        .unwrap();

        let token = reg_response.into_inner().access_token;

        // 验证token
        let verify_response = client.verify_token(VerifyTokenRequest {
            token: token.clone(),
        })
        .await;

        assert!(verify_response.is_ok());
        let result = verify_response.unwrap().into_inner();
        assert!(!result.user_id.is_empty());
        assert_eq!(result.email, "token_test@example.com");
    }

    #[tokio::test]
    async fn test_verify_token_invalid() {
        let server = TestServer::start().await;
        let mut client = IdentityServiceClient::connect(
            format!("http://{}", server.addr)
        )
        .await
        .unwrap();

        // 用无效token应该失败
        let verify_response = client.verify_token(VerifyTokenRequest {
            token: "invalid.token.here".to_string(),
        })
        .await;

        assert!(verify_response.is_err());
    }

    #[tokio::test]
    async fn test_refresh_token() {
        let server = TestServer::start().await;
        let mut client = IdentityServiceClient::connect(
            format!("http://{}", server.addr)
        )
        .await
        .unwrap();

        // 登录获取刷新token
        client.register(RegisterRequest {
            email: "refresh_test@example.com".to_string(),
            password: "Pass123!".to_string(),
            username: "refreshuser".to_string(),
        })
        .await
        .unwrap();

        let login_response = client.login(LoginRequest {
            email: "refresh_test@example.com".to_string(),
            password: "Pass123!".to_string(),
        })
        .await
        .unwrap();

        let refresh_token = login_response.into_inner().refresh_token;

        // 使用刷新token获取新的access token
        let refresh_response = client.refresh_token(RefreshTokenRequest {
            refresh_token,
        })
        .await;

        assert!(refresh_response.is_ok());
        let result = refresh_response.unwrap().into_inner();
        assert!(!result.access_token.is_empty());
    }
}
```

#### 第2步：JWT验证单元测试

**文件**: `/Users/proerror/Documents/nova/backend/identity-service/tests/jwt_validation_test.rs`

```rust
#[cfg(test)]
mod jwt_tests {
    use identity_service::security::jwt::{
        JwtManager, Claims, JwtError
    };
    use chrono::{Duration, Utc};

    fn setup_jwt_manager() -> JwtManager {
        JwtManager::new("test-secret-key-for-testing-only".to_string())
    }

    #[test]
    fn test_generate_token_success() {
        let manager = setup_jwt_manager();
        let user_id = "user123";

        let token = manager.generate_token(
            user_id.to_string(),
            "user@example.com".to_string(),
            Duration::hours(1)
        );

        assert!(token.is_ok());
        let token_str = token.unwrap();
        assert!(!token_str.is_empty());

        // Token格式: "header.payload.signature"
        let parts: Vec<&str> = token_str.split('.').collect();
        assert_eq!(parts.len(), 3);
    }

    #[test]
    fn test_verify_token_valid() {
        let manager = setup_jwt_manager();
        let user_id = "user123";

        let token = manager.generate_token(
            user_id.to_string(),
            "user@example.com".to_string(),
            Duration::hours(1)
        )
        .unwrap();

        let claims = manager.verify_token(&token);

        assert!(claims.is_ok());
        let claims_data = claims.unwrap();
        assert_eq!(claims_data.sub, user_id);
        assert_eq!(claims_data.email, "user@example.com");
    }

    #[test]
    fn test_verify_token_invalid_signature() {
        let manager = setup_jwt_manager();

        // 生成有效token
        let token = manager.generate_token(
            "user123".to_string(),
            "user@example.com".to_string(),
            Duration::hours(1)
        )
        .unwrap();

        // 篡改token（改变最后一个字符）
        let tampered = format!("{}X", &token[..token.len()-1]);

        let result = manager.verify_token(&tampered);

        assert!(result.is_err());
        match result.unwrap_err() {
            JwtError::InvalidSignature => {}, // 预期
            _ => panic!("Expected InvalidSignature error"),
        }
    }

    #[test]
    fn test_verify_token_expired() {
        let manager = setup_jwt_manager();

        // 生成已过期的token（负时间间隔）
        let token = manager.generate_token(
            "user123".to_string(),
            "user@example.com".to_string(),
            Duration::hours(-1) // 已过期
        )
        .unwrap();

        let result = manager.verify_token(&token);

        assert!(result.is_err());
        match result.unwrap_err() {
            JwtError::ExpiredToken => {}, // 预期
            _ => panic!("Expected ExpiredToken error"),
        }
    }

    #[test]
    fn test_verify_token_malformed() {
        let manager = setup_jwt_manager();

        let malformed_tokens = vec![
            "not-a-token",
            "only.two.parts",
            "a.b.c.d.e", // 太多点
            "",
            "...".to_string(), // 仅点
        ];

        for token in malformed_tokens {
            let result = manager.verify_token(token);
            assert!(result.is_err(), "Token '{}' should be invalid", token);
        }
    }

    #[test]
    fn test_extract_claims_from_token() {
        let manager = setup_jwt_manager();

        let token = manager.generate_token(
            "user456".to_string(),
            "another@example.com".to_string(),
            Duration::hours(2)
        )
        .unwrap();

        let claims = manager.verify_token(&token).unwrap();

        // 验证声明内容
        assert_eq!(claims.sub, "user456");
        assert_eq!(claims.email, "another@example.com");
        assert!(claims.exp > Utc::now().timestamp() as usize);
    }

    #[test]
    fn test_token_expiration_times() {
        let manager = setup_jwt_manager();
        let user_id = "user789";

        // 测试不同的过期时间
        let durations = vec![
            Duration::minutes(1),
            Duration::hours(1),
            Duration::days(1),
            Duration::days(7),
        ];

        for duration in durations {
            let token = manager.generate_token(
                user_id.to_string(),
                "user@example.com".to_string(),
                duration
            )
            .unwrap();

            let claims = manager.verify_token(&token).unwrap();
            let exp_time = claims.exp as i64;
            let now = Utc::now().timestamp();
            let expected_diff = duration.num_seconds();

            // 允许1秒的时钟偏差
            assert!((exp_time - now - expected_diff).abs() < 2);
        }
    }
}
```

---

## 2. P0 修复：Graph Service - Neo4j 集成测试

### 2.1 问题诊断

```
当前状态:
- graph-service: 1215行代码，0个集成测试
- Neo4j 查询完全未验证
- 无超时配置（关键性能问题）

风险:
- 任何Neo4j bug直接导致系统崩溃
- 无限挂起的查询会耗尽连接池
```

### 2.2 修复步骤

#### 第1步：添加超时配置

**文件修改**: `/Users/proerror/Documents/nova/backend/graph-service/src/repository/graph_repository.rs`

```rust
// 当前代码（有问题）
pub async fn new(uri: &str, user: &str, password: &str) -> Result<Self> {
    let graph = Graph::new(uri, user, password)
        .await
        .context("Failed to connect to Neo4j")?;
    Ok(Self {
        graph: Arc::new(graph),
    })
}

// 修复后的代码
use std::time::Duration;

pub struct GraphRepository {
    graph: Arc<Graph>,
    query_timeout: Duration,
}

impl GraphRepository {
    pub async fn new(uri: &str, user: &str, password: &str) -> Result<Self> {
        let graph = Graph::new(uri, user, password)
            .await
            .context("Failed to connect to Neo4j")?;

        Ok(Self {
            graph: Arc::new(graph),
            query_timeout: Duration::from_secs(5), // 5秒查询超时
        })
    }

    pub async fn health_check(&self) -> Result<bool> {
        let result = tokio::time::timeout(
            self.query_timeout,
            self.graph.execute(query("RETURN 1 AS health"))
        )
        .await
        .context("Health check query timed out")?
        .context("Health check query failed")?;

        if let Some(row) = result.rows().next() {
            let health: i64 = row.get("health").unwrap_or(0);
            Ok(health == 1)
        } else {
            Ok(false)
        }
    }

    // 为每个查询方法添加超时
    pub async fn create_follow(&self, follower_id: Uuid, followee_id: Uuid) -> Result<()> {
        if follower_id == followee_id {
            return Err(anyhow::anyhow!("Cannot follow self"));
        }

        self.ensure_user_node(follower_id).await?;
        self.ensure_user_node(followee_id).await?;

        let cypher = r#"
            MATCH (a:User {id: $follower}), (b:User {id: $followee})
            MERGE (a)-[r:FOLLOWS]->(b)
            ON CREATE SET r.created_at = timestamp()
            RETURN r.created_at
        "#;

        let future = self.graph.execute(
            query(cypher)
                .param("follower", follower_id.to_string())
                .param("followee", followee_id.to_string()),
        );

        // ✅ 添加超时保护
        tokio::time::timeout(self.query_timeout, future)
            .await
            .context("Create follow query timed out")?
            .context("Failed to create FOLLOWS edge")?;

        debug!("Created FOLLOWS: {} -> {}", follower_id, followee_id);
        Ok(())
    }
}
```

#### 第2步：创建集成测试

**文件**: `/Users/proerror/Documents/nova/backend/graph-service/tests/graph_integration_test.rs`

```rust
#[cfg(test)]
mod graph_integration_tests {
    use graph_service::repository::GraphRepository;
    use testcontainers::clients;
    use testcontainers::images::neo4j;
    use uuid::Uuid;

    /// 测试容器管理
    struct Neo4jTestEnv {
        _container: testcontainers::Container<neo4j::Neo4j>,
        url: String,
    }

    impl Neo4jTestEnv {
        async fn new() -> Self {
            let docker = clients::Cli::default();

            // 启动Neo4j容器
            let container = docker.run(
                neo4j::Neo4j::default()
                    .with_admin_password("testpass")
            );

            let port = container.get_host_port_ipv4(7687);
            let url = format!("bolt://127.0.0.1:{}", port);

            // 等待Neo4j启动
            tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;

            Self {
                _container: container,
                url,
            }
        }
    }

    #[tokio::test]
    async fn test_create_follow_edge() {
        let env = Neo4jTestEnv::new().await;

        let repo = GraphRepository::new(&env.url, "neo4j", "testpass")
            .await
            .expect("Failed to initialize repository");

        let user1 = Uuid::new_v4();
        let user2 = Uuid::new_v4();

        // 创建关注关系
        let result = repo.create_follow(user1, user2).await;

        assert!(result.is_ok(), "Failed to create follow");
    }

    #[tokio::test]
    async fn test_cannot_follow_self() {
        let env = Neo4jTestEnv::new().await;

        let repo = GraphRepository::new(&env.url, "neo4j", "testpass")
            .await
            .expect("Failed to initialize repository");

        let user = Uuid::new_v4();

        // 尝试关注自己应该失败
        let result = repo.create_follow(user, user).await;

        assert!(result.is_err(), "Should not allow following self");
    }

    #[tokio::test]
    async fn test_delete_follow_edge() {
        let env = Neo4jTestEnv::new().await;

        let repo = GraphRepository::new(&env.url, "neo4j", "testpass")
            .await
            .expect("Failed to initialize repository");

        let user1 = Uuid::new_v4();
        let user2 = Uuid::new_v4();

        // 创建关注关系
        repo.create_follow(user1, user2)
            .await
            .expect("Failed to create follow");

        // 删除关注关系
        let result = repo.delete_follow(user1, user2).await;

        assert!(result.is_ok(), "Failed to delete follow");
    }

    #[tokio::test]
    async fn test_get_followers() {
        let env = Neo4jTestEnv::new().await;

        let repo = GraphRepository::new(&env.url, "neo4j", "testpass")
            .await
            .expect("Failed to initialize repository");

        let followee = Uuid::new_v4();
        let follower1 = Uuid::new_v4();
        let follower2 = Uuid::new_v4();

        // 创建多个关注关系
        repo.create_follow(follower1, followee)
            .await
            .expect("Failed to create follow 1");

        repo.create_follow(follower2, followee)
            .await
            .expect("Failed to create follow 2");

        // 获取粉丝列表
        let followers = repo.get_followers(followee)
            .await
            .expect("Failed to get followers");

        assert_eq!(followers.len(), 2);
        assert!(followers.contains(&follower1));
        assert!(followers.contains(&follower2));
    }

    #[tokio::test]
    async fn test_health_check() {
        let env = Neo4jTestEnv::new().await;

        let repo = GraphRepository::new(&env.url, "neo4j", "testpass")
            .await
            .expect("Failed to initialize repository");

        let health = repo.health_check()
            .await
            .expect("Health check failed");

        assert!(health, "Neo4j should be healthy");
    }

    #[tokio::test]
    async fn test_query_timeout() {
        let env = Neo4jTestEnv::new().await;

        let repo = GraphRepository::new(&env.url, "neo4j", "testpass")
            .await
            .expect("Failed to initialize repository");

        // 创建一个会超时的查询（无限循环）
        // 这个测试验证超时机制是否正常工作
        // 实际实现应该包含一个会长时间运行的Cypher查询

        // 注意：这个测试可能需要自定义实现，
        // 因为Neo4j通常会优化查询
    }
}
```

---

## 3. P1 修复：Realtime Chat Service - WebSocket基础测试

### 3.1 问题诊断

```
当前状态:
- realtime-chat-service: 10148行代码，0个集成测试
- 关键WebSocket连接/消息路由未验证
- 权限检查无测试

风险:
- 用户可能能够发送给未授权的用户
- 连接泄漏（连接不正确关闭）
- 消息顺序无法保证
```

### 3.2 修复步骤

**文件**: `/Users/proerror/Documents/nova/backend/realtime-chat-service/tests/websocket_integration_test.rs`

```rust
#[cfg(test)]
mod websocket_integration_tests {
    use realtime_chat_service::server::ChatServer;
    use tokio_tungstenite::{connect_async, tungstenite::Message};
    use futures_util::{SinkExt, StreamExt};
    use serde_json::json;
    use uuid::Uuid;

    struct ChatTestServer {
        addr: String,
        _handle: tokio::task::JoinHandle<()>,
    }

    impl ChatTestServer {
        async fn start() -> Self {
            let addr = "127.0.0.1:0".parse().unwrap();
            let server = ChatServer::new();

            let handle = tokio::spawn(async move {
                server.start(addr).await.expect("Server failed to start");
            });

            // 等待服务器启动
            tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

            Self {
                addr: "ws://127.0.0.1:8080".to_string(),
                _handle: handle,
            }
        }
    }

    #[tokio::test]
    async fn test_websocket_connection_established() {
        let _server = ChatTestServer::start().await;

        let token = "valid_jwt_token_here";

        let (ws_stream, _) = connect_async(
            format!("ws://127.0.0.1:8080/chat?token={}", token)
        )
        .await
        .expect("Failed to connect");

        let (mut write, mut read) = ws_stream.split();

        // 服务器应该发送欢迎消息
        let welcome = tokio::time::timeout(
            tokio::time::Duration::from_secs(5),
            read.next()
        )
        .await
        .expect("Timeout waiting for welcome")
        .expect("No welcome message");

        let message = welcome.to_text().expect("Not text");
        assert!(message.contains("connected"));
    }

    #[tokio::test]
    async fn test_websocket_send_message() {
        let _server = ChatTestServer::start().await;

        let token = "valid_jwt_token_here";
        let user_id = Uuid::new_v4();

        let (ws_stream, _) = connect_async(
            format!("ws://127.0.0.1:8080/chat?token={}", token)
        )
        .await
        .expect("Failed to connect");

        let (mut write, mut read) = ws_stream.split();

        // 跳过欢迎消息
        let _ = tokio::time::timeout(
            tokio::time::Duration::from_secs(1),
            read.next()
        ).await;

        // 发送消息
        let msg = json!({
            "type": "message",
            "conversation_id": "conv123",
            "content": "Hello, World!"
        });

        write.send(Message::Text(msg.to_string()))
            .await
            .expect("Failed to send");

        // 等待服务器确认
        let response = tokio::time::timeout(
            tokio::time::Duration::from_secs(5),
            read.next()
        )
        .await
        .expect("Timeout")
        .expect("No response");

        let response_text = response.to_text().expect("Not text");
        let json: serde_json::Value = serde_json::from_str(&response_text)
            .expect("Invalid JSON response");

        // 验证服务器返回消息ID或确认
        assert!(json["type"].as_str() == Some("message_sent"));
    }

    #[tokio::test]
    async fn test_websocket_authentication_required() {
        let _server = ChatTestServer::start().await;

        // 无token连接应该被拒绝
        let result = connect_async("ws://127.0.0.1:8080/chat").await;

        assert!(result.is_err(), "Should reject connection without token");
    }

    #[tokio::test]
    async fn test_websocket_invalid_token_rejected() {
        let _server = ChatTestServer::start().await;

        let invalid_token = "invalid.token.signature";

        let result = connect_async(
            format!("ws://127.0.0.1:8080/chat?token={}", invalid_token)
        ).await;

        assert!(result.is_err(), "Should reject invalid token");
    }

    #[tokio::test]
    async fn test_user_cannot_send_to_unauthorized_conversation() {
        let _server = ChatTestServer::start().await;

        let token = "valid_user_a_token";

        let (ws_stream, _) = connect_async(
            format!("ws://127.0.0.1:8080/chat?token={}", token)
        )
        .await
        .expect("Failed to connect");

        let (mut write, mut read) = ws_stream.split();

        // 跳过欢迎消息
        let _ = read.next().await;

        // 尝试发送给没有权限的对话
        let msg = json!({
            "type": "message",
            "conversation_id": "forbidden_conv",
            "content": "Unauthorized message"
        });

        write.send(Message::Text(msg.to_string()))
            .await
            .ok();

        // 应该收到错误或消息被拒绝
        let response = tokio::time::timeout(
            tokio::time::Duration::from_secs(5),
            read.next()
        )
        .await;

        if let Ok(Some(msg)) = response {
            let text = msg.to_text().expect("Not text");
            let json: serde_json::Value = serde_json::from_str(&text)
                .expect("Invalid JSON");

            // 应该返回权限错误
            assert!(json["type"].as_str() == Some("error"));
            assert!(json["error"].as_str()
                .map(|e| e.contains("permission") || e.contains("unauthorized"))
                .unwrap_or(false));
        }
    }

    #[tokio::test]
    async fn test_websocket_multiple_concurrent_connections() {
        let _server = ChatTestServer::start().await;

        let user_count = 5;
        let mut handles = vec![];

        for i in 0..user_count {
            let handle = tokio::spawn(async move {
                let token = format!("user_{}_token", i);

                let (ws_stream, _) = connect_async(
                    format!("ws://127.0.0.1:8080/chat?token={}", token)
                )
                .await
                .expect("Failed to connect");

                let (mut write, mut read) = ws_stream.split();

                // 跳过欢迎消息
                let _ = read.next().await;

                // 发送消息
                let msg = json!({
                    "type": "message",
                    "conversation_id": "group_conv",
                    "content": format!("Message from user {}", i)
                });

                write.send(Message::Text(msg.to_string()))
                    .await
                    .ok();

                // 等待响应
                let _ = read.next().await;
            });

            handles.push(handle);
        }

        // 等待所有连接完成
        for handle in handles {
            let _ = handle.await;
        }
    }

    #[tokio::test]
    async fn test_websocket_message_order_preserved() {
        let _server = ChatTestServer::start().await;

        let token = "valid_token";
        let conversation_id = Uuid::new_v4().to_string();

        let (ws_stream, _) = connect_async(
            format!("ws://127.0.0.1:8080/chat?token={}", token)
        )
        .await
        .expect("Failed to connect");

        let (mut write, mut read) = ws_stream.split();

        // 跳过欢迎消息
        let _ = read.next().await;

        let message_count = 10;

        // 发送多个消息
        for i in 0..message_count {
            let msg = json!({
                "type": "message",
                "conversation_id": &conversation_id,
                "content": format!("Message {}", i),
                "sequence": i
            });

            write.send(Message::Text(msg.to_string()))
                .await
                .ok();
        }

        // 验证消息顺序
        for i in 0..message_count {
            if let Ok(Some(msg)) = tokio::time::timeout(
                tokio::time::Duration::from_secs(5),
                read.next()
            ).await {
                let text = msg.to_text().ok();
                // 验证消息序列号是递增的
                if let Some(text) = text {
                    if let Ok(json) = serde_json::from_str::<serde_json::Value>(text) {
                        let sequence = json["sequence"].as_i64();
                        assert_eq!(sequence, Some(i as i64));
                    }
                }
            }
        }
    }
}
```

---

## 4. 测试基础设施配置

### 4.1 Cargo 配置

**文件**: `/Users/proerror/Documents/nova/backend/Cargo.toml` (在 `[dev-dependencies]` 部分添加)

```toml
[dev-dependencies]
# 现有依赖...
tokio-test = "0.4"
testcontainers = "0.15"
testcontainers-modules = { version = "0.1", features = ["neo4j"] }
tokio-tungstenite = "0.20"
```

### 4.2 GitHub Actions CI/CD 集成

**文件**: `/Users/proerror/Documents/nova/.github/workflows/test-coverage.yml`

```yaml
name: Test Coverage

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432

    steps:
      - uses: actions/checkout@v3

      - uses: dtolnay/rust-toolchain@stable

      - name: Cache cargo registry
        uses: actions/cache@v3
        with:
          path: ~/.cargo/registry
          key: ${{ runner.os }}-cargo-registry-${{ hashFiles('**/Cargo.lock') }}

      - name: Cache cargo index
        uses: actions/cache@v3
        with:
          path: ~/.cargo/git
          key: ${{ runner.os }}-cargo-git-${{ hashFiles('**/Cargo.lock') }}

      - name: Cache cargo build
        uses: actions/cache@v3
        with:
          path: target
          key: ${{ runner.os }}-cargo-build-target-${{ hashFiles('**/Cargo.lock') }}

      - name: Run tests
        run: cargo test --all --verbose
        env:
          DATABASE_URL: postgres://test:test@localhost:5432/test

      - name: Generate coverage
        run: |
          cargo install cargo-tarpaulin
          cargo tarpaulin --out Xml --exclude-files tests/**

      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./cobertura.xml
```

---

## 5. 验收标准

### Identity Service
- [ ] 8+ gRPC集成测试通过
- [ ] JWT单元测试覆盖所有路径
- [ ] 认证流程端到端验证
- [ ] 覆盖率 > 70%

### Graph Service
- [ ] Neo4j集成测试使用testcontainers
- [ ] 所有查询方法有超时配置
- [ ] 创建/删除关系测试通过
- [ ] 覆盖率 > 50%

### Realtime Chat Service
- [ ] WebSocket连接测试通过
- [ ] 权限检查测试通过
- [ ] 并发连接测试（5+用户）
- [ ] 覆盖率 > 30%

---

## 6. 时间估计

```
Task                              估计时间   难度
────────────────────────────────────────────────
1. Identity Service Tests         3-4天    中等
2. Graph Service Tests            2-3天    中等
3. Neo4j超时配置                  4小时    简单
4. Realtime Chat Tests            3-4天    难
5. CI/CD集成                      1-2天    简单
────────────────────────────────────────────────
总计                              9-14天   中等偏难
```

---

**下一步**: 按优先级执行修复，每个修复完成后运行 `cargo test --all` 验证。
