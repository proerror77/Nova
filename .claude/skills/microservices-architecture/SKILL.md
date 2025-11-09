---
name: microservices-architecture
description: Master microservices architecture patterns including service boundaries, event-driven communication, and resilience strategies. Use when designing distributed systems, decomposing monoliths, or solving inter-service communication challenges.
---

# Microservices Architecture Patterns

Essential patterns for building scalable, maintainable microservices systems.

## When to Use This Skill

- Defining service boundaries
- Designing inter-service communication
- Implementing event-driven architectures
- Building resilient distributed systems
- Decomposing monolithic applications
- Solving data consistency challenges

## Core Patterns

### Pattern 1: Service Boundary Definition (DDD)

**Bounded Context Example:**
```
User Service (Identity Context)
├── User authentication
├── User profiles
└── User preferences

Content Service (Content Context)
├── Post creation/editing
├── Comments
└── Content moderation

Feed Service (Feed Context)
├── Personalized feeds
├── Feed ranking
└── Feed caching
```

**Service Ownership:**
- Each service owns its data
- No direct database access across services
- Communication via APIs or events

### Pattern 2: Event-Driven Communication

**Event Example:**
```rust
#[derive(Serialize, Deserialize)]
pub struct UserCreatedEvent {
    pub user_id: i64,
    pub email: String,
    pub created_at: DateTime<Utc>,
}

// Producer (User Service)
pub async fn create_user(user: NewUser) -> Result<User> {
    // Create user in database
    let user = sqlx::query_as!(...)
        .fetch_one(&pool)
        .await?;

    // Publish event
    let event = UserCreatedEvent {
        user_id: user.id,
        email: user.email.clone(),
        created_at: user.created_at,
    };

    kafka_producer
        .send("user.created", &event)
        .await?;

    Ok(user)
}

// Consumer (Email Service)
pub async fn handle_user_created(event: UserCreatedEvent) -> Result<()> {
    send_welcome_email(&event.email).await?;
    Ok(())
}
```

### Pattern 3: Saga Pattern (Distributed Transactions)

**Choreography-Based Saga:**
```
Order Service → OrderCreated event
    ↓
Payment Service → PaymentProcessed event
    ↓
Inventory Service → InventoryReserved event
    ↓
Shipping Service → ShipmentScheduled event

Rollback on failure:
    Shipping fails → InventoryReleased event
    Payment fails → OrderCancelled event
```

**Implementation:**
```rust
pub async fn process_order(order: Order) -> Result<()> {
    // Step 1: Create order
    let order_id = create_order(&order).await?;

    // Step 2: Process payment
    match process_payment(order_id, order.total).await {
        Ok(_) => {
            publish_event("payment.processed", order_id).await?;
        }
        Err(e) => {
            // Compensate: Cancel order
            cancel_order(order_id).await?;
            publish_event("order.cancelled", order_id).await?;
            return Err(e);
        }
    }

    // Step 3: Reserve inventory
    match reserve_inventory(order_id, &order.items).await {
        Ok(_) => {
            publish_event("inventory.reserved", order_id).await?;
        }
        Err(e) => {
            // Compensate: Refund payment
            refund_payment(order_id).await?;
            cancel_order(order_id).await?;
            return Err(e);
        }
    }

    Ok(())
}
```

### Pattern 4: Circuit Breaker

**Implementation:**
```rust
use std::sync::Arc;
use tokio::sync::RwLock;

pub struct CircuitBreaker {
    state: Arc<RwLock<CircuitState>>,
    failure_threshold: u32,
    reset_timeout: Duration,
}

impl CircuitBreaker {
    pub async fn call<F, T>(&self, f: F) -> Result<T>
    where
        F: Future<Output = Result<T>>,
    {
        match *self.state.read().await {
            CircuitState::Open => Err(anyhow!("Circuit is open")),
            _ => {
                match f.await {
                    Ok(result) => {
                        self.on_success().await;
                        Ok(result)
                    }
                    Err(e) => {
                        self.on_failure().await;
                        Err(e)
                    }
                }
            }
        }
    }
}

// Usage
let breaker = CircuitBreaker::new(5, Duration::from_secs(30));

breaker.call(|| async {
    call_external_service().await
}).await?;
```

### Pattern 5: API Gateway Pattern

**Gateway Aggregation:**
```rust
pub struct ApiGateway {
    user_client: UserServiceClient,
    content_client: ContentServiceClient,
}

impl ApiGateway {
    pub async fn get_user_dashboard(&self, user_id: i64) -> Result<Dashboard> {
        // Parallel requests to multiple services
        let (user, posts, followers) = tokio::join!(
            self.user_client.get_user(user_id),
            self.content_client.get_user_posts(user_id),
            self.user_client.get_followers(user_id)
        );

        Ok(Dashboard {
            user: user?,
            recent_posts: posts?,
            follower_count: followers?.len(),
        })
    }
}
```

### Pattern 6: Outbox Pattern (Transactional Messaging)

**Ensure At-Least-Once Delivery:**
```rust
pub async fn create_user_with_event(user: NewUser, pool: &PgPool) -> Result<User> {
    let mut tx = pool.begin().await?;

    // 1. Insert user
    let user = sqlx::query_as!(
        User,
        "INSERT INTO users (email, name) VALUES ($1, $2) RETURNING *",
        user.email,
        user.name
    )
    .fetch_one(&mut tx)
    .await?;

    // 2. Insert outbox event
    let event = serde_json::to_value(UserCreatedEvent {
        user_id: user.id,
        email: user.email.clone(),
    })?;

    sqlx::query!(
        "INSERT INTO outbox (aggregate_id, event_type, payload) VALUES ($1, $2, $3)",
        user.id,
        "user.created",
        event
    )
    .execute(&mut tx)
    .await?;

    tx.commit().await?;

    Ok(user)
}

// Background worker publishes outbox events
pub async fn outbox_publisher(pool: PgPool, kafka: KafkaProducer) {
    loop {
        let events = sqlx::query_as!(
            OutboxEvent,
            "SELECT * FROM outbox WHERE published_at IS NULL LIMIT 100"
        )
        .fetch_all(&pool)
        .await?;

        for event in events {
            kafka.send(&event.event_type, &event.payload).await?;

            sqlx::query!(
                "UPDATE outbox SET published_at = NOW() WHERE id = $1",
                event.id
            )
            .execute(&pool)
            .await?;
        }

        tokio::time::sleep(Duration::from_secs(1)).await;
    }
}
```

## Anti-Patterns to Avoid

### ❌ Distributed Monolith
- Services tightly coupled
- Synchronous inter-service calls everywhere
- Shared database across services

### ❌ Breaking Service Boundaries
```rust
// BAD: Content Service directly accessing User database
let user = sqlx::query!("SELECT * FROM users.users WHERE id = $1", user_id)
    .fetch_one(&pool)
    .await?;

// GOOD: Call User Service API
let user = user_client.get_user(user_id).await?;
```

### ❌ Chatty Services
```rust
// BAD: N+1 service calls
for post in posts {
    let user = user_client.get_user(post.user_id).await?;
    enriched_posts.push((post, user));
}

// GOOD: Batch request
let user_ids = posts.iter().map(|p| p.user_id).collect();
let users = user_client.get_users_batch(user_ids).await?;
```

## Best Practices

1. **Database per Service** - Each service owns its data
2. **Asynchronous Communication** - Use events for loose coupling
3. **API Versioning** - Never break existing clients
4. **Idempotency** - Support safe retries
5. **Circuit Breakers** - Prevent cascading failures
6. **Distributed Tracing** - Track requests across services
7. **Service Discovery** - Use Kubernetes DNS or service mesh
8. **Health Checks** - Liveness and readiness probes
9. **Graceful Degradation** - Fallback when dependencies fail
10. **Event Versioning** - Support event schema evolution

## Resources

- [Microservices Patterns](https://microservices.io/patterns/)
- [Domain-Driven Design](https://www.domainlanguage.com/ddd/)
- [Saga Pattern](https://microservices.io/patterns/data/saga.html)
