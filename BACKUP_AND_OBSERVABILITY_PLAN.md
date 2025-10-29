# Nova 備份與觀測落地計畫

## 1. PostgreSQL 自動備份排程

- **目標**：每日全量備份 `nova_auth`、`nova_content` 等資料庫至 S3，保留 7 天。
- **腳本**：使用已存在的 `scripts/backup/pg_backup.sh`，調整為可接受 `DATABASE_URL`、`S3_BUCKET`、`RETENTION_DAYS` 參數。
- **Kubernetes CronJob 草稿**
  ```yaml
  apiVersion: batch/v1
  kind: CronJob
  metadata:
    name: nova-postgres-backup
    namespace: nova-prod
  spec:
    schedule: "0 1 * * *"               # 01:00 UTC
    successfulJobsHistoryLimit: 2
    failedJobsHistoryLimit: 2
    jobTemplate:
      spec:
        template:
          spec:
            restartPolicy: OnFailure
            containers:
              - name: pg-backup
                image: ghcr.io/nova/pg-backup:latest
                imagePullPolicy: IfNotPresent
                env:
                  - name: DATABASE_URL
                    valueFrom:
                      secretKeyRef:
                        name: postgres-credentials
                        key: url
                  - name: S3_BUCKET
                    value: s3://nova-backups/prod/postgres
                  - name: RETENTION_DAYS
                    value: "7"
                  - name: AWS_REGION
                    value: us-west-2
                volumeMounts:
                  - name: aws-credentials
                    mountPath: /var/aws
                    readOnly: true
            volumes:
              - name: aws-credentials
                secret:
                  secretName: aws-backup-credentials
  ```
- **待辦**：
  1. 依上方草稿建立 `k8s/base/cronjobs/postgres-backup.yaml`，並在 `k8s/overlays/prod/kustomization.yaml` 中引用。
  2. 為 staging 建立較小保留（3 天）與不同 bucket 路徑。
  3. 於 `scripts/backup/pg_backup.sh` 新增參數解析與日誌輸出（成功/失敗上報 CloudWatch）。

## 2. 觀測與追蹤整合

| 項目                 | 作法概要 | 待辦細節 |
| -------------------- | -------- | -------- |
| **Logs**             | 使用 `tracing` → stdout，透過 Fluent Bit 匯出至 CloudWatch Logs | - 建立 `k8s/base/logging/fluent-bit-daemonset.yaml`<br>- 在 Deployment 加上 `logging=structured` label 方便收集 |
| **Metrics**          | 以 Prometheus 格式暴露 `/metrics`；Grafana 監看 | - 確認所有服務使用 `metrics::register_service_metrics()`<br>- 在 k8s overlays 加上 `ServiceMonitor` (適用於 Prometheus Operator) |
| **Tracing**          | 導入 OpenTelemetry (otlp exporter) 指向 AWS X-Ray 或自建 Jaeger | - 在 `backend/*-service/Cargo.toml` 新增 `opentelemetry`, `tracing-opentelemetry` 依賴<br>- 於 `main.rs` 初始化 OTLP exporter（以 `OTEL_EXPORTER_OTLP_ENDPOINT` 控制） |
| **Alerting**         | 以 CloudWatch Alarm / Prometheus Alertmanager | - 定義 P0 指標：`http_server_errors_total`, `grpc_client_errors_total`, `redis_timeout_total`<br>- 建立 Terraform / CloudFormation 模組或在 `infra/` 內補充 IaC 筆記 |

## 3. 後續行動項目

1. **腳本強化**：`pg_backup.sh` 增加 `--dry-run`、`--log-format json` 參數以方便整合。
2. **機密管理**：使用 AWS Secrets Manager 或 Kubernetes `ExternalSecret` 注入資料庫密碼與 S3 凭證，避免寫死在 CronJob。
3. **驗證流程**：建立 `docs/runbooks/restore_postgres.md`，紀錄從備份還原到臨時資料庫的流程（季度演練）。
4. **觀測驗證**：新增煙霧測試腳本（CI）確保 `/metrics`、 `/health`、`/ready` endpoint 在部署後可用。
5. **追蹤示例**：在 user-service 的 feed handler 補一個 `#[tracing::instrument]` 範例，示範跨服務 span 傳遞，做為之後全面套用的模板。

> 此文件僅規劃落地步驟；實作時請依優先順序將 CronJob、Fluent Bit、OTel exporter 分別提交 PR，避免單一變更過於龐大。
