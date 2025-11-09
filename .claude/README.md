# Nova Project - Claude Code Configuration

**Version**: 1.0
**Last Updated**: 2025-11-09
**Tech Stack**: Rust, gRPC (Tonic), PostgreSQL, Redis, Kafka, Kubernetes

---

## Overview

This directory contains specialized AI agents, knowledge skills, and workflow commands optimized for the Nova social media platform microservices architecture.

## Directory Structure

```
.claude/
├── agents/                    # Specialized AI expert agents
│   ├── rust-microservices-architect.md
│   ├── grpc-service-builder.md
│   ├── database-migration-expert.md
│   ├── k8s-deployment-engineer.md
│   └── performance-auditor.md
│
├── skills/                    # Knowledge reference libraries
│   ├── rust-async-patterns/
│   │   └── SKILL.md
│   ├── grpc-best-practices/
│   │   └── SKILL.md
│   ├── microservices-architecture/
│   │   └── SKILL.md
│   ├── k8s-deployment-patterns/
│   │   └── SKILL.md
│   └── database-optimization/
│       └── SKILL.md
│
├── commands/                  # Slash commands for workflows
│   ├── grpc.new-service.md
│   ├── db.migrate.md
│   ├── k8s.deploy.md
│   ├── perf.audit.md
│   ├── workflow.feature.md
│   └── speckit.*.md          # Existing spec workflow commands
│
└── README.md                  # This file
```

---

## Specialized Agents

Agents are AI experts with reasoning capabilities who can orchestrate complex tasks and make architectural decisions.

### 1. rust-microservices-architect

**Model**: Sonnet (Claude 3.5)
**Purpose**: Service boundary definition, architecture design, event-driven patterns

**When to use**:
- Designing new microservices
- Defining service boundaries using DDD
- Planning event-driven communication (Kafka)
- Refactoring monolithic features
- Solving distributed system challenges

**Invoke with Task tool**:
```
Task: Design service boundaries for {feature}
Agent: rust-microservices-architect
Prompt: |
  Design architecture for: {requirements}

  Provide:
  1. Service boundary definition
  2. Data model (entities)
  3. gRPC interface outline
  4. Integration points with existing services
  5. Event sourcing requirements
```

**Capabilities**:
- DDD bounded contexts
- Database-per-service pattern
- Saga pattern for distributed transactions
- Outbox pattern for reliable events
- Circuit breaker and resilience patterns

---

### 2. grpc-service-builder

**Model**: Sonnet
**Purpose**: gRPC service implementation with Tonic and Protocol Buffers

**When to use**:
- Implementing new gRPC services
- Creating .proto schemas
- Building service clients with retry logic
- Adding streaming (server, client, bidirectional)
- Implementing authentication interceptors

**Invoke with Task tool**:
```
Task: Implement gRPC service
Agent: grpc-service-builder
Prompt: |
  Implement gRPC service: {service-name}

  Based on architecture from rust-microservices-architect:
  1. Proto schema (proto/{service}/v1/)
  2. Tonic server implementation
  3. Client library with retry logic
  4. Integration tests
```

**Capabilities**:
- Proto schema design (versioning, evolution)
- Tonic server/client code generation
- Authentication/authorization interceptors
- Metrics and tracing interceptors
- Server/client streaming patterns
- Error handling with gRPC Status codes

---

### 3. database-migration-expert

**Model**: Sonnet
**Purpose**: PostgreSQL migrations with zero-downtime strategies using sqlx-cli

**When to use**:
- Creating database migrations
- Planning schema evolution
- Refactoring database structure
- Ensuring zero-downtime deployments
- Designing rollback procedures

**Invoke with Task tool**:
```
Task: Create database migration
Agent: database-migration-expert
Prompt: |
  Create migration for {service-name}:

  Change: {description}

  Requirements:
  1. Use expand-contract pattern
  2. Zero-downtime deployment
  3. Include rollback SQL
  4. Safety checks (IF NOT EXISTS)
```

**Capabilities**:
- Expand-contract migration pattern
- SQLx migration file generation
- Foreign key strategy (ON DELETE/UPDATE)
- Index creation (CONCURRENTLY)
- Data backfill strategies
- Rollback procedures

---

### 4. k8s-deployment-engineer

**Model**: Sonnet
**Purpose**: Production-grade Kubernetes deployment manifests

**When to use**:
- Creating K8s Deployment manifests
- Configuring HorizontalPodAutoscaler
- Setting up health probes
- Managing ConfigMaps and Secrets
- Troubleshooting deployment issues
- Optimizing resource allocation

**Invoke with Task tool**:
```
Task: Generate K8s manifests
Agent: k8s-deployment-engineer
Prompt: |
  Create production K8s manifests for {service-name}:

  Files needed:
  1. Deployment (resource limits, probes)
  2. Service (ClusterIP)
  3. HPA (auto-scaling)
  4. ConfigMap/Secret
  5. PodDisruptionBudget
```

**Capabilities**:
- Deployment manifests with best practices
- Resource requests/limits (CPU, memory)
- Liveness, readiness, startup probes
- HPA with scale-up/scale-down policies
- Pod anti-affinity for high availability
- Graceful shutdown configuration
- Security contexts (non-root, read-only fs)

---

### 5. performance-auditor

**Model**: Sonnet
**Purpose**: Performance profiling and optimization for Rust async applications

**When to use**:
- Investigating performance issues
- Profiling CPU/memory usage
- Analyzing Tokio async runtime
- Optimizing database queries
- Identifying bottlenecks
- Benchmarking before production

**Invoke with Task tool**:
```
Task: Profile and optimize service
Agent: performance-auditor
Prompt: |
  Analyze performance for {service-name}:

  Focus areas:
  - CPU profiling (flamegraph)
  - Memory allocation
  - Async runtime (tokio-console)
  - Database query performance
```

**Capabilities**:
- CPU profiling with flamegraph
- Memory profiling (valgrind, heaptrack)
- Tokio async runtime analysis (tokio-console)
- Database query optimization (pg_stat_statements)
- Benchmark suite with criterion
- Optimization action plans with code snippets

---

## Knowledge Skills

Skills are reference manuals with code examples, patterns, and best practices. They auto-activate based on context.

### 1. rust-async-patterns

**File**: `skills/rust-async-patterns/SKILL.md`

**When auto-activated**:
- Working with Tokio runtime
- Implementing async handlers
- Managing concurrent tasks
- Using async/await patterns

**Key patterns included**:
- Connection pooling (SQLx, Redis with deadpool)
- Graceful shutdown (signal handling)
- Task spawning and management
- Channels (MPSC, broadcast)
- Semaphore for rate limiting
- Select for racing futures
- Circuit breaker implementation
- Retry with exponential backoff

**Common pitfalls covered**:
- Blocking the runtime (use `tokio::time::sleep`)
- Holding locks across await points
- Unbounded task spawning

---

### 2. grpc-best-practices

**File**: `skills/grpc-best-practices/SKILL.md`

**When auto-activated**:
- Writing .proto schemas
- Implementing Tonic services
- Creating gRPC clients
- Working with streaming

**Key patterns included**:
- Proto schema design (versioning, evolution)
- Tonic server implementation
- Authentication interceptor
- Client with retry logic
- Server streaming (ReceiverStream)
- Status code mapping guide

**Best practices**:
- Use versioned packages (`package user.v1`)
- Include timestamps (google.protobuf.Timestamp)
- Design for evolution (add fields with new numbers)
- Implement health checks (tonic::health)
- Add request tracing (OpenTelemetry)

---

### 3. microservices-architecture

**File**: `skills/microservices-architecture/SKILL.md`

**When auto-activated**:
- Designing service boundaries
- Implementing event-driven communication
- Building distributed systems
- Solving inter-service challenges

**Key patterns included**:
- Service boundary definition (DDD)
- Event-driven communication (Kafka)
- Saga pattern (choreography-based)
- Circuit breaker implementation
- API Gateway pattern
- Outbox pattern (transactional messaging)

**Anti-patterns covered**:
- Distributed monolith
- Breaking service boundaries
- Chatty services (N+1 calls)

---

### 4. k8s-deployment-patterns

**File**: `skills/k8s-deployment-patterns/SKILL.md`

**When auto-activated**:
- Creating Deployment manifests
- Configuring auto-scaling
- Setting up health checks
- Managing ConfigMaps/Secrets

**Key patterns included**:
- Production Deployment (resource management, probes)
- HorizontalPodAutoscaler (HPA)
- Service configuration (ClusterIP)
- ConfigMap & Secrets
- PodDisruptionBudget
- Resource quotas

**Sizing guidelines**:
| Service Load | Requests (CPU/Mem) | Limits (CPU/Mem) |
|-------------|-------------------|------------------|
| Low         | 50m / 64Mi        | 200m / 256Mi     |
| Medium      | 100m / 128Mi      | 500m / 512Mi     |
| High        | 200m / 256Mi      | 1000m / 1Gi      |

---

### 5. database-optimization

**File**: `skills/database-optimization/SKILL.md`

**When auto-activated**:
- Writing database queries
- Creating indexes
- Optimizing slow queries
- Configuring connection pools

**Key patterns included**:
- Efficient indexing (single, composite, partial, covering)
- Query optimization (N+1 prevention, EXPLAIN ANALYZE)
- Connection pool configuration (SQLx)
- Batch operations (QueryBuilder, UNNEST)
- Caching strategy (Redis)
- Transaction management

**Performance monitoring**:
- Slow query identification (pg_stat_statements)
- Index usage statistics
- Connection pool sizing formula

---

## Slash Commands (Workflows)

Commands orchestrate multi-step workflows by invoking agents and skills.

### Project-Specific Commands

#### 1. /grpc.new-service

**Purpose**: Create a complete new gRPC microservice from scratch

**Usage**:
```
/grpc.new-service <service-name> <description>
```

**Example**:
```
/grpc.new-service payment-service Handle payment processing and transactions
```

**What it does**:
1. Invokes `rust-microservices-architect` for service design
2. Invokes `grpc-service-builder` for implementation
3. Invokes `database-migration-expert` for schema
4. Invokes `k8s-deployment-engineer` for manifests
5. Generates Cargo.toml, Dockerfile, README

**Files created**:
- `proto/{service}/v1/{service}.proto`
- `backend/{service}/src/main.rs`
- `backend/grpc-clients/src/{service}_client.rs`
- `backend/{service}/migrations/001_create_{service}_tables.sql`
- `k8s/microservices/{service}-*.yaml`

---

#### 2. /db.migrate

**Purpose**: Manage PostgreSQL migrations with zero-downtime strategies

**Usage**:
```
/db.migrate <action> [service-name] [description]
```

**Actions**:
- `create` - Create new migration file
- `plan` - Show pending migrations
- `run` - Execute pending migrations (with safety checks)
- `revert` - Rollback last migration
- `status` - Show migration status for all services

**Examples**:
```
/db.migrate create user-service add-email-verification-column
/db.migrate plan user-service
/db.migrate run user-service
/db.migrate revert user-service
/db.migrate status
```

**Safety features**:
- Pre-flight validation (blocking operations, lock time)
- Confirmation prompts for destructive operations
- Automatic rollback verification
- Post-migration schema verification
- Regenerate SQLx metadata

---

#### 3. /k8s.deploy

**Purpose**: Deploy microservices to Kubernetes with production-grade configurations

**Usage**:
```
/k8s.deploy <action> <service-name> [environment]
```

**Actions**:
- `generate` - Generate K8s manifests
- `apply` - Deploy service to cluster
- `update` - Update existing deployment (rolling update)
- `rollback` - Rollback to previous version
- `status` - Check deployment status
- `logs` - Tail service logs
- `scale` - Scale replicas manually

**Examples**:
```
/k8s.deploy generate user-service
/k8s.deploy apply user-service staging
/k8s.deploy status user-service production
/k8s.deploy rollback user-service production
/k8s.deploy scale user-service 5
```

**Safety features**:
- Pre-deployment manifest validation
- Production deployment checklist
- Health verification after deployment
- Gradual rollout monitoring
- Automatic smoke tests

---

#### 4. /perf.audit

**Purpose**: Profile and optimize Rust microservice performance

**Usage**:
```
/perf.audit <service-name> [profile-type]
```

**Profile types**:
- `cpu` - CPU profiling with flamegraph
- `memory` - Memory allocation profiling
- `async` - Tokio async runtime analysis
- `database` - Database query performance
- `all` - Run all profiling types (default)

**Examples**:
```
/perf.audit user-service
/perf.audit content-service cpu
/perf.audit feed-service database
```

**What it does**:
1. Runs profiling tools (flamegraph, valgrind, tokio-console)
2. Analyzes results and identifies bottlenecks
3. Generates optimization recommendations
4. Provides code snippets for top 3 fixes
5. Creates Prometheus alerts for monitoring
6. Sets up continuous profiling in CI

---

#### 5. /workflow.feature

**Purpose**: End-to-end workflow for implementing a complete feature across multiple services

**Usage**:
```
/workflow.feature <feature-description>
```

**Example**:
```
/workflow.feature Add real-time notifications when users receive new messages
```

**Workflow phases**:

1. **Feature Specification** (`/speckit.specify`)
   - Create feature branch
   - Generate spec.md
   - Quality validation

2. **Architecture Design** (`rust-microservices-architect`)
   - Service scope analysis
   - Integration points
   - Data flow design
   - Technical decisions

3. **Task Breakdown** (`/speckit.plan`, `/speckit.tasks`)
   - Implementation plan
   - Dependency-ordered tasks
   - Test requirements

4. **Multi-Service Implementation**
   - Database migrations (`/db.migrate`)
   - gRPC service updates (`grpc-service-builder`)
   - Event-driven integration (`rust-microservices-architect`)

5. **Implementation Execution** (`/speckit.implement`)
   - TDD approach (tests first)
   - Phase-by-phase execution

6. **Deployment Preparation**
   - Generate K8s manifests (`/k8s.deploy generate`)
   - Performance validation (`/perf.audit`)

7. **Deployment Workflow**
   - Deploy to dev → staging → production
   - Gradual rollout with monitoring

8. **Observability Setup**
   - Grafana dashboards
   - Prometheus alerts

9. **Documentation and Handoff**
   - Update README
   - Create runbook
   - Update API docs

---

### Speckit Commands (Existing)

These commands work with feature specifications and planning:

- `/speckit.specify` - Create feature specification
- `/speckit.clarify` - Clarify underspecified areas
- `/speckit.plan` - Generate technical implementation plan
- `/speckit.tasks` - Generate dependency-ordered task list
- `/speckit.analyze` - Cross-artifact consistency analysis
- `/speckit.implement` - Execute implementation plan
- `/speckit.checklist` - Generate custom checklist
- `/speckit.constitution` - Create/update project constitution

**Documentation**: See individual command files in `.claude/commands/speckit.*.md`

---

## Usage Examples

### Example 1: Create New Microservice

**Scenario**: Add a new notification service

```bash
# Step 1: Create the service
/grpc.new-service notification-service Send real-time and batch notifications to users

# This invokes all agents and creates:
# - Proto schema
# - Server implementation
# - Client library
# - Database migration
# - K8s manifests
# - Tests

# Step 2: Review generated code

# Step 3: Build and test
cd backend/notification-service
cargo build
cargo test

# Step 4: Apply migration
/db.migrate run notification-service

# Step 5: Deploy to dev
/k8s.deploy apply notification-service dev
```

---

### Example 2: Add Feature to Existing Service

**Scenario**: Add email verification to user-service

```bash
# Step 1: Create specification
/workflow.feature Add email verification with confirmation link sent via email

# This runs the full workflow:
# - Specification
# - Architecture design
# - Task breakdown
# - Implementation
# - Deployment

# Step 2: Review spec and confirm

# Step 3: Let workflow complete implementation

# Step 4: Deploy gradually
/k8s.deploy apply user-service staging
# Monitor and verify
/k8s.deploy apply user-service production
```

---

### Example 3: Optimize Slow Service

**Scenario**: Feed-service has high latency

```bash
# Step 1: Profile all aspects
/perf.audit feed-service all

# Step 2: Review findings
# - CPU hotspots identified
# - N+1 database queries found
# - Memory leak detected

# Step 3: Implement fixes based on recommendations

# Step 4: Re-profile to verify improvement
/perf.audit feed-service

# Step 5: Deploy optimized version
/k8s.deploy update feed-service production
```

---

### Example 4: Database Schema Migration

**Scenario**: Add new column to users table

```bash
# Step 1: Create migration with expand-contract
/db.migrate create user-service add-last-login-timestamp

# Reviews generated migration file
# backend/user-service/migrations/003_add_last_login_timestamp.sql

# Step 2: Apply to dev first
DATABASE_URL=dev /db.migrate run user-service

# Step 3: Deploy updated service to dev (reads new column)
/k8s.deploy apply user-service dev

# Step 4: Apply to staging and production
DATABASE_URL=staging /db.migrate run user-service
/k8s.deploy apply user-service staging

DATABASE_URL=production /db.migrate run user-service
/k8s.deploy apply user-service production
```

---

## Best Practices

### When to Use Agents vs Skills

**Use Agents when**:
- You need reasoning and decision-making
- Task requires orchestration of multiple steps
- Architectural design is needed
- Trade-off analysis required

**Use Skills when**:
- You need code examples and patterns
- Reference implementation needed
- Learning best practices
- Quick lookup of syntax

**Example**:
```
❌ Wrong: "Use rust-async-patterns skill to design service"
✅ Right: "Use rust-microservices-architect agent to design service"
           (Agent may reference rust-async-patterns skill for implementation details)
```

### Agent Invocation Pattern

Always provide clear context when invoking agents:

```
Task: {concise task description}
Agent: {agent-name}
Prompt: |
  {detailed requirements}

  Provide:
  1. {expected output 1}
  2. {expected output 2}
  3. {expected output 3}

  Use skills: {relevant-skill-1}, {relevant-skill-2}
```

### Command Composition

Compose commands for complex workflows:

```bash
# Full feature workflow
/workflow.feature {description}

# Or manual composition
/speckit.specify {description}
# Review spec
/speckit.plan
/speckit.tasks
/speckit.implement
/perf.audit {service}
/k8s.deploy apply {service} production
```

---

## Integration with Project

### Tech Stack Alignment

All agents and skills are tailored to Nova's tech stack:

**Backend**:
- Rust (Tokio runtime)
- gRPC (Tonic, prost)
- PostgreSQL (SQLx)
- Redis (deadpool-redis)
- Apache Kafka

**Infrastructure**:
- Kubernetes (EKS)
- Prometheus + Grafana
- Distributed tracing (OpenTelemetry)

**Microservices** (10 services):
- user-service
- content-service
- feed-service
- media-service
- messaging-service
- auth-service
- search-service
- notification-service
- events-service
- streaming-service

### File Structure Convention

```
backend/
├── {service-name}/
│   ├── src/
│   │   ├── main.rs           # Tonic server
│   │   ├── handlers/         # gRPC handlers
│   │   ├── models/           # Data models
│   │   └── lib.rs
│   ├── tests/
│   │   └── grpc_tests.rs     # Integration tests
│   ├── migrations/           # SQLx migrations
│   ├── Cargo.toml
│   ├── build.rs              # Tonic build
│   ├── Dockerfile
│   └── README.md
├── grpc-clients/             # Shared client library
└── shared/                   # Shared libraries
    ├── error-types/
    ├── grpc-metrics/
    └── crypto-core/

proto/
└── {service-name}/
    └── v1/
        └── {service-name}.proto

k8s/
└── microservices/
    ├── {service-name}-deployment.yaml
    ├── {service-name}-service.yaml
    ├── {service-name}-hpa.yaml
    ├── {service-name}-configmap.yaml
    ├── {service-name}-secret.yaml
    └── {service-name}-pdb.yaml
```

---

## Troubleshooting

### Agent Not Responding

**Problem**: Agent invocation times out or returns empty response

**Solutions**:
1. Verify agent name matches file name (case-sensitive)
2. Check `model` field in agent frontmatter (should be `sonnet`)
3. Simplify the prompt - break into smaller tasks
4. Check context size - large prompts may fail

### Skill Not Auto-Activating

**Problem**: Skill doesn't appear in context when needed

**Solutions**:
1. Verify YAML frontmatter format in `SKILL.md`
2. Check `description` field has relevant keywords
3. Manually reference skill in agent prompt: `Use skill: {skill-name}`
4. Ensure skill directory name matches reference

### Command Execution Fails

**Problem**: Slash command returns error or unexpected behavior

**Solutions**:
1. Check command syntax: `/command <required-arg> [optional-arg]`
2. Verify all required arguments provided
3. Check file paths are absolute (not relative)
4. Review command file for specific error handling instructions

---

## Maintenance

### Updating Agents

When tech stack changes or new patterns emerge:

1. Edit agent markdown file (`.claude/agents/{agent-name}.md`)
2. Update capabilities, behavioral traits, or system prompt
3. Test with sample prompts
4. Update this README if significant changes

### Updating Skills

When adding new patterns or examples:

1. Edit skill file (`.claude/skills/{skill-name}/SKILL.md`)
2. Add code examples with explanations
3. Update "When to Use" section if needed
4. Test auto-activation with relevant prompts

### Adding New Commands

To create new workflow commands:

1. Create `.claude/commands/{category}.{command-name}.md`
2. Follow existing command structure (frontmatter + execution flow)
3. Document in this README under "Slash Commands"
4. Test end-to-end workflow

---

## Resources

### Internal Documentation

- Agent architecture: See `wshobson/agents` repository structure
- Speckit workflow: See `.claude/commands/speckit.*.md` commands
- Project tech stack: `backend/*/Cargo.toml` dependencies

### External References

- [Rust Async Book](https://rust-lang.github.io/async-book/)
- [Tokio Documentation](https://tokio.rs)
- [Tonic gRPC Guide](https://docs.rs/tonic)
- [SQLx Documentation](https://docs.rs/sqlx)
- [Kubernetes Best Practices](https://kubernetes.io/docs/concepts/)
- [Microservices Patterns](https://microservices.io/patterns/)

---

## Version History

**v1.0** (2025-11-09)
- Initial setup with 5 specialized agents
- 5 knowledge skills covering core patterns
- 5 project-specific slash commands
- End-to-end feature workflow
- Integration with existing speckit commands

---

## Contributing

When extending this configuration:

1. **Agents**: Create focused, single-responsibility experts
2. **Skills**: Provide complete code examples with explanations
3. **Commands**: Orchestrate agents and skills for workflows
4. **Testing**: Verify agents with realistic prompts before committing

---

## Support

For questions or issues:

1. Check this README first
2. Review relevant agent/skill/command documentation
3. Test with simplified prompts to isolate issues
4. Check Claude Code documentation: https://docs.claude.com

---

**May the Force be with you.**
