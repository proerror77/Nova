# P1 Fix: WebSocket Sticky Sessions

## Problem

**Issue**: WebSocket connections drop on pod restart without affinity
```
Client WebSocket Connection
  ↓
Load Balancer: Round-robin to Pod A, Pod B, Pod C
  ↓
Pod A handles connection
  ↓
Pod A restarts (rolling update)
  ↓
Connection routed to Pod B/C
  ↓
❌ Client gets disconnected (connection severed)
  ❌ User sees "lost connection" error
  ❌ Must manually reconnect
```

**Impact**:
- Chat users disconnected during updates
- Video streaming interrupted
- Real-time notifications missed
- Poor user experience (updates should be transparent)

**Example Flow**:
```
t=0:    Client connects to messaging-service pod-1
        Opens WebSocket: ws://messaging-service:8080/chat/123

t=30s:  Client sending: "Hello"

t=60s:  Kubernetes rolling update starts
        pod-1 terminates gracefully (SIGTERM)
        Connection still pending

t=61s:  Load balancer routes new packets to pod-2
        ❌ pod-2 doesn't know about connection
        ❌ Message dropped

t=62s:  Browser detects disconnect
        Retries with new connection
        User sees: "Reconnected" (jarring)
```

---

## Solution: Sticky Sessions (Session Affinity)

### High-Level Design

```
Load Balancer (Istio/Nginx/AWS ALB)
  ├── Pod A: hosting websocket-123 (user-session-123)
  ├── Pod B
  └── Pod C

Rule: "If client IP matches stored affinity → always route to Pod A"

Result:
- User connects to pod-1
- Even after pod restart, connection migrates to same pod
- Or: connection is maintained through persistence layer
```

### Three Approaches (Ranked by Simplicity)

#### Approach 1: Kubernetes Service Affinity (Recommended)

**Pros**:
- Zero code changes
- Built into Kubernetes
- Works across pod restarts

**Cons**:
- Session lost on pod termination
- Need graceful shutdown handling

**Implementation**:

```yaml
# kubernetes/base/messaging-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: messaging-service
  namespace: nova
spec:
  type: ClusterIP
  selector:
    app: messaging-service
  ports:
    - name: http
      port: 8080
      targetPort: 8080
    - name: grpc
      port: 8081
      targetPort: 8081
  sessionAffinity: ClientIP          # ← STICKY SESSIONS
  sessionAffinityConfig:
    clientIPConfig:
      timeoutSeconds: 10800          # 3 hours
```

**How it works**:
- Kubernetes tracks client IP → pod mapping
- All requests from same IP route to same pod
- Timeout: 3 hours (user can reconnect if stale)

**Testing**:
```bash
# Test affinity
kubectl apply -f kubernetes/base/messaging-service.yaml

# Check config
kubectl get svc messaging-service -o yaml | grep -A 5 sessionAffinity

# Result should show:
# sessionAffinity: ClientIP
# timeoutSeconds: 10800
```

#### Approach 2: Ingress Controller Affinity (For External Traffic)

**Scenario**: Users connect via ingress (not internal K8s DNS)

```yaml
# kubernetes/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nova-ingress
  annotations:
    nginx.ingress.kubernetes.io/affinity: "cookie"
    nginx.ingress.kubernetes.io/affinity-mode: "persistent"
    nginx.ingress.kubernetes.io/session-cookie-name: "SERVERID"
    nginx.ingress.kubernetes.io/session-cookie-path: "/"
    nginx.ingress.kubernetes.io/session-cookie-max-age: "86400"
    nginx.ingress.kubernetes.io/session-cookie-httponly: "true"
    nginx.ingress.kubernetes.io/session-cookie-secure: "true"
spec:
  ingressClassName: nginx
  rules:
    - host: api.nova.social
      http:
        paths:
          - path: /messaging
            pathType: Prefix
            backend:
              service:
                name: messaging-service
                port:
                  number: 8080
          - path: /streaming
            pathType: Prefix
            backend:
              service:
                name: streaming-service
                port:
                  number: 8080
```

**How it works**:
- Ingress controller sets persistent cookie
- Cookie contains pod identity (SERVERID)
- All requests with same cookie → same pod
- Survives pod restarts (until timeout)

**AWS ALB Alternative**:
```yaml
apiVersion: v1
kind: Service
metadata:
  name: messaging-service
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "tcp"
spec:
  type: LoadBalancer
  selector:
    app: messaging-service
  ports:
    - port: 8080
      targetPort: 8080
      protocol: TCP
  sessionAffinity: ClientIP
```

#### Approach 3: Distributed Session Store (For Multi-Region)

**Scenario**: Pod can restart AND affinity lost → preserve session in Redis

```rust
// In messaging-service
use redis::Commands;

#[derive(Clone, serde::Serialize, serde::Deserialize)]
pub struct WebSocketSession {
    pub user_id: String,
    pub connection_id: String,
    pub pod_id: String,
    pub created_at: i64,
}

impl WebSocketSession {
    /// Save session to Redis for recovery
    pub async fn save(&self, redis: &redis::aio::ConnectionManager) -> Result<()> {
        let key = format!("ws:session:{}", self.connection_id);
        redis.set_ex(
            &key,
            serde_json::to_string(self)?,
            3600, // 1 hour TTL
        ).await?;
        Ok(())
    }

    /// Restore session (client reconnects to different pod)
    pub async fn restore(
        connection_id: &str,
        redis: &redis::aio::ConnectionManager,
    ) -> Result<Option<Self>> {
        let key = format!("ws:session:{}", connection_id);
        match redis.get::<_, String>(&key).await {
            Ok(json) => Ok(Some(serde_json::from_str(&json)?)),
            Err(_) => Ok(None),
        }
    }
}

// In WebSocket handler
#[actix_web::web::route("/chat/{room_id}", method = "GET")]
pub async fn websocket_handler(
    req: HttpRequest,
    stream: web::Payload,
    redis: web::Data<redis::aio::ConnectionManager>,
    room_id: web::Path<String>,
) -> Result<HttpResponse> {
    let connection_id = Uuid::new_v4().to_string();
    let user_id = extract_user_id(&req)?;

    let session = WebSocketSession {
        user_id: user_id.clone(),
        connection_id: connection_id.clone(),
        pod_id: std::env::var("POD_NAME").unwrap_or_default(),
        created_at: chrono::Utc::now().timestamp(),
    };

    // Save to Redis (survive pod restart)
    session.save(&redis).await?;

    // Handle WebSocket normally
    let (response, actor) = actix_web::ws::WsResponseBuilder::new(
        WebSocketActor::new(user_id, room_id.into_inner()),
        &req,
        stream.into_inner(),
    ).start_with_addr()?;

    Ok(response)
}

// On client disconnect
pub async fn handle_disconnect(
    connection_id: String,
    redis: &redis::aio::ConnectionManager,
) {
    let key = format!("ws:session:{}", connection_id);
    let _ = redis.del(&key).await;  // Clean up
}

// On client reconnect
pub async fn handle_reconnect(
    user_id: String,
    old_connection_id: String,
    new_connection_id: String,
    redis: &redis::aio::ConnectionManager,
) -> Result<()> {
    // Restore old session to new connection
    if let Some(mut session) = WebSocketSession::restore(&old_connection_id, &redis).await? {
        session.connection_id = new_connection_id.clone();
        session.save(&redis).await?;

        // Get pending messages from queue
        let messages_key = format!("ws:messages:{}", user_id);
        let pending: Vec<String> = redis.lrange(&messages_key, 0, -1).await?;

        // Send to client
        for msg in pending {
            // send_message_to_client(msg).await?;
        }
    }
    Ok(())
}
```

---

## Implementation Checklist

### Phase 1: Kubernetes Service Affinity (Week 1)

- [ ] Update messaging-service deployment
- [ ] Set sessionAffinity: ClientIP
- [ ] Set timeoutSeconds: 10800
- [ ] Apply to staging
- [ ] Test: connect, kill pod, verify reconnect to same pod
- [ ] Monitor: connection drops during rolling updates

**Test Script**:
```bash
#!/bin/bash

# Terminal 1: Watch pod assignments
kubectl get pods -l app=messaging-service -o wide

# Terminal 2: Connect WebSocket client
# (from different IP addresses)
wscat -c ws://messaging-service:8080/chat/room-123

# Terminal 3: Trigger rolling update
kubectl rollout restart deployment/messaging-service

# Expected: Connection stays active
#          or reconnects automatically
#          NO dropped connections
```

### Phase 2: Ingress Affinity (Week 1-2)

**If using NGINX Ingress**:

```bash
# Install NGINX ingress if not present
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx

# Update ingress.yaml with annotations (above)
kubectl apply -f kubernetes/ingress.yaml

# Verify:
kubectl get ingress nova-ingress -o yaml | grep -A 10 annotations
```

**If using AWS ALB**:

```bash
# Update service annotations
kubectl annotate service messaging-service \
  service.beta.kubernetes.io/aws-load-balancer-type=nlb \
  --overwrite

# Apply session affinity
kubectl patch service messaging-service -p \
  '{"spec":{"sessionAffinity":"ClientIP"}}'
```

### Phase 3: Distributed Session Store (Week 2-3)

**Only needed if**:
- Multi-pod rolling updates with zero downtime
- Multi-region deployment
- Session must survive pod termination

**Setup**:
- [ ] Update messaging-service to use redis session store
- [ ] Add WebSocketSession serialization
- [ ] Implement reconnect with session restoration
- [ ] Test: kill pod → client reconnects → messages restored
- [ ] Monitor: session hit rate, reconnect latency

---

## Pod Graceful Shutdown Integration

### Problem: Pod terminates mid-connection

When Kubernetes sends SIGTERM:
```
Pod: Receive SIGTERM
  ↓
Pod: 30 second termination grace period (default)
  ↓
WebSocket connections: Active but pod shutting down
  ↓
SIGKILL: Force termination
  ↓
❌ Connections lost instantly (no graceful close)
```

### Solution: Graceful Connection Draining

```rust
// In main.rs
use actix_web::HttpServer;
use tokio::signal;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let server = HttpServer::new(|| {
        App::new()
            .route("/chat/{room}", web::get().to(websocket_handler))
    })
    .bind("0.0.0.0:8080")?
    .workers(4)
    // Set high keep-alive to allow graceful shutdown
    .keep_alive(std::time::Duration::from_secs(75))
    .shutdown_timeout(30); // 30 second grace period

    let server_handle = server.run();
    let server_task = tokio::spawn(server_handle);

    // Listen for SIGTERM
    let sigterm = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("Failed to install signal handler")
            .recv()
            .await
    };

    // Listen for SIGINT (Ctrl+C)
    let sigint = async {
        signal::ctrl_c().await.ok()
    };

    tokio::select! {
        _ = sigterm => {
            tracing::info!("SIGTERM received, starting graceful shutdown");
            // Server will close listening socket
            // But active connections continue until timeout
        }
        _ = sigint => {
            tracing::info!("SIGINT received, starting graceful shutdown");
        }
    }

    // Wait for all connections to close (up to 30 seconds)
    server_task.await.ok();
    tracing::info!("Server shut down gracefully");
    Ok(())
}
```

**Kubernetes Pod Spec**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: messaging-service
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 45  # 45 seconds to close connections
      containers:
      - name: messaging-service
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 10"]  # Give k8s time to remove endpoint
```

---

## Monitoring & Alerting

### Metrics to Track

```rust
lazy_static::lazy_static! {
    static ref WS_CONNECTIONS_ACTIVE: prometheus::Gauge =
        prometheus::Gauge::new("websocket_connections_active", "Active WebSocket connections").unwrap();

    static ref WS_CONNECTIONS_CREATED: prometheus::Counter =
        prometheus::Counter::new("websocket_connections_created_total", "Total WebSocket connections").unwrap();

    static ref WS_CONNECTIONS_CLOSED: prometheus::Counter =
        prometheus::Counter::new("websocket_connections_closed_total", "Closed WebSocket connections").unwrap();

    static ref WS_RECONNECTS: prometheus::Counter =
        prometheus::Counter::new("websocket_reconnects_total", "WebSocket reconnections").unwrap();

    static ref WS_SESSION_DURATION: prometheus::Histogram =
        prometheus::Histogram::new("websocket_session_duration_seconds", "WebSocket session duration").unwrap();
}

// In WebSocket actor
pub async fn on_connect(&mut self) {
    WS_CONNECTIONS_ACTIVE.inc();
    WS_CONNECTIONS_CREATED.inc();
}

pub async fn on_disconnect(&mut self) {
    WS_CONNECTIONS_ACTIVE.dec();
    WS_CONNECTIONS_CLOSED.inc();
    let duration = self.created_at.elapsed();
    WS_SESSION_DURATION.observe(duration.as_secs_f64());
}
```

### Grafana Dashboard

```yaml
# queries:
- name: "Active WebSocket Connections"
  query: "websocket_connections_active"

- name: "Connection Creation Rate"
  query: "rate(websocket_connections_created_total[5m])"

- name: "Reconnect Rate"
  query: "rate(websocket_reconnects_total[5m])"

- name: "Average Session Duration"
  query: "histogram_quantile(0.95, websocket_session_duration_seconds)"
```

### Alert Rules

```yaml
groups:
  - name: websocket
    rules:
      - alert: WebSocketReconnectSurge
        expr: rate(websocket_reconnects_total[5m]) > 10
        for: 1m
        annotations:
          summary: "{{ $value }} WebSocket reconnects/sec (normal: <1)"
          description: "Possible pod restart or network issue"

      - alert: LongWebSocketSession
        expr: histogram_quantile(0.99, websocket_session_duration_seconds) > 3600
        annotations:
          summary: "p99 session duration > 1 hour"
          description: "May indicate stuck connections"
```

---

## Troubleshooting

### Issue: Connections still dropping on pod restart

**Causes**:
1. sessionAffinity not set on Service
2. Ingress not configured for persistence
3. Client connecting through external LB without affinity
4. Multiple services (streaming, messaging) not synchronized

**Check**:
```bash
# Verify Service affinity
kubectl get svc messaging-service -o yaml | grep sessionAffinity

# Result should show: sessionAffinity: ClientIP

# Verify Ingress
kubectl get ingress -o yaml | grep affinity

# Should see: nginx.ingress.kubernetes.io/affinity: cookie
```

**Fix**:
```bash
# Apply affinity
kubectl patch svc messaging-service -p \
  '{"spec":{"sessionAffinity":"ClientIP","sessionAffinityConfig":{"clientIPConfig":{"timeoutSeconds":10800}}}}'

# Verify applied
kubectl rollout restart deployment/messaging-service
```

### Issue: Reconnect latency high (client waits 10+ seconds)

**Causes**:
1. Session timeout too short
2. DNS resolution slow
3. Pod boot time slow

**Fix**:
```yaml
# Increase timeout
sessionAffinityConfig:
  clientIPConfig:
    timeoutSeconds: 10800  # Increase from default 10800
```

---

## Testing Scenarios

### Test 1: Rolling Update (No Affinity)

```bash
# Before: Active WebSocket → Pod A
# During: Rolling update kills Pod A
# Expected WITHOUT affinity: Connection drops, client reconnects

# Run test
kubectl rollout restart deployment/messaging-service --record
wscat -c ws://messaging-service:8080/test

# Expected: "❌ WebSocket closed"
```

### Test 2: Rolling Update (With Affinity)

```bash
# Before: Active WebSocket → Pod A (sticky)
# During: Rolling update kills Pod A
# Expected WITH affinity: Connection migrates to Pod B, stays active

# Apply affinity
kubectl patch svc messaging-service -p \
  '{"spec":{"sessionAffinity":"ClientIP"}}'

# Run test
kubectl rollout restart deployment/messaging-service --record
wscat -c ws://messaging-service:8080/test

# Expected: "✅ Connection maintained"
```

### Test 3: Client Reconnect Recovery

```bash
# Start client
wscat -c ws://messaging-service:8080/chat/room-1

# Kill network (simulate disconnect)
# Client should automatically reconnect
# With session store: messages queued during disconnect delivered

# Expected: "✅ Reconnected, messages restored"
```

---

## References

- [Kubernetes Service Affinity](https://kubernetes.io/docs/concepts/services-networking/service/#session-affinity)
- [NGINX Ingress Affinity](https://kubernetes.github.io/ingress-nginx/user-guide/miscellaneous/#affinity)
- [Actix WebSocket](https://actix.rs/actix-web/actix_web/web/ws/)

## Status

- **Created**: 2025-11-04
- **Priority**: P1 (High)
- **Estimated Effort**: 1 week (all 3 phases)
- **Impact**: Seamless WebSocket experience during updates, improved reliability
- **Blocks**: Production quality messaging & real-time features
