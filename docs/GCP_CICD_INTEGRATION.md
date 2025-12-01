# GCP CI/CD 集成方案 - GitHub Actions + OIDC

**版本**: 1.0
**日期**: 2025-11-30

---

## 概览

使用 Workload Identity Federation (OIDC) 将 GitHub Actions 与 GCP 集成，无需长期凭证。

```
┌─────────────────────┐
│  GitHub Actions     │
│  (CI/CD Pipeline)   │
└──────────┬──────────┘
           │ OpenID Connect Token
           │
    ┌──────▼─────────────────────────────┐
    │ Workload Identity Federation       │
    │ (Token Exchange)                    │
    └──────┬──────────────────────────────┘
           │ GCP Service Account Access Token
           │
    ┌──────▼──────────────────┐
    │ GCP (Artifact Registry  │
    │ Cloud SQL, Secret Mgr)  │
    └─────────────────────────┘
```

---

## 1. GCP 侧配置 (Terraform)

### 1.1 Workload Identity Pool 和 Provider

```hcl
# 创建 Workload Identity Pool (项目级)
resource "google_iam_workload_identity_pool" "github" {
  display_name            = "GitHub Actions"
  location                = "global"
  workload_identity_pool_id = "github"
  disabled                = false
  description             = "Workload Identity Pool for GitHub Actions CI/CD"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.environment" = "assertion.environment"
  }

  # 限制 Token 颁发器为 GitHub
  attribute_condition = "assertion.aud == 'https://github.com/anthropics'"
}

# 创建 Workload Identity Provider (GitHub 专用)
resource "google_iam_workload_identity_pool_provider" "github" {
  display_name           = "GitHub Provider"
  location               = "global"
  workload_identity_pool_id = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  disabled               = false

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
    "attribute.environment" = "assertion.environment"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}
```

### 1.2 GitHub Actions Service Account

```hcl
resource "google_service_account" "github_actions" {
  account_id   = "github-actions"
  display_name = "GitHub Actions CI/CD"
  description  = "Service account for GitHub Actions to push images and deploy"
}

# 将 Service Account 与 Workload Identity Pool 关联
resource "google_service_account_iam_binding" "github_actions_oidc" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    # 允许所有来自该仓库的 GitHub Actions 运行
    "principalSet://iam.googleapis.com/projects/${data.google_client_config.current.project_number}/locations/global/workloadIdentityPools/github/attribute.repository/proerror/nova"
  ]
}

# 或者更细粒度的控制 (仅 staging 分支)
resource "google_service_account_iam_binding" "github_actions_staging" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/projects/${data.google_client_config.current.project_number}/locations/global/workloadIdentityPools/github/attribute.repository/proerror/nova/ref:refs/heads/main"
  ]
}
```

### 1.3 授予 GitHub Actions 权限

```hcl
# Artifact Registry: 推送镜像
resource "google_project_iam_member" "github_artifact_push" {
  project = data.google_client_config.current.project
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# GKE: 部署应用
resource "google_project_iam_member" "github_gke_admin" {
  project = data.google_client_config.current.project
  role    = "roles/container.developer"  # 允许 kubectl 操作
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Secret Manager: 读取秘钥
resource "google_project_iam_member" "github_secrets_read" {
  project = data.google_client_config.current.project
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}

# Cloud SQL: 管理连接
resource "google_project_iam_member" "github_sql_client" {
  project = data.google_client_config.current.project
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}
```

---

## 2. GitHub Actions 侧配置

### 2.1 设置环境变量

在 GitHub Repository Settings → Secrets and variables → Actions:

```
Secrets:
- GCP_PROJECT_ID: "banded-pad-479802-k9"
- GCP_WORKLOAD_IDENTITY_PROVIDER: "projects/690655954246/locations/global/workloadIdentityPools/github/providers/github-provider"
- GCP_SERVICE_ACCOUNT: "github-actions@banded-pad-479802-k9.iam.gserviceaccount.com"

Variables:
- GCP_REGION: "asia-northeast1"
- GKE_CLUSTER_NAME: "nova-staging-gke"
- ARTIFACT_REGISTRY: "asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova-staging"
```

### 2.2 修改 Workflow: Build & Push

```yaml
name: GCP Build & Push

on:
  push:
    branches:
      - main
    paths:
      - 'backend/**'
      - '.github/workflows/gcp-*.yml'

permissions:
  contents: read
  id-token: write  # 需要 OIDC token

env:
  ARTIFACT_REGISTRY: ${{ secrets.GCP_ARTIFACT_REGISTRY }}
  GKE_CLUSTER: ${{ vars.GKE_CLUSTER_NAME }}
  GCP_REGION: ${{ vars.GCP_REGION }}

jobs:
  build-push:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [identity-service, realtime-chat-service, analytics-service, ...]

    steps:
      # 1. Checkout
      - name: Checkout code
        uses: actions/checkout@v4

      # 2. 获取 GCP 访问 Token (OIDC)
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      # 3. 设置 gcloud CLI
      - name: Set up Cloud SDK
        uses: google-github-actions/setup-gcloud@v2

      # 4. 配置 Docker 认证到 Artifact Registry
      - name: Configure Docker for Artifact Registry
        run: |
          gcloud auth configure-docker ${{ env.GCP_REGION }}-docker.pkg.dev

      # 5. 构建 Docker 镜像
      - name: Build Docker image
        run: |
          docker build \
            -t ${{ env.ARTIFACT_REGISTRY }}/${{ matrix.service }}:${{ github.sha }} \
            -t ${{ env.ARTIFACT_REGISTRY }}/${{ matrix.service }}:latest \
            -f backend/${{ matrix.service }}/Dockerfile \
            backend/

      # 6. 推送到 Artifact Registry
      - name: Push to Artifact Registry
        run: |
          docker push ${{ env.ARTIFACT_REGISTRY }}/${{ matrix.service }}:${{ github.sha }}
          docker push ${{ env.ARTIFACT_REGISTRY }}/${{ matrix.service }}:latest

      # 7. 镜像扫描 (可选)
      - name: Scan image for vulnerabilities
        run: |
          gcloud container images scan ${{ env.ARTIFACT_REGISTRY }}/${{ matrix.service }}:${{ github.sha }}

  # 部署 Job
  deploy:
    needs: build-push
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Get GKE credentials
        run: |
          gcloud container clusters get-credentials ${{ env.GKE_CLUSTER }} \
            --region=${{ env.GCP_REGION }}

      - name: Update Kubernetes deployments
        run: |
          # 使用 kustomize 或 kubectl 更新镜像标签
          kubectl set image deployment/identity-service \
            identity-service=${{ env.ARTIFACT_REGISTRY }}/identity-service:${{ github.sha }} \
            -n nova-staging

          # 等等其他服务...

      - name: Verify rollout
        run: |
          kubectl rollout status deployment/identity-service -n nova-staging --timeout=5m
```

### 2.3 修改 Workflow: 数据库迁移 (可选)

```yaml
name: GCP Database Migration

on:
  push:
    branches:
      - main
    paths:
      - 'backend/migrations/**'

permissions:
  contents: read
  id-token: write

jobs:
  migrate:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Get Cloud SQL connection info
        run: |
          # 获取 Cloud SQL 连接信息 (私有 IP)
          gcloud sql instances describe nova-staging \
            --format='value(ipAddresses[0].ipAddress)' > /tmp/sql_ip.txt

      - name: Run migrations
        run: |
          # 通过 Cloud SQL Proxy 或 Private IP 运行迁移
          # 这需要更复杂的网络配置
          echo "Migration script would run here"
```

---

## 3. 新增 Workflow: 定期备份

```yaml
name: GCP Database Backup

on:
  schedule:
    # 每天 UTC 03:00 执行
    - cron: '0 3 * * *'
  workflow_dispatch:

permissions:
  contents: read
  id-token: write

jobs:
  backup:
    runs-on: ubuntu-latest

    steps:
      - name: Authenticate to Google Cloud
        uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ secrets.GCP_WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ secrets.GCP_SERVICE_ACCOUNT }}

      - name: Trigger Cloud SQL backup
        run: |
          gcloud sql backups create \
            --instance=nova-staging \
            --description="Automated daily backup"
```

---

## 4. 环境变量和秘钥同步

### 4.1 Secret Manager 同步到 K8s

替换之前的 AWS Secrets Manager CronJob:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: secrets-sync
  namespace: nova-staging
spec:
  schedule: "*/30 * * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: k8s-workload-sa
          restartPolicy: OnFailure
          containers:
          - name: sync
            image: google/cloud-sdk:latest
            command: ["sh", "-lc"]
            args:
              - |
                set -euo pipefail

                # 使用 gcloud 从 Secret Manager 读取秘钥
                get_secret() {
                  gcloud secrets versions access latest --secret="$1"
                }

                # 同步数据库凭证
                DB_CREDS=$(get_secret nova-staging-db-credentials)
                kubectl create secret generic nova-db-credentials \
                  --from-literal=connection-string="$DB_CREDS" \
                  --dry-run=client -o yaml | kubectl apply -f -

                # 同步 JWT 密钥
                JWT_KEY=$(get_secret nova-staging-jwt-keys)
                kubectl create secret generic nova-jwt-keys \
                  --from-literal=key="$JWT_KEY" \
                  --dry-run=client -o yaml | kubectl apply -f -

                echo "Secrets synced successfully"
```

### 4.2 Workload Identity 注解

配置 K8s Service Account 使用 GCP Service Account:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: k8s-workload-sa
  namespace: nova-staging
  annotations:
    iam.gke.io/gcp-service-account: nova-k8s-workloads@banded-pad-479802-k9.iam.gserviceaccount.com
```

---

## 5. 验证 OIDC 配置

### 5.1 测试 OIDC Token

```bash
# 在 GitHub Actions 中获取 OIDC token
TOKEN=$(curl -sS "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=https://iam.googleapis.com" \
  -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN")
echo $TOKEN | jq .
```

### 5.2 测试 Service Account 权限

```bash
# 认证
gcloud auth application-default login

# 测试 Artifact Registry 访问
gcloud artifacts repositories list --location=asia-northeast1

# 测试 GKE 访问
gcloud container clusters list --region=asia-northeast1

# 测试 Secret Manager 访问
gcloud secrets list
```

---

## 6. 故障排查

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| "OIDC token not found" | OIDC 未启用 | 确保 workflow 权限有 `id-token: write` |
| "Token not valid" | 仓库不匹配 | 检查 Workload Identity Pool 的 repository 属性 |
| "Permission denied" | Service Account 无权限 | 检查 IAM 绑定是否正确 |
| "gcloud not found" | SDK 未安装 | 使用 `google-github-actions/setup-gcloud@v2` |

---

## 7. 检查清单

- [ ] Workload Identity Pool 已创建
- [ ] GitHub Provider 已配置
- [ ] Service Account 已创建并绑定
- [ ] IAM 权限已设置 (Artifact Registry, GKE, Secrets)
- [ ] GitHub Secrets 已配置
- [ ] GitHub Environments 已配置 (如需)
- [ ] Workflow 已修改并测试
- [ ] 手动运行一次 workflow 验证端到端流程

---

## 8. 参考资源

- [Google Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation)
- [Google GitHub Actions Auth](https://github.com/google-github-actions/auth)
- [GKE Workload Identity](https://cloud.google.com/kubernetes-engine/docs/how-to/workload-identity)
