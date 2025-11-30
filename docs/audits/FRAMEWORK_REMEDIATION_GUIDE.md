# Framework Compliance - Quick Remediation Guide

**Quick-start implementations for highest-impact issues**

---

## 1. RUST: Eliminate Critical unwrap() Calls

### Pattern 1: gRPC Client Initialization

**File**: `backend/graphql-gateway/src/clients.rs`

**Before**:
```rust
pub async fn create_channel(url: &str) -> Channel {
    Endpoint::from_shared(url.to_string())
        .unwrap()  // ❌ PANICS on invalid URL
        .connect_lazy()
}
```

**After**:
```rust
use anyhow::{Context, Result};

pub async fn create_channel(url: &str) -> Result<Channel> {
    let channel = Endpoint::from_shared(url.to_string())
        .context(format!("Invalid gRPC endpoint URL: {}", url))?
        .connect_lazy();
    Ok(channel)
}

// In main.rs
let auth_channel = create_channel(&config.auth_service_url)
    .context("Failed to create auth service channel")?;
```

---

### Pattern 2: Connection Pool Creation

**File**: `backend/graphql-gateway/src/config.rs`

**Before**:
```rust
fn default_redis_url() -> String {
    env::var("REDIS_URL").unwrap_or_else(|_| "redis://redis:6379".to_string())
}
```

**After**:
```rust
use anyhow::{Context, Result};

fn default_redis_url() -> String {
    "redis://redis:6379".to_string()  // Safe default
}

pub async fn init_redis_pool(config: &Config) -> Result<ConnectionManager> {
    let pool = redis::Client::open(&config.redis_url)
        .context("Invalid Redis URL")?
        .get_connection_manager()
        .await
        .context("Failed to connect to Redis")?;
    Ok(pool)
}
```

---

### Pattern 3: Mutex Lock Handling

**File**: `backend/social-service/src/grpc/server_v2.rs`

**Before**:
```rust
let state = self.state.lock().unwrap();  // ❌ PANICS on poisoned lock
```

**After**:
```rust
use tonic::Status;

let state = self.state.lock()
    .map_err(|e| {
        tracing::error!("Mutex poisoned: {}", e);
        Status::internal("Service state corrupted")
    })?;
```

---

## 2. SWIFT: Implement Error State Pattern

### File: `ios/NovaSocial/Features/Home/ViewModels/FeedViewModel.swift`

**Step 1**: Create LoadingState enum
```swift
import Foundation

@MainActor
class FeedViewModel: ObservableObject {
    enum LoadingState {
        case idle
        case loading
        case success([FeedPost])
        case error(APIError, retryAction: () -> Void)
    }

    @Published var state: LoadingState = .idle
    @Published var hasMore = true

    private let feedService = FeedService()
    private let contentService = ContentService()

    // MARK: - Public Methods

    func loadFeed(algorithm: FeedAlgorithm = .chronological) async {
        self.state = .loading

        do {
            let response = try await feedService.getFeed(
                algo: algorithm,
                limit: 20,
                cursor: nil
            )

            let posts = response.posts.map { FeedPost(from: $0) }
            self.state = .success(posts)
            self.hasMore = response.hasMore

        } catch let error as APIError {
            self.state = .error(error) { [weak self] in
                Task {
                    await self?.loadFeed(algorithm: algorithm)
                }
            }
        } catch {
            let apiError = APIError.unknown
            self.state = .error(apiError) { [weak self] in
                Task {
                    await self?.loadFeed(algorithm: algorithm)
                }
            }
        }
    }

    func loadMore() async {
        guard case .success = state else { return }
        // Implementation...
    }

    func retry() {
        if case .error(_, let retryAction) = state {
            retryAction()
        }
    }
}
```

**Step 2**: Update View to use state
```swift
// In HomeView.swift
struct HomeView: View {
    @StateObject var viewModel = FeedViewModel()

    var body: some View {
        ZStack {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading feed...")

            case .success(let posts):
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(posts, id: \.id) { post in
                            FeedPostView(post: post)
                        }

                        if viewModel.hasMore {
                            ProgressView()
                                .onAppear {
                                    Task {
                                        await viewModel.loadMore()
                                    }
                                }
                        }
                    }
                }

            case .error(let error, let retry):
                ErrorView(
                    title: "Failed to Load Feed",
                    message: error.localizedDescription,
                    retryAction: retry
                )
            }
        }
        .onAppear {
            Task {
                await viewModel.loadFeed()
            }
        }
    }
}

struct ErrorView: View {
    let title: String
    let message: String
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: retryAction) {
                Text("Retry")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding()
    }
}
```

---

## 3. KUBERNETES: Add Security Context

### File: Create `k8s/graphql-gateway/security-patch.yaml`

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: nova-gateway

---
apiVersion: policy/v1
kind: PodSecurityPolicy
metadata:
  name: nova-restricted
spec:
  privileged: false
  allowPrivilegeEscalation: false
  requiredDropCapabilities:
  - ALL
  runAsUser:
    rule: 'MustRunAsNonRoot'
  seLinux:
    rule: 'MustRunAs'
    seLinuxOptions:
      level: 's0:c123,c456'
  fsGroup:
    rule: 'MustRunAs'
    ranges:
    - min: 1000
      max: 65535
  readOnlyRootFilesystem: true

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: graphql-gateway
  namespace: nova-gateway
spec:
  replicas: 3

  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0

  template:
    metadata:
      labels:
        app: graphql-gateway
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"

    spec:
      serviceAccountName: graphql-gateway
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault

      containers:
      - name: graphql-gateway
        image: nova/graphql-gateway:latest
        imagePullPolicy: Always

        ports:
        - name: http
          containerPort: 8080
          protocol: TCP

        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 1000
          capabilities:
            drop:
            - ALL

        resources:
          requests:
            cpu: 250m
            memory: 256Mi
          limits:
            cpu: 1000m
            memory: 512Mi

        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 2

        volumeMounts:
        - name: tmp
          mountPath: /tmp
        - name: cache
          mountPath: /app/cache

        env:
        - name: ENVIRONMENT
          value: "staging"
        - name: GRAPHQL_INTROSPECTION
          value: "false"
        - name: GRAPHQL_PLAYGROUND
          value: "false"

      volumes:
      - name: tmp
        emptyDir: {}
      - name: cache
        emptyDir:
          sizeLimit: 100Mi

      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: app
                  operator: In
                  values:
                  - graphql-gateway
              topologyKey: kubernetes.io/hostname

      terminationGracePeriodSeconds: 30

---
apiVersion: v1
kind: Service
metadata:
  name: graphql-gateway
  namespace: nova-gateway
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: http
    protocol: TCP
  selector:
    app: graphql-gateway

---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: graphql-gateway-ingress
  namespace: nova-gateway
spec:
  podSelector:
    matchLabels:
      app: graphql-gateway
  policyTypes:
  - Ingress
  - Egress

  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx
    - podSelector:
        matchLabels:
          app: api-tester
    ports:
    - protocol: TCP
      port: 8080

  egress:
  # DNS
  - to:
    - podSelector: {}
    ports:
    - protocol: UDP
      port: 53

  # gRPC services (nova-staging namespace)
  - to:
    - namespaceSelector:
        matchLabels:
          name: nova-staging
    ports:
    - protocol: TCP
      port: 50051

  # PostgreSQL
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432

  # Redis
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          app: redis
    ports:
    - protocol: TCP
      port: 6379

  # Kafka (if using)
  - to:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          app: kafka
    ports:
    - protocol: TCP
      port: 9092

---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: graphql-gateway-pdb
  namespace: nova-gateway
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: graphql-gateway
```

---

## 4. GRPC: Add Timeout Wrapper Pattern

### File: `backend/libs/resilience/src/timeout.rs`

```rust
use anyhow::{Context, Result};
use std::future::Future;
use std::time::Duration;
use tonic::Status;

/// Wraps a gRPC call with timeout protection
pub async fn with_timeout<F, T>(
    future: F,
    service_name: &str,
    method_name: &str,
    timeout: Duration,
) -> Result<T, Status>
where
    F: Future<Output = Result<T, Status>>,
{
    tokio::time::timeout(timeout, future)
        .await
        .map_err(|_| {
            tracing::warn!(
                service = service_name,
                method = method_name,
                timeout_secs = timeout.as_secs(),
                "gRPC call timeout"
            );
            Status::deadline_exceeded(format!(
                "{}::{} exceeded {}s timeout",
                service_name,
                method_name,
                timeout.as_secs()
            ))
        })
        .and_then(|result| result)
}

#[macro_export]
macro_rules! grpc_call {
    ($client:expr, $method:expr, $service:expr, $timeout:expr) => {
        $crate::timeout::with_timeout(
            $method,
            $service,
            stringify!($method),
            $timeout,
        )
        .await
    };
}
```

### Usage in Services:

```rust
use resilience::timeout::with_timeout;
use std::time::Duration;

pub async fn get_user(
    &self,
    request: Request<GetUserRequest>,
) -> Result<Response<User>, Status> {
    let req = request.into_inner();

    let user = with_timeout(
        self.db.get_user(&req.user_id),
        "ContentService",
        "GetUser",
        Duration::from_secs(10),
    )
    .await?;

    Ok(Response::new(user))
}
```

---

## 5. iOS: Certificate Pinning

### File: `ios/NovaSocial/Shared/Services/Networking/CertificatePinning.swift`

```swift
import Foundation

class CertificatePinningDelegate: NSObject, URLSessionDelegate {
    // Public key hash of api.nova.social certificate
    private let pinnedPublicKeyHashes = [
        "sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",  // Production
        "sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=",  // Backup
    ]

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        // Only handle HTTPS challenges
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Validate certificate chain
        var secResult = SecTrustResultType.invalid
        let status = SecTrustEvaluate(serverTrust, &secResult)

        guard status == errSecSuccess else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract and validate public key
        guard let certificate = SecTrustGetCertificateAtIndex(serverTrust, 0),
              validatePublicKey(certificate) else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Certificate is valid and pinned
        let credential = URLCredential(trust: serverTrust)
        completionHandler(.useCredential, credential)
    }

    private func validatePublicKey(_ certificate: SecCertificate) -> Bool {
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?

        SecTrustCreateWithCertificates(certificate as CFTypeRef, policy, &trust)

        guard let trust = trust,
              let publicKey = SecTrustCopyPublicKey(trust) else {
            return false
        }

        let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? ?? Data()
        let publicKeyHash = SHA256(publicKeyData).base64EncodedString()

        return pinnedPublicKeyHashes.contains("sha256/\(publicKeyHash)")
    }
}

// MARK: - SHA256 Helper
private func SHA256(_ data: Data) -> Data {
    var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

    #if os(iOS)
    data.withUnsafeBytes { buffer in
        CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &digest)
    }
    #endif

    return Data(digest)
}

// MARK: - Import CommonCrypto
import CommonCrypto

// MARK: - Updated APIClient

class APIClient {
    static let shared = APIClient()

    private let baseURL = APIConfig.current.baseURL
    let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = APIConfig.current.timeout
        config.timeoutIntervalForResource = 300

        // Use certificate pinning delegate
        let pinningDelegate = CertificatePinningDelegate()

        self.session = URLSession(
            configuration: config,
            delegate: pinningDelegate,
            delegateQueue: .main
        )
    }
}
```

---

## 6. GraphQL: Disable Introspection in Production

### File: Update `backend/graphql-gateway/src/config.rs`

```rust
use std::env;

#[derive(Debug, Clone)]
pub struct GraphQLConfig {
    pub introspection_enabled: bool,
    pub playground_enabled: bool,
    pub max_query_depth: usize,
    pub max_query_complexity: usize,
}

impl GraphQLConfig {
    pub fn from_env() -> Self {
        let environment = env::var("ENVIRONMENT").unwrap_or_else(|_| "production".to_string());

        match environment.as_str() {
            "production" => Self {
                introspection_enabled: false,
                playground_enabled: false,
                max_query_depth: 10,
                max_query_complexity: 1000,
            },
            "staging" => Self {
                introspection_enabled: true,
                playground_enabled: true,
                max_query_depth: 15,
                max_query_complexity: 2000,
            },
            _ => Self {
                introspection_enabled: true,
                playground_enabled: true,
                max_query_depth: 20,
                max_query_complexity: 5000,
            },
        }
    }
}
```

### File: `backend/graphql-gateway/src/main.rs`

```rust
use async_graphql::{http::GraphiQLSource, EmptySubscription, Schema};

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    // ... existing code ...

    let graphql_config = GraphQLConfig::from_env();
    let schema = build_schema_with_config(&graphql_config);

    HttpServer::new(move || {
        let mut app = App::new()
            .app_data(web::Data::new(schema.clone()))
            .app_data(web::Data::new(clients.clone()));

        // Only expose playground and introspection in development
        if graphql_config.playground_enabled {
            app = app
                .route("/", web::get().to(graphiql_handler))
                .route("/graphql/playground", web::get().to(playground_handler));
        }

        app.route("/health", web::get().to(health_handler))
            .route("/graphql", web::post().to(graphql_handler))
            .route("/schema.graphql", web::get().to(schema_handler))
    })
    .bind("0.0.0.0:8080")?
    .run()
    .await
}

fn build_schema_with_config(config: &GraphQLConfig) -> Schema<Query, Mutation, EmptySubscription> {
    let mut schema_builder = Schema::build(Query, Mutation, EmptySubscription);

    if !config.introspection_enabled {
        schema_builder = schema_builder.introspection_enabled(false);
    }

    schema_builder.finish()
}
```

---

## 7. DATABASE: Connection Pool Tuning

### File: `backend/graphql-gateway/src/config.rs`

```rust
use sqlx::postgres::PgPoolOptions;
use std::time::Duration;

pub async fn create_database_pool(database_url: &str) -> Result<PgPool> {
    // Service-specific configuration
    let service_name = std::env::var("SERVICE_NAME").unwrap_or_else(|_| "unknown".to_string());

    let (min_conns, max_conns) = match service_name.as_str() {
        "graphql-gateway" => (10, 50),
        "feed-service" => (8, 40),
        "social-service" => (8, 30),
        "content-service" => (5, 25),
        _ => (5, 20),
    };

    PgPoolOptions::new()
        .min_connections(min_conns)
        .max_connections(max_conns)
        .acquire_timeout(Duration::from_secs(10))
        .connect_timeout(Duration::from_secs(5))
        .idle_timeout(Duration::from_secs(300))
        .max_lifetime(Duration::from_secs(1800))
        .connect(database_url)
        .await
        .context(format!(
            "Failed to create database pool for {}",
            service_name
        ))
}
```

### File: Update `k8s/graphql-gateway/deployment.yaml`

```yaml
spec:
  containers:
  - name: graphql-gateway
    env:
    - name: DB_MAX_CONNECTIONS
      value: "50"  # Increased from 20
    - name: DB_MIN_CONNECTIONS
      value: "10"  # Increased from 5
    - name: DB_CONNECT_TIMEOUT
      value: "5"
    - name: DB_IDLE_TIMEOUT
      value: "300"
```

---

## Deployment Checklist

### Before Deploying Changes:

- [ ] All tests pass: `cargo test --workspace`
- [ ] No clippy warnings: `cargo clippy --workspace`
- [ ] Format checked: `cargo fmt --check`
- [ ] Kubernetes manifests valid: `kubectl apply --dry-run=client -f k8s/`
- [ ] Database migrations safe: `sqlx migrate verify`
- [ ] No hardcoded secrets: `grep -r "password\|key\|token" --exclude-dir=target`
- [ ] iOS builds without warnings
- [ ] Load test shows acceptable latency

### Deployment Order:

1. **Backend Services**: Deploy updated services with timeout support
2. **Kubernetes**: Apply security patches (security context, network policies)
3. **GraphQL Gateway**: Update config and redeploy
4. **iOS App**: Deploy certificate pinning
5. **Database**: Run migrations in maintenance window

---

**Implementation Time**: 3-5 days (depending on test coverage)
**Risk Level**: Medium (requires careful testing)
**Rollback Plan**: Keep previous image tags available for rollback
