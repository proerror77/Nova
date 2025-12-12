# Zitadel & Nova Integration - Architecture Diagrams

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Matrix Client                               │
│                      (Element, FluffyChat, etc.)                    │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ 1. Login via SSO
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Matrix Synapse Homeserver                      │
│                                                                     │
│  Configuration:                                                     │
│  - OIDC Provider: https://id.staging.nova.app                      │
│  - Client ID: <matrix-client-id>                                   │
│  - Scopes: openid, profile, email                                  │
└────────────────────────────┬────────────────────────────────────────┘
                             │
                             │ 2. OIDC Auth Flow
                             │    (Authorization Code Grant)
                             ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            Zitadel                                  │
│                     (OIDC Identity Provider)                        │
│                                                                     │
│  External Domain: id.staging.nova.app                              │
│  Port: 443 (HTTPS via Ingress)                                     │
│  Database: PostgreSQL (zitadel schema)                             │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────┐    │
│  │              Zitadel Action: nova_claims_enrichment        │    │
│  │                                                             │    │
│  │  Flow Type: Complement Token                               │    │
│  │  Triggers:                                                  │    │
│  │    - Pre Userinfo creation                                 │    │
│  │    - Pre access token creation                             │    │
│  │                                                             │    │
│  │  JavaScript Code:                                           │    │
│  │    1. Extract user ID from context                         │    │
│  │    2. HTTP GET to identity-service                         │    │
│  │    3. Parse JSON response                                  │    │
│  │    4. Inject claims into OIDC token                        │    │
│  │                                                             │    │
│  │  Environment Variables:                                     │    │
│  │    - IDENTITY_SERVICE_URL: http://identity-service:8081    │    │
│  │    - INTERNAL_API_KEY: <secret>                            │    │
│  └───────────────┬───────────────────────────────────────────┘    │
└──────────────────┼──────────────────────────────────────────────────┘
                   │
                   │ 3. Fetch User Claims
                   │    GET /internal/zitadel/user-claims/:user_id
                   │    Header: X-Internal-API-Key: <secret>
                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      Identity Service                               │
│                    (Rust - Tokio Runtime)                           │
│                                                                     │
│  ┌──────────────────────┐           ┌──────────────────────┐       │
│  │   HTTP Server        │           │   gRPC Server        │       │
│  │   Port: 8081         │           │   Port: 9081         │       │
│  │                      │           │                      │       │
│  │  Routes:             │           │  Services:           │       │
│  │  - /health           │           │  - Register          │       │
│  │  - /internal/        │           │  - Login             │       │
│  │    zitadel/          │           │  - VerifyToken       │       │
│  │    user-claims/:id   │           │  - GetUser           │       │
│  │                      │           │  - ...               │       │
│  │  Auth Middleware:    │           │                      │       │
│  │  - X-Internal-API-   │           │  Auth: gRPC TLS      │       │
│  │    Key validation    │           │                      │       │
│  └──────────┬───────────┘           └──────────────────────┘       │
│             │                                                       │
│             │ 4. Query User Data                                   │
│             ▼                                                       │
│  ┌─────────────────────────────────────────────────────────┐       │
│  │           Database Repository (db::users)               │       │
│  │                                                          │       │
│  │  Function: find_by_id(user_id)                          │       │
│  │  Returns: User struct with all profile fields           │       │
│  └─────────────────────┬────────────────────────────────────┘       │
└────────────────────────┼──────────────────────────────────────────┘
                         │
                         │ 5. SQL Query
                         ▼
┌─────────────────────────────────────────────────────────────────────┐
│                          PostgreSQL                                 │
│                                                                     │
│  Database: nova_identity                                            │
│  Table: users                                                       │
│                                                                     │
│  Columns:                                                           │
│    - id (UUID, PRIMARY KEY)                                         │
│    - username (VARCHAR, UNIQUE)                                     │
│    - email (VARCHAR, UNIQUE)                                        │
│    - email_verified (BOOLEAN)                                       │
│    - display_name (VARCHAR)                                         │
│    - avatar_url (VARCHAR)                                           │
│    - first_name, last_name (VARCHAR)                                │
│    - bio, location (TEXT)                                           │
│    - phone_number, phone_verified                                   │
│    - created_at, updated_at (TIMESTAMPTZ)                           │
│    - ... (see migrations)                                           │
└─────────────────────────────────────────────────────────────────────┘
```

## Sequence Diagram: OIDC Token Issuance with Claims Enrichment

```
Matrix Client    Synapse      Zitadel         Zitadel Action    Identity-Service    PostgreSQL
      │              │            │                   │                  │               │
      │─Login────────>│           │                   │                  │               │
      │              │            │                   │                  │               │
      │              │─OIDC Start>│                   │                  │               │
      │              │            │                   │                  │               │
      │<─────────────┼Auth URL────│                   │                  │               │
      │              │            │                   │                  │               │
      │─Auth User────────────────>│                   │                  │               │
      │              │            │                   │                  │               │
      │<─Auth Code───────────────│                   │                  │               │
      │              │            │                   │                  │               │
      │─Code─────────>│           │                   │                  │               │
      │              │            │                   │                  │               │
      │              │─Exchange──>│                   │                  │               │
      │              │   Code     │                   │                  │               │
      │              │            │                   │                  │               │
      │              │            │─Trigger Action───>│                  │               │
      │              │            │  (Pre-Token)      │                  │               │
      │              │            │                   │                  │               │
      │              │            │                   │─HTTP GET─────────>│              │
      │              │            │                   │  /internal/      │              │
      │              │            │                   │  zitadel/user-   │              │
      │              │            │                   │  claims/:id      │              │
      │              │            │                   │  Header:         │              │
      │              │            │                   │  X-Internal-API- │              │
      │              │            │                   │  Key: <secret>   │              │
      │              │            │                   │                  │              │
      │              │            │                   │                  │─Query User──>│
      │              │            │                   │                  │  SELECT *    │
      │              │            │                   │                  │  FROM users  │
      │              │            │                   │                  │  WHERE id=.. │
      │              │            │                   │                  │              │
      │              │            │                   │                  │<User Data────│
      │              │            │                   │                  │              │
      │              │            │                   │<JSON Response────│              │
      │              │            │                   │  {               │              │
      │              │            │                   │    sub: uuid,    │              │
      │              │            │                   │    username,     │              │
      │              │            │                   │    email,        │              │
      │              │            │                   │    picture,      │              │
      │              │            │                   │    ...           │              │
      │              │            │                   │  }               │              │
      │              │            │                   │                  │              │
      │              │            │                   │─Inject Claims───>│              │
      │              │            │                   │  api.v1.claims.  │              │
      │              │            │                   │  setClaim(...)   │              │
      │              │            │                   │                  │              │
      │              │            │<Action Complete──│                  │              │
      │              │            │                   │                  │              │
      │              │<ID Token───│                   │                  │              │
      │              │   {        │                   │                  │              │
      │              │   sub: uuid│                   │                  │              │
      │              │   preferred│                   │                  │              │
      │              │   _username│                   │                  │              │
      │              │   email,   │                   │                  │              │
      │              │   ...      │                   │                  │              │
      │              │   }        │                   │                  │              │
      │              │            │                   │                  │              │
      │<Tokens───────│            │                   │                  │              │
      │  (Access +   │            │                   │                  │              │
      │   Refresh)   │            │                   │                  │              │
      │              │            │                   │                  │              │
```

## Network Architecture (Kubernetes)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                              │
│                       Namespace: nova-backend                           │
│                                                                         │
│  ┌────────────────────────────────────────────────────────────────┐    │
│  │                          Ingress                                │    │
│  │                    (NGINX Ingress Controller)                   │    │
│  │                                                                 │    │
│  │  Routes:                                                        │    │
│  │    id.staging.nova.app → zitadel:8080                          │    │
│  │                                                                 │    │
│  │  TLS: cert-manager (Let's Encrypt)                             │    │
│  └────────────────────────┬────────────────────────────────────────┘    │
│                           │                                             │
│                           ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      Zitadel Deployment                         │   │
│  │                                                                 │   │
│  │  Replicas: 1                                                    │   │
│  │  Image: ghcr.io/zitadel/zitadel:v2.62.1                        │   │
│  │  Ports:                                                         │   │
│  │    - 8080 (HTTP)                                                │   │
│  │    - 8081 (gRPC)                                                │   │
│  │                                                                 │   │
│  │  ConfigMap: zitadel-runtime-config                             │   │
│  │  Secrets: zitadel-secrets, zitadel-action-secrets              │   │
│  │                                                                 │   │
│  │  Actions: nova_claims_enrichment (configured via UI)           │   │
│  └────────────────────────┬────────────────────────────────────────┘   │
│                           │                                             │
│                           │ Internal HTTP Call                          │
│                           │ (ClusterIP Service)                         │
│                           ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │               Identity Service Deployment                       │   │
│  │                                                                 │   │
│  │  Replicas: 3                                                    │   │
│  │  Image: nova-identity-service:latest                           │   │
│  │  Ports:                                                         │   │
│  │    - 8081 (HTTP - Internal APIs)                               │   │
│  │    - 9081 (gRPC - Backend Services)                            │   │
│  │                                                                 │   │
│  │  Environment Variables:                                         │   │
│  │    - HTTP_PORT=8081                                             │   │
│  │    - SERVER_PORT=9081 (gRPC)                                   │   │
│  │    - INTERNAL_API_KEY (from secret)                            │   │
│  │    - DATABASE_URL, REDIS_URL, KAFKA_BROKERS                    │   │
│  │                                                                 │   │
│  │  Secrets: identity-service-secrets                             │   │
│  │                                                                 │   │
│  │  Service: identity-service (ClusterIP)                         │   │
│  │    - Port 8081 → 8081 (HTTP)                                   │   │
│  │    - Port 9081 → 9081 (gRPC)                                   │   │
│  └────────────────────────┬────────────────────────────────────────┘   │
│                           │                                             │
│                           │ SQL Queries                                 │
│                           ▼                                             │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    PostgreSQL StatefulSet                       │   │
│  │                                                                 │   │
│  │  Databases:                                                     │   │
│  │    - zitadel (Zitadel schema)                                  │   │
│  │    - nova_identity (Users, sessions, etc.)                     │   │
│  │                                                                 │   │
│  │  Service: postgres:5432 (ClusterIP)                           │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Security Boundaries

```
┌────────────────────────────────────────────────────────────────┐
│                      Public Internet                           │
│                                                                │
│  Users, Matrix Clients                                         │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         │ HTTPS (TLS 1.3)
                         │ Port 443
                         ▼
┌────────────────────────────────────────────────────────────────┐
│                    Security Boundary 1                         │
│                    (Ingress / WAF)                             │
│                                                                │
│  - TLS Termination                                             │
│  - Rate Limiting                                               │
│  - DDoS Protection                                             │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         │ HTTP (internal)
                         │ ClusterIP Network
                         ▼
┌────────────────────────────────────────────────────────────────┐
│                    Security Boundary 2                         │
│               (Kubernetes Network Policies)                    │
│                                                                │
│  Allowed Traffic:                                              │
│    - Ingress → Zitadel:8080                                   │
│    - Zitadel → Identity-Service:8081 (HTTP)                   │
│    - Backend Services → Identity-Service:9081 (gRPC)          │
│    - Identity-Service → PostgreSQL:5432                       │
│                                                                │
│  Blocked:                                                      │
│    - External → Identity-Service (no ingress)                 │
│    - Direct Pod-to-Pod (except allowed above)                 │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         │ X-Internal-API-Key
                         │ Authentication
                         ▼
┌────────────────────────────────────────────────────────────────┐
│                    Security Boundary 3                         │
│              (Application-Level Auth)                          │
│                                                                │
│  Identity Service HTTP Middleware:                             │
│    - Validate X-Internal-API-Key header                       │
│    - Reject unauthenticated requests                          │
│    - Log all access attempts                                  │
│                                                                │
│  gRPC Interceptor:                                             │
│    - Validate INTERNAL_GRPC_API_KEY (optional)                │
│    - Correlation ID injection                                 │
└────────────────────────┬───────────────────────────────────────┘
                         │
                         │ SQL Queries
                         │ (Connection Pool)
                         ▼
┌────────────────────────────────────────────────────────────────┐
│                    Security Boundary 4                         │
│                  (Database Access Control)                     │
│                                                                │
│  PostgreSQL:                                                   │
│    - SSL/TLS connections (optional, recommended)              │
│    - Role-based access control                                │
│    - Row-level security (if needed)                           │
│    - Audit logging                                             │
└────────────────────────────────────────────────────────────────┘
```

## Data Flow: User Profile Update Propagation

```
┌──────────────────────────────────────────────────────────────────┐
│  Scenario: User updates profile (e.g., changes avatar)          │
└──────────────────────────────────────────────────────────────────┘

Nova App      API Gateway   Identity-Service   PostgreSQL   Zitadel
    │               │               │               │          │
    │─Update────────>│              │               │          │
    │  Profile      │              │               │          │
    │               │              │               │          │
    │               │─gRPC Call────>│              │          │
    │               │  UpdateUser  │               │          │
    │               │  Profile     │               │          │
    │               │              │               │          │
    │               │              │─SQL UPDATE────>│          │
    │               │              │  SET avatar_  │          │
    │               │              │  url=...      │          │
    │               │              │               │          │
    │               │              │<Success───────│          │
    │               │              │               │          │
    │               │<Response─────│               │          │
    │               │              │               │          │
    │<Success───────│              │               │          │
    │               │              │               │          │
    │               │              │               │          │
    │  [Later: User logs into Matrix via Zitadel]  │          │
    │               │              │               │          │
Matrix Client  │              │               │          │
    │               │              │               │    ┌─────▼──────┐
    │─OIDC Login────┼──────────────┼───────────────────>│  Zitadel   │
    │               │              │               │    │            │
    │               │              │               │    │  Action    │
    │               │              │               │    │  Triggered │
    │               │              │               │    └─────┬──────┘
    │               │              │               │          │
    │               │              │<HTTP GET──────┼──────────│
    │               │              │ /internal/    │          │
    │               │              │ zitadel/user- │          │
    │               │              │ claims/:id    │          │
    │               │              │               │          │
    │               │              │─SQL SELECT────>│          │
    │               │              │               │          │
    │               │              │<User Data─────│          │
    │               │              │  (NEW avatar) │          │
    │               │              │               │          │
    │               │              │─JSON──────────┼─────────>│
    │               │              │  {            │          │
    │               │              │   picture:    │          │
    │               │              │   "new.jpg"   │          │
    │               │              │  }            │          │
    │               │              │               │          │
    │<ID Token──────┼──────────────┼───────────────┼──────────│
    │  {            │              │               │          │
    │   picture:    │              │               │          │
    │   "new.jpg"   │              │               │          │
    │  }            │              │               │          │

Result: Profile changes are immediately reflected in OIDC tokens
        without any manual sync or batch jobs.
```

## Failure Handling: Identity Service Unavailable

```
┌──────────────────────────────────────────────────────────────────┐
│  Scenario: Identity-Service is down during token issuance       │
└──────────────────────────────────────────────────────────────────┘

Matrix Client    Zitadel        Zitadel Action    Identity-Service
      │              │                  │                  │
      │─OIDC Login──>│                  │                  │
      │              │                  │                  │
      │              │─Trigger Action──>│                  │
      │              │                  │                  │
      │              │                  │─HTTP GET────────>│
      │              │                  │                  X  (503 Error)
      │              │                  │                  │  Service Down
      │              │                  │                  │
      │              │                  │<HTTP 503/Timeout │
      │              │                  │                  │
      │              │                  │ [Action Logic]   │
      │              │                  │ Catch Error:     │
      │              │                  │   Log error      │
      │              │                  │   Call fallback  │
      │              │                  │                  │
      │              │                  │ setFallbackClaims()
      │              │                  │   - Use Zitadel  │
      │              │                  │     user data    │
      │              │                  │   - Basic claims │
      │              │                  │                  │
      │              │<Action Complete──│                  │
      │              │  (with fallback) │                  │
      │              │                  │                  │
      │<ID Token─────│                  │                  │
      │  {           │                  │                  │
      │   sub: ...,  │                  │                  │
      │   email: ... │                  │                  │
      │   (minimal)  │                  │                  │
      │  }           │                  │                  │
      │              │                  │                  │

Result: Login succeeds even if identity-service is down.
        Token contains fallback claims from Zitadel.
        User experience: Slightly degraded (may miss custom claims)
                        but authentication still works.
```

---

These diagrams illustrate the complete architecture, data flow, security boundaries, and failure handling mechanisms of the Zitadel-Nova integration.
