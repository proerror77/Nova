# Nova Staging on GCP - 架构设计方案

**版本**: 1.0
**日期**: 2025-11-30
**环境**: Staging
**状态**: 规划阶段

---

## 目录

1. [架构概览](#架构概览)
2. [AWS vs GCP 组件映射](#aws-vs-gcp-组件映射)
3. [详细设计](#详细设计)
4. [实施路线图](#实施路线图)
5. [成本估算](#成本估算)
6. [决策矩阵](#决策矩阵)

---

## 架构概览

### GCP 环境整体架构

```
┌─────────────────────────────────────────────────────────────────┐
│                     GCP Project (banded-pad-479802-k9)          │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ VPC Network (nova-vpc)                                   │  │
│  │ CIDR: 10.0.0.0/16                                       │  │
│  │                                                          │  │
│  │  ┌─────────────────────────────────────────────────┐   │  │
│  │  │ GKE Cluster (nova-staging-gke)                │   │  │
│  │  │ - Kubernetes 1.27+                            │   │  │
│  │  │ - 2 node pools (on-demand + spot)             │   │  │
│  │  │ - Workload Identity enabled                   │   │  │
│  │  │                                               │   │  │
│  │  │  ┌─────────────────────────────────────────┐  │   │  │
│  │  │  │ 13 Microservices (Deployments)         │  │   │  │
│  │  │  │ - identity-service                      │  │   │  │
│  │  │  │ - realtime-chat-service                 │  │   │  │
│  │  │  │ - analytics-service                     │  │   │  │
│  │  │  │ ... (and others)                        │  │   │  │
│  │  │  └─────────────────────────────────────────┘  │   │  │
│  │  │                                               │   │  │
│  │  │  ┌─────────────────────────────────────────┐  │   │  │
│  │  │  │ Service Mesh (optional)                │  │   │  │
│  │  │  │ - Istio / Cloud Service Mesh           │  │   │  │
│  │  │  └─────────────────────────────────────────┘  │   │  │
│  │  └─────────────────────────────────────────────────┘   │  │
│  │                                                          │  │
│  │  ┌─────────────────────────────────────────────────┐   │  │
│  │  │ Cloud SQL (PostgreSQL)                        │   │  │
│  │  │ - db.custom-4-16gb (4 vCPU, 16GB RAM)        │   │  │
│  │  │ - 100GB storage (auto-expandable to 500GB)   │   │  │
│  │  │ - High availability (regional)               │   │  │
│  │  └─────────────────────────────────────────────────┘   │  │
│  │                                                          │  │
│  │  ┌─────────────────────────────────────────────────┐   │  │
│  │  │ Memorystore Redis                             │   │  │
│  │  │ - cache.standard-1 (1GB)                      │   │  │
│  │  │ - 3 replicas (high availability)              │   │  │
│  │  └─────────────────────────────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Artifact Registry                                        │  │
│  │ - nova-staging (13 container images)                    │  │
│  │ - Location: asia-northeast1                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Secret Manager                                           │  │
│  │ - Database credentials                                  │  │
│  │ - JWT keys                                              │  │
│  │ - ClickHouse credentials                                │  │
│  │ - S3 config (migration only)                            │  │
│  │ - Push credentials (APNs/FCM)                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Cloud Storage (Object Storage)                          │  │
│  │ - nova-staging-media (media files)                      │  │
│  │ - nova-staging-backups (database backups)               │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Cloud Load Balancing                                    │  │
│  │ - HTTPS Load Balancer (Global)                          │  │
│  │ - SSL/TLS termination                                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│               CI/CD Pipeline (GitHub Actions)                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Workload Identity Federation (OIDC)                           │
│  ↓                                                              │
│  GitHub Actions → Service Account → GCP Permissions            │
│                                                                  │
│  1. Build & Test (Rust)                                        │
│  2. Build Docker Images                                        │
│  3. Push to Artifact Registry                                  │
│  4. Deploy to GKE (kubectl)                                    │
│  5. Smoke Tests                                                │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## AWS vs GCP 组件映射

| 功能 | AWS | GCP | 说明 |
|------|-----|-----|------|
| **Kubernetes** | EKS | GKE | GCP 更简单（managed）|
| **Container Registry** | ECR | Artifact Registry | 功能相同 |
| **关系型数据库** | RDS PostgreSQL | Cloud SQL PostgreSQL | 完全兼容 |
| **缓存** | ElastiCache Redis | Memorystore Redis | 完全兼容 |
| **对象存储** | S3 | Cloud Storage | 功能基本相同 |
| **秘钥管理** | AWS Secrets Manager | Secret Manager | 功能相同 |
| **负载均衡** | ALB (Layer 7) | Cloud Load Balancing | 都支持 HTTPS |
| **VPC/网络** | VPC + Subnets | VPC + Subnets | 基本相同 |
| **身份认证** | IAM + OIDC | Workload Identity Federation | OIDC 互联网方式 |

---

## 详细设计

### 1. 网络架构

#### VPC 配置

```hcl
# GCP VPC
resource "google_compute_network" "vpc" {
  name                    = "nova-vpc"
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
}

# Primary Subnet (Nodes & Services)
resource "google_compute_subnetwork" "primary" {
  name          = "nova-primary"
  network       = google_compute_network.vpc.name
  ip_cidr_range = "10.0.0.0/20"     # 4096 IPs
  region        = "asia-northeast1"
}

# Secondary CIDR for Pods
# (auto-allocated by GKE)

# Secondary CIDR for Services
# (auto-allocated by GKE)
```

**关键差异**：
- GCP VPC 支持自动子网创建，但为了控制更细致，建议手动创建
- Pod IP 范围由 GKE 自动管理

---

### 2. GKE 集群配置

#### Cluster 创建

```hcl
resource "google_container_cluster" "primary" {
  name     = "nova-staging-gke"
  location = "asia-northeast1-a"

  # We can't create a cluster with no node pool defined, but we want to only use
  # separately managed node pools. So we create the smallest possible default
  # node pool and immediately delete it.
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.primary.name

  # Network config
  networking_mode = "VPC_NATIVE"

  cluster_secondary_range_name = "pods"
  services_secondary_range_name = "services"

  # Security
  enable_shielded_nodes   = true
  enable_network_policy   = true
  enable_intra_node_visibility = true

  # Workload Identity
  workload_identity_config {
    workload_pool = "banded-pad-479802-k9.svc.id.goog"
  }

  # Logging & Monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # IP allocation policy (required for VPC-native)
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Maintenance window
  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  labels = {
    environment = "staging"
    project     = "nova"
  }
}
```

#### Node Pool 配置

**On-Demand Node Pool (基础容量)**

```hcl
resource "google_container_node_pool" "on_demand" {
  name       = "nova-staging-on-demand"
  cluster    = google_container_cluster.primary.name
  location   = google_container_cluster.primary.location
  node_count = 2  # Staging: 2 nodes

  node_config {
    machine_type = "n2-standard-4"  # 4 vCPU, 16GB RAM
    disk_size_gb = 50
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    metadata = {
      disable-legacy-endpoints = "true"
    }

    labels = {
      pool_type   = "on-demand"
      environment = "staging"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"  # Workload Identity
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  autoscaling {
    min_node_count = 2
    max_node_count = 5
  }
}

# Spot Node Pool (可选, 降低成本)
resource "google_container_node_pool" "spot" {
  name       = "nova-staging-spot"
  cluster    = google_container_cluster.primary.name
  location   = google_container_cluster.primary.location
  node_count = 0  # Disabled for staging by default

  node_config {
    machine_type = "n2-standard-4"
    disk_size_gb = 50

    spot = true  # 等价于 AWS Spot

    labels = {
      pool_type   = "spot"
      environment = "staging"
    }

    workload_metadata_config {
      mode = "GKE_METADATA"
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  autoscaling {
    min_node_count = 0
    max_node_count = 3
  }
}
```

---

### 3. 数据库配置

#### Cloud SQL (PostgreSQL)

```hcl
resource "google_sql_database_instance" "main" {
  name             = "nova-staging"
  database_version = "POSTGRES_16"
  region           = "asia-northeast1"
  deletion_protection = false  # Staging 允许删除

  settings {
    tier              = "db-custom-4-16384"  # 4 vCPU, 16GB RAM
    availability_type = "REGIONAL"  # High Availability
    disk_type         = "PD_SSD"
    disk_size         = 100
    disk_autoresize   = true
    disk_autoresize_limit = 500

    # Backup
    backup_configuration {
      enabled            = true
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    # Maintenance
    maintenance_window {
      day          = 1  # Monday
      hour         = 3
      update_track = "stable"
    }

    # Insights
    insights_config {
      query_insights_enabled = true
      query_plans_per_minute = 5
      query_string_length    = 1024
      record_application_tags = true
    }

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.vpc.id
      require_ssl     = true
    }
  }
}

resource "google_sql_database" "nova" {
  name     = "nova"
  instance = google_sql_database_instance.main.name
}

resource "google_sql_user" "nova_admin" {
  name     = "nova_admin"
  instance = google_sql_database_instance.main.name
  password = random_password.db_password.result
  type     = "BUILT_IN"
}

# Store password in Secret Manager
resource "google_secret_manager_secret" "db_password" {
  secret_id = "nova-staging-db-password"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_password" {
  secret      = google_secret_manager_secret.db_password.id
  secret_data = random_password.db_password.result
}
```

---

### 4. 缓存配置

#### Memorystore Redis

```hcl
resource "google_redis_instance" "cache" {
  name           = "nova-staging-redis"
  tier           = "standard"
  memory_size_gb = 1
  region         = "asia-northeast1"

  redis_version       = "7.0"
  display_name        = "Nova Staging Redis Cache"

  # Network
  authorized_network = google_compute_network.vpc.id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  # Backup
  backup_configuration {
    start_time = "03:00"
  }

  # Maintenance
  maintenance_policy {
    weekly_maintenance_window {
      day        = "MONDAY"
      start_time {
        hours = 1
      }
    }
  }

  labels = {
    environment = "staging"
  }
}
```

**关键差异**：
- GCP Memorystore 支持 automated failover（类似 AWS 的 multi-AZ）
- 使用私有服务连接，无需手动处理防火墙

---

### 5. 容器镜像仓库

#### Artifact Registry

```hcl
resource "google_artifact_registry_repository" "nova" {
  location      = "asia-northeast1"
  repository_id = "nova-staging"
  description   = "Nova Staging Container Images"

  format = "DOCKER"

  docker_config {
    immutable_tags = false
  }

  labels = {
    environment = "staging"
  }
}

# IAM: Allow GKE nodes to pull images
resource "google_artifact_registry_repository_iam_member" "gke_pull" {
  repository = google_artifact_registry_repository.nova.name
  location   = google_artifact_registry_repository.nova.location
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Cleanup policy: Keep only last 10 images
resource "google_artifact_registry_cleanup_policy" "images" {
  repository    = google_artifact_registry_repository.nova.name
  location      = google_artifact_registry_repository.nova.location
  cleanup_policy_id = "keep-10-images"

  condition {
    most_recent_versions {
      keep_count = 10
    }
  }
}
```

---

### 6. 秘钥管理

#### Secret Manager

```hcl
# Database credentials
resource "google_secret_manager_secret" "db_credentials" {
  secret_id = "nova-staging-db-credentials"
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "db_credentials" {
  secret      = google_secret_manager_secret.db_credentials.id
  secret_data = jsonencode({
    username = google_sql_user.nova_admin.name
    password = random_password.db_password.result
    host     = google_sql_database_instance.main.private_ip_address
    database = google_sql_database.nova.name
  })
}

# JWT keys
resource "google_secret_manager_secret" "jwt_keys" {
  secret_id = "nova-staging-jwt-keys"
  replication {
    auto {}
  }
}

# Service account access to secrets
resource "google_secret_manager_secret_iam_member" "gke_access" {
  for_each = toset([
    google_secret_manager_secret.db_credentials.id,
    google_secret_manager_secret.jwt_keys.id,
  ])

  secret_id = each.value
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.k8s_workloads.email}"
}
```

---

### 7. 存储配置

#### Cloud Storage

```hcl
# Media files
resource "google_storage_bucket" "media" {
  name          = "nova-staging-media-${data.google_client_config.current.project}"
  location      = "ASIA-NORTHEAST1"
  force_destroy = true  # Staging only

  uniform_bucket_level_access = true

  versioning {
    enabled = false
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }
}

# Database backups
resource "google_storage_bucket" "backups" {
  name          = "nova-staging-backups-${data.google_client_config.current.project}"
  location      = "ASIA-NORTHEAST1"
  force_destroy = true

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "Delete"
    }
  }
}

# Service account for media access
resource "google_storage_bucket_iam_member" "media_access" {
  bucket = google_storage_bucket.media.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.k8s_workloads.email}"
}
```

---

### 8. 身份与访问管理 (IAM)

#### Workload Identity Federation

```hcl
# Service account for GKE workloads
resource "google_service_account" "k8s_workloads" {
  account_id   = "nova-k8s-workloads"
  display_name = "Nova Kubernetes Workloads"
}

# Service account for GKE nodes
resource "google_service_account" "gke_nodes" {
  account_id   = "nova-gke-nodes"
  display_name = "Nova GKE Nodes"
}

# GKE nodes SA can pull from Artifact Registry
resource "google_project_iam_member" "gke_artifact_pull" {
  project = data.google_client_config.current.project
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.gke_nodes.email}"
}

# Workload Identity binding (K8s SA → GCP SA)
# This will be done via Terraform or manually after cluster creation:
# kubectl annotate serviceaccount k8s-workload-sa \
#   iam.gke.io/gcp-service-account=nova-k8s-workloads@PROJECT_ID.iam.gserviceaccount.com

# Workload Identity Binding resource (in Terraform)
resource "google_service_account_iam_binding" "workload_identity" {
  service_account_id = google_service_account.k8s_workloads.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "serviceAccount:banded-pad-479802-k9.svc.id.goog[nova-staging/k8s-workload-sa]",
    "serviceAccount:banded-pad-479802-k9.svc.id.goog[nova-staging/default]"
  ]
}
```

#### GitHub Actions OIDC Integration

```hcl
# Workload Identity Provider for GitHub
resource "google_iam_workload_identity_pool" "github" {
  display_name            = "GitHub Actions"
  workload_identity_pool_id = "github-pool"
  location                = "global"
  disabled                = false
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  display_name           = "GitHub Provider"
  workload_identity_pool_id = google_iam_workload_identity_pool.github.workload_identity_pool_id
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.environment" = "assertion.environment"
  }
  attribute_condition = "assertion.aud == 'https://github.com/anthropics'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Service account for GitHub Actions
resource "google_service_account" "github_actions" {
  account_id   = "github-actions"
  display_name = "GitHub Actions CI/CD"
}

# GitHub Actions → Service Account binding
resource "google_service_account_iam_binding" "github_actions_pool" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/projects/banded-pad-479802-k9/locations/global/workloadIdentityPools/github-pool/attribute.repository/proerror/nova"
  ]
}

# Grant GitHub Actions necessary permissions
resource "google_project_iam_member" "github_artifact_push" {
  project = data.google_client_config.current.project
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

resource "google_project_iam_member" "github_gke_deploy" {
  project = data.google_client_config.current.project
  role    = "roles/container.developer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}
```

---

### 9. 负载均衡 & 入口

#### Cloud Load Balancer

```hcl
# SSL/TLS Certificate (using Google-managed certificate)
resource "google_compute_ssl_certificate" "nova" {
  name      = "nova-staging-cert"
  managed {
    domains = ["staging.novaso.cial"]  # Replace with your domain
  }
}

# Global Static IP
resource "google_compute_global_address" "nova" {
  name = "nova-staging-global-ip"
}

# Health Check
resource "google_compute_health_check" "nova" {
  name = "nova-staging-health-check"
  http_health_check {
    port         = 8080
    request_path = "/health"
  }
}

# Backend Service (GKE Service as backend)
resource "google_compute_backend_service" "nova" {
  name            = "nova-staging-backend"
  protocol        = "HTTP"
  health_checks   = [google_compute_health_check.nova.id]
  session_affinity = "NONE"
  load_balancing_scheme = "EXTERNAL"

  # Use NEG (Network Endpoint Group) with GKE
  backend {
    group = google_compute_network_endpoint_group.k8s_services.id
  }
}

# URL Map
resource "google_compute_url_map" "nova" {
  name            = "nova-staging-url-map"
  default_service = google_compute_backend_service.nova.id
}

# HTTPS Proxy
resource "google_compute_target_https_proxy" "nova" {
  name             = "nova-staging-https-proxy"
  url_map          = google_compute_url_map.nova.id
  ssl_certificates = [google_compute_ssl_certificate.nova.id]
}

# Forwarding Rule
resource "google_compute_global_forwarding_rule" "nova" {
  name       = "nova-staging-forwarding-rule"
  ip_address = google_compute_global_address.nova.address
  target     = google_compute_target_https_proxy.nova.id
  port_range = "443"
}

# HTTP to HTTPS redirect
resource "google_compute_url_map" "nova_http_redirect" {
  name = "nova-staging-http-redirect"
  default_url_redirect {
    redirect_code = "301"
    https_redirect = true
  }
}

resource "google_compute_target_http_proxy" "nova_http" {
  name    = "nova-staging-http-proxy"
  url_map = google_compute_url_map.nova_http_redirect.id
}

resource "google_compute_global_forwarding_rule" "nova_http" {
  name       = "nova-staging-http-forwarding-rule"
  ip_address = google_compute_global_address.nova.address
  target     = google_compute_target_http_proxy.nova_http.id
  port_range = "80"
}
```

**注意**: Kubernetes Ingress 与 GCP Load Balancer 的关系：
- 推荐在 K8s 中使用 `Ingress` 资源
- GKE 会自动创建 Cloud Load Balancer
- 无需手动 Terraform 管理（更简单）

---

## 实施路线图

### 阶段 1: 基础设施 (3-5 天)

- [ ] Day 1: VPC 和 GKE 集群
  - 创建 VPC 和子网
  - 创建 GKE 集群
  - 配置 node pools

- [ ] Day 2: 数据和缓存
  - 创建 Cloud SQL PostgreSQL
  - 创建 Memorystore Redis
  - 配置网络连接

- [ ] Day 3: 镜像和秘钥
  - 创建 Artifact Registry
  - 配置 Secret Manager
  - 测试 IAM 权限

- [ ] Day 4: 存储和 LB
  - 创建 Cloud Storage buckets
  - 配置 Cloud Load Balancer
  - DNS 配置

- [ ] Day 5: 验证
  - 测试所有连接
  - 负载测试
  - 文档更新

### 阶段 2: CI/CD (2-3 天)

- [ ] Day 1: OIDC 配置
  - Workload Identity Federation setup
  - GitHub Actions 服务账号配置

- [ ] Day 2: CI/CD Pipeline
  - 修改 GitHub Actions workflows
  - 测试镜像 build & push
  - 测试部署

- [ ] Day 3: 验证 & 优化
  - 端到端测试
  - 性能监控
  - 成本优化

### 阶段 3: 数据迁移 (1-2 天)

- [ ] 使用 database dumping & restore
- [ ] 验证数据完整性
- [ ] 更新连接字符串

### 阶段 4: 应用部署 (1-2 天)

- [ ] 配置 Kubernetes manifests
- [ ] 部署 13 个微服务
- [ ] Smoke tests
- [ ] 性能验证

**总计: 7-12 天** (取决于平行度和团队规模)

---

## 成本估算

### 月度成本对比 (Staging 环境)

#### GCP 成本

| 组件 | 配置 | 月度成本 |
|------|------|---------|
| **GKE** | 2 n2-standard-4 nodes (On-Demand) | $220 |
| **Cloud SQL** | db-custom-4-16gb, 100GB storage | $380 |
| **Memorystore** | 1GB Redis | $75 |
| **Artifact Registry** | ~10GB storage, pull traffic | $30 |
| **Cloud Storage** | Media (50GB) + Backups (20GB) | $2 |
| **Load Balancer** | Global HTTPS LB | $18 |
| **Networking** | Inter-zone traffic | $15 |
| **其他** | Secret Manager, Compute Engine | $20 |
| **合计** | | **~$760/月** |

#### AWS 成本 (对标)

| 组件 | 配置 | 月度成本 |
|------|------|---------|
| **EKS** | 2 t3.xlarge (On-Demand) | $280 |
| **RDS** | db.t4g.medium, 100GB | $320 |
| **ElastiCache** | cache.t4g.micro, 3 nodes | $85 |
| **ECR** | ~10GB storage | $10 |
| **S3** | Media (50GB) + Backups | $2 |
| **ALB** | Application LB | $20 |
| **Networking** | NAT Gateway, data transfer | $40 |
| **其他** | Secrets Manager | $15 |
| **合计** | | **~$772/月** |

### 结论
- **成本基本相同** ($760 vs $772)
- GKE 稍便宜 (託管 K8s 减少开销)
- 都支持 Spot/Preemptible 进一步降低 20-30%

---

## 决策矩阵

### AWS vs GCP 对比

| 评估维度 | AWS | GCP | 建议 |
|---------|-----|-----|------|
| **成本** | $772/月 | $760/月 | 平手 |
| **学习曲线** | 陡峭 | 较缓 | GCP |
| **Managed K8s** | EKS (复杂) | GKE (简单) | **GCP** |
| **数据库** | RDS (好) | Cloud SQL (好) | 平手 |
| **CI/CD 集成** | OIDC Role | OIDC Pool | **GCP** |
| **团队熟悉度** | ❓ | ✅ (GCP) | **GCP** |
| **现有配置** | ✅ (完成) | ❌ (需重写) | **AWS** |
| **实施时间** | 1-2 天 | 7-12 天 | **AWS** |
| **长期维护** | 复杂 | 简单 | **GCP** |

### 最终建议

#### 快速方案 (推荐首选)
```
使用 AWS (现有配置)
理由:
- 配置已完成
- 2 天内启动
- 降低风险
```

#### 长期方案 (值得迁移)
```
如果满足以下条件，改用 GCP:
1. 团队确实更熟悉 GCP
2. 有 2 周以上的实施时间
3. 希望降低维护复杂度
4. 长期计划使用 GCP

迁移路径:
- Staging 先用 AWS 验证架构
- 后续生产环境迁移 GCP
- 或 hybrid approach (staging GCP, prod AWS)
```

---

## 总结

| 方案 | 时间 | 成本 | 复杂度 | 建议 |
|------|------|------|--------|------|
| AWS (现有) | 2 天 | $772/月 | 高 | ✅ **立即启动** |
| GCP (新写) | 7-12 天 | $760/月 | 低 | ⏱ **未来考虑** |

**建议行动**:
1. **现在**: 使用 AWS 配置部署 staging (验证业务)
2. **后续**: 如需优化，考虑逐步迁移到 GCP

---

**作者**: Claude Code
**版本控制**: 可根据实际情况更新本方案
