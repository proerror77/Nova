# Staging Environment Fixes - 2025-11-20

## Summary
- Recovered data-plane availability for analytics/search by aligning Secrets Manager values with actual DB creds and rebuilding ClickHouse on staging.
- Ensured service env wiring matches staging endpoints (Postgres, Elasticsearch, ClickHouse).
- Restarted impacted Deployments to pick up secret changes.

## Actions Performed
1) **Secrets**
   - `nova/staging/nova-db-credentials`: corrected password and added per-service URLs (analytics, search, notification, realtime-chat, trust-safety).
   - `nova/staging/search-service-secret`: fixed `DATABASE_URL` host/port and `ELASTICSEARCH_URL` namespace.
   - `nova/staging/nova-clickhouse-credentials`: pointed host to `clickhouse.nova-staging.svc.cluster.local:8123`, database `analytics`.
2) **Kubernetes**
   - Deployed `clickhouse-statefulset.yaml` (simple 1-replica StatefulSet + ClusterIP).
   - Recreated `nova-ch-data` PVC (old PV deleted/cleaned) and initialized ClickHouse; created database `analytics`.
   - Restarted Deployments: `analytics-service`, `search-service`, `notification-service`, `realtime-chat-service`, `trust-safety-service`, `content-service`.
3) **Config Alignment**
   - search-service env patched to use staging ES/CH URLs (runtime patch + patches file kept in repo).
   - content-service ClickHouse URL switched to `clickhouse.nova-staging.svc.cluster.local:8123`.

## Current State (nova-staging)
- analytics-service: DB pool OK, outbox publisher running.
- search-service: DB/Redis/ES/ClickHouse connected; Kafka topics `message_persisted` / `message_deleted` still missing (warnings).
- clickhouse: ClusterIP `clickhouse.nova-staging.svc.cluster.local:8123`, DB `analytics` present, user `nova` (password in AWS secret).
- realtime-chat-service / trust-safety-service: DB connections healthy after restart.

## Follow-ups
- Create Kafka topics `message_persisted` and `message_deleted` for search indexing.
- If Altinity operator `chi-nova-ch-single-0-0-0` is no longer needed, clean it up to avoid dual ClickHouse endpoints.
- If you need mTLS for search-service in staging, provision grpc certs (`grpc-mtls-shared`, `grpc-ca-cert`) and restart.

## References
- Updated overlays already in repo:
  - `k8s/infrastructure/overlays/staging/clickhouse-statefulset.yaml`
  - `k8s/infrastructure/overlays/staging/nova-clickhouse-credentials.yaml`
  - `k8s/infrastructure/overlays/staging/search-service-env-patch.yaml`
  - `k8s/infrastructure/overlays/staging/content-service-env-patch.yaml`
  - `k8s/infrastructure/overlays/staging/service-db-env-patch.yaml`
