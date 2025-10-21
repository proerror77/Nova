# Staging Deployment Checklist

## Overview

This checklist ensures Nova Streaming platform components are properly configured, tested, and ready for deployment to the staging environment. Each section must be completed and verified before proceeding.

## Pre-Deployment Phase

### 1. Code Readiness

- [ ] **All code committed to main branch**
  - [ ] All changes merged via pull requests
  - [ ] All CI/CD checks passing
  - [ ] No uncommitted changes in working directory
  ```bash
  git status
  git log --oneline -5
  ```

- [ ] **Version bumped appropriately**
  - [ ] Backend version updated in `Cargo.toml`
  - [ ] iOS app version updated in `Info.plist`
  - [ ] Tag created: `git tag -a v0.x.x -m "Release v0.x.x"`
  ```bash
  git tag v0.x.x
  git push origin v0.x.x
  ```

- [ ] **Dependencies up-to-date**
  - [ ] Run `cargo update` and test
  - [ ] npm/Swift dependencies reviewed
  - [ ] Security vulnerabilities checked
  ```bash
  cargo audit
  cargo update
  npm audit
  ```

- [ ] **Code quality checks passed**
  - [ ] No compiler warnings: `cargo build --all 2>&1 | grep warning`
  - [ ] Clippy checks: `cargo clippy --all -- -D warnings`
  - [ ] Formatting: `cargo fmt --all -- --check`
  - [ ] Tests: `cargo test --all`

### 2. Documentation Review

- [ ] **API Documentation updated**
  - [ ] OpenAPI spec reflects current endpoints
  - [ ] Request/response schemas current
  - [ ] Error codes documented
  ```bash
  grep -n "version:" docs/openapi-streaming.yaml
  ```

- [ ] **WebSocket protocol documented**
  - [ ] All message types described
  - [ ] Client implementation examples current
  - [ ] Error handling documented

- [ ] **Configuration documented**
  - [ ] All environment variables listed
  - [ ] Default values specified
  - [ ] Required vs optional marked

- [ ] **Deployment guides current**
  - [ ] This checklist reviewed for accuracy
  - [ ] Troubleshooting guide up-to-date
  - [ ] Known issues documented

### 3. Security Review

- [ ] **Authentication/Authorization**
  - [ ] JWT secret rotation completed
  - [ ] Token expiry set to 1 hour
  - [ ] CORS headers configured
  - [ ] Rate limiting enabled
  ```bash
  grep -r "rate_limit" backend/
  grep -r "CORS" backend/
  ```

- [ ] **Data Protection**
  - [ ] Database passwords rotated
  - [ ] Redis auth enabled
  - [ ] SSL certificates generated
  - [ ] Encryption at rest configured

- [ ] **API Security**
  - [ ] Input validation on all endpoints
  - [ ] SQL injection prevention verified
  - [ ] XSS protection implemented
  - [ ] CSRF tokens where needed

- [ ] **Infrastructure Security**
  - [ ] Firewall rules configured
  - [ ] SSH keys rotated
  - [ ] Secret management in place
  - [ ] Audit logging enabled

### 4. Database Preparation

- [ ] **Migrations reviewed**
  - [ ] All pending migrations listed
  - [ ] Migration rollback tested
  - [ ] Data backup procedure documented
  ```bash
  sqlx migrate info
  sqlx migrate run --dry-run
  ```

- [ ] **Database state verified**
  - [ ] Indexes created for performance
  - [ ] Constraints properly defined
  - [ ] Partitioning configured (if needed)
  - [ ] Statistics updated: `ANALYZE;`

- [ ] **Backup configured**
  - [ ] Automated daily backups enabled
  - [ ] Backup retention policy set (30 days minimum)
  - [ ] Restore procedure tested
  - [ ] Backup storage encrypted

### 5. Infrastructure Preparation

- [ ] **Kubernetes manifests validated**
  - [ ] Deployments have resource requests/limits
  - [ ] Health checks configured (liveness + readiness)
  - [ ] Rolling update strategy set
  - [ ] Pod security policies applied
  ```bash
  kubectl apply --dry-run=client -f k8s/
  ```

- [ ] **Docker images built and tested**
  - [ ] Image builds successfully
  - [ ] Image scanned for vulnerabilities
  - [ ] Image tagged with version
  - [ ] Image pushed to registry
  ```bash
  docker build -t nova/user-service:v0.x.x .
  docker scan nova/user-service:v0.x.x
  docker push nova/user-service:v0.x.x
  ```

- [ ] **Network configuration**
  - [ ] DNS records prepared
  - [ ] Load balancer configured
  - [ ] TLS certificates ready
  - [ ] CDN cache rules configured

- [ ] **Monitoring infrastructure**
  - [ ] Prometheus scrape targets configured
  - [ ] Grafana dashboards imported
  - [ ] Alert rules deployed
  - [ ] Log aggregation configured

---

## Staging Environment Setup

### 6. Service Deployment

- [ ] **Deploy user-service**
  ```bash
  kubectl apply -f k8s/staging/user-service-deployment.yaml
  kubectl rollout status deployment/user-service-staging
  kubectl get pods -l app=user-service-staging
  ```

- [ ] **Deploy PostgreSQL**
  ```bash
  kubectl apply -f k8s/staging/postgres-deployment.yaml
  kubectl exec -it <postgres-pod> -- psql -U postgres -c "SELECT 1;"
  ```

- [ ] **Deploy Redis**
  ```bash
  kubectl apply -f k8s/staging/redis-deployment.yaml
  redis-cli -h <redis-host> ping
  ```

- [ ] **Deploy Kafka**
  ```bash
  kubectl apply -f k8s/staging/kafka-deployment.yaml
  kubectl exec -it <kafka-pod> -- kafka-broker-api-versions.sh --bootstrap-server localhost:9092
  ```

- [ ] **Deploy ClickHouse**
  ```bash
  kubectl apply -f k8s/staging/clickhouse-deployment.yaml
  curl http://<clickhouse-host>:8123/?query=SELECT%201
  ```

- [ ] **Deploy Nginx-RTMP**
  ```bash
  kubectl apply -f k8s/staging/nginx-rtmp-deployment.yaml
  curl http://<nginx-host>:1935/stat
  ```

### 7. Service Verification

- [ ] **Service connectivity**
  - [ ] User service accessible: `curl https://staging-api.nova-social.io/health`
  - [ ] Database accessible: `psql -h staging-db.nova-social.io -U nova_user -d nova_streaming -c "SELECT 1;"`
  - [ ] Redis accessible: `redis-cli -h staging-redis.nova-social.io ping`
  - [ ] RTMP server listening: `telnet staging-rtmp.nova-social.io 1935`

- [ ] **API endpoints responsive**
  - [ ] `GET /api/v1/streams/active` returns 200
  - [ ] `POST /api/v1/streams` returns 400 (missing fields)
  - [ ] `GET /metrics` returns Prometheus format
  - [ ] WebSocket `/api/v1/streams/{id}/ws` upgrades connection

- [ ] **Authentication working**
  - [ ] Valid JWT token accepted
  - [ ] Invalid token rejected with 401
  - [ ] Expired token rejected with 401
  - [ ] Missing token rejected with 401

- [ ] **Database connectivity**
  - [ ] Tables exist: `SELECT table_name FROM information_schema.tables;`
  - [ ] Migrations applied: `SELECT * FROM _sqlx_migrations;`
  - [ ] Sample data available for testing

### 8. Monitoring Setup

- [ ] **Prometheus metrics available**
  ```bash
  curl https://staging-metrics.nova-social.io/api/v1/query?query=nova_streaming_active_streams
  ```

- [ ] **Grafana dashboards deployed**
  - [ ] Login: `https://staging-grafana.nova-social.io`
  - [ ] Streaming dashboard visible
  - [ ] Dashboard showing real metrics
  - [ ] All panels have data

- [ ] **Alerting rules loaded**
  ```bash
  kubectl get prometheusrules -n monitoring
  kubectl logs -n monitoring prometheus-0 | grep "alert"
  ```

- [ ] **Log aggregation working**
  - [ ] Logs appearing in ELK/CloudWatch
  - [ ] Structured logging format correct
  - [ ] Error logs indexed
  - [ ] Search queries working

---

## Functional Testing

### 9. API Testing

- [ ] **Stream creation workflow**
  ```bash
  # Create stream
  STREAM_ID=$(curl -s -X POST "https://staging-api.nova-social.io/api/v1/streams" \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"title": "Test", "description": "Testing"}' | jq -r '.id')

  # Retrieve stream
  curl "https://staging-api.nova-social.io/api/v1/streams/$STREAM_ID" \
    -H "Authorization: Bearer $JWT_TOKEN"

  # List active streams
  curl "https://staging-api.nova-social.io/api/v1/streams/active" \
    -H "Authorization: Bearer $JWT_TOKEN"

  # Delete stream
  curl -X DELETE "https://staging-api.nova-social.io/api/v1/streams/$STREAM_ID" \
    -H "Authorization: Bearer $JWT_TOKEN"
  ```

- [ ] **RTMP broadcasting**
  - [ ] FFmpeg successfully connects to RTMP server
  - [ ] Stream created automatically upon RTMP connection
  - [ ] Stream ends when FFmpeg disconnects
  - [ ] RTMP errors logged appropriately

- [ ] **WebSocket connectivity**
  - [ ] Connection established: `connection_established` message received
  - [ ] Viewer count updates received
  - [ ] Quality changes propagated
  - [ ] Stream lifecycle events received
  - [ ] Ping/pong keepalive working

- [ ] **Error handling**
  - [ ] Invalid stream ID returns 404
  - [ ] Unauthorized requests return 401
  - [ ] Malformed JSON returns 400
  - [ ] Rate limiting returns 429

### 10. Performance Testing

- [ ] **Load testing under 100 concurrent viewers**
  ```bash
  # Create 10 simultaneous WebSocket connections
  for i in {1..10}; do
    websocat "wss://staging-api.nova-social.io/api/v1/streams/$STREAM_ID/ws?token=$JWT_TOKEN" &
  done
  ```

- [ ] **Throughput verification**
  - [ ] Metrics endpoint responds < 100ms
  - [ ] Stream list endpoint responds < 500ms
  - [ ] WebSocket message latency < 100ms

- [ ] **Resource utilization**
  - [ ] CPU usage < 60%
  - [ ] Memory usage < 70%
  - [ ] Disk I/O < 50%
  - [ ] Network bandwidth utilized efficiently

- [ ] **Concurrent stream handling**
  - [ ] 5 simultaneous RTMP streams: functional
  - [ ] 50 viewers per stream: stable
  - [ ] Total 250 concurrent viewers: acceptable performance

### 11. iOS App Testing

- [ ] **Build succeeds on staging backend**
  ```bash
  cd ios/NovaSocialApp
  xcodebuild -scheme NovaSocialApp -configuration Release -derivedDataPath build
  ```

- [ ] **App connects to staging API**
  - [ ] Login successful
  - [ ] Stream list loads
  - [ ] Stream creation works
  - [ ] WebSocket connection established

- [ ] **Video playback**
  - [ ] HLS stream plays smoothly
  - [ ] Quality adaptation works
  - [ ] Buffering handled gracefully
  - [ ] No crashes during playback

### 12. Client Example Testing

- [ ] **Python broadcaster works**
  ```bash
  python examples/python-broadcaster-client.py \
    --token "$JWT_TOKEN" \
    --generate-test-video \
    --title "Staging Test"
  ```

- [ ] **JavaScript viewer works**
  ```bash
  node examples/javascript-viewer-client.js \
    --stream-id "$STREAM_ID" \
    --token "$JWT_TOKEN"
  ```

- [ ] **cURL testing guide accurate**
  - [ ] All example endpoints work
  - [ ] Response formats match documentation
  - [ ] Error cases return expected codes

---

## Integration Testing

### 13. End-to-End Workflows

- [ ] **Complete streaming session**
  1. User creates stream
  2. RTMP broadcaster connects
  3. Stream transitions to "active"
  4. Viewers connect via WebSocket
  5. Metrics recorded correctly
  6. Broadcaster disconnects
  7. Stream transitions to "ended"
  8. WebSocket connections closed
  9. Metrics show correct values

- [ ] **Multiple concurrent streams**
  1. Create 3 simultaneous streams
  2. Start RTMP broadcasts for each
  3. Connect 20 viewers to each stream
  4. Verify independent state management
  5. End streams in different order
  6. Verify no cross-contamination

- [ ] **Error recovery scenarios**
  1. RTMP broadcast interruption
  2. Database connection loss
  3. WebSocket client disconnect
  4. High network latency
  5. Service restart during active stream

### 14. Data Consistency

- [ ] **Viewer count accuracy**
  - [ ] Matches WebSocket connections
  - [ ] Matches database records
  - [ ] Accurate after reconnection

- [ ] **Stream metadata**
  - [ ] Title/description preserved
  - [ ] Created/started/ended timestamps correct
  - [ ] Regional information accurate

- [ ] **Metrics consistency**
  - [ ] Prometheus metrics match database
  - [ ] ClickHouse records match real events
  - [ ] Time series data continuous

---

## Stability Testing

### 15. Soak Testing

- [ ] **Run for 4+ hours with continuous load**
  - [ ] Monitor memory for leaks
  - [ ] Check for increasing latency
  - [ ] Verify no database connection issues
  - [ ] Confirm metrics still accurate

- [ ] **Memory usage stable**
  - [ ] Baseline: 256 MB at startup
  - [ ] No growth after 100 connections
  - [ ] Proper cleanup after disconnection

- [ ] **Database stability**
  - [ ] Connection pool not exhausted
  - [ ] Query performance consistent
  - [ ] No lock contention

### 16. Failover Testing

- [ ] **Database failover**
  - [ ] Primary database failure handled
  - [ ] Automatic failover to replica
  - [ ] Service continues functioning
  - [ ] Data consistency verified

- [ ] **Cache failover**
  - [ ] Redis failure handled gracefully
  - [ ] Application functions without cache
  - [ ] Cache rebuilt upon recovery

- [ ] **Service restart**
  - [ ] Service restarts without data loss
  - [ ] Existing connections handled
  - [ ] Metrics preserved

---

## Security Validation

### 17. Security Testing

- [ ] **Authentication bypass attempts fail**
  - [ ] No endpoint accessible without token
  - [ ] Token tampering detected
  - [ ] Expired tokens rejected

- [ ] **Input validation**
  - [ ] SQL injection attempts blocked
  - [ ] XSS payloads sanitized
  - [ ] Oversized inputs rejected
  - [ ] Invalid Unicode handled

- [ ] **Rate limiting effective**
  - [ ] IP-based limiting works
  - [ ] User-based limiting works
  - [ ] Bypass attempts failed

- [ ] **Data encryption**
  - [ ] HTTPS enforced
  - [ ] TLS version >= 1.2
  - [ ] Weak ciphers disabled
  - [ ] Certificates valid

### 18. Access Control

- [ ] **User isolation**
  - [ ] Cannot access other user's streams
  - [ ] Cannot modify other user's data
  - [ ] Cannot view other user's metrics

- [ ] **Admin capabilities**
  - [ ] Admin can view all streams
  - [ ] Admin can force-end streams
  - [ ] Admin can view system metrics

---

## Rollback Preparation

### 19. Rollback Procedures

- [ ] **Database rollback tested**
  ```bash
  # Verify rollback procedure
  sqlx migrate revert --all
  sqlx migrate run
  ```

- [ ] **Service rollback tested**
  - [ ] Previous version image available
  - [ ] Helm rollback works: `helm rollback nova-streaming`
  - [ ] Service restarts cleanly

- [ ] **Rollback procedure documented**
  - [ ] Step-by-step instructions written
  - [ ] Estimated rollback time: < 10 minutes
  - [ ] Data recovery procedure clear

### 20. Communication Plan

- [ ] **Stakeholders notified**
  - [ ] Team aware of staging deployment
  - [ ] Stakeholders know testing schedule
  - [ ] Escalation contacts listed

- [ ] **Incident response ready**
  - [ ] On-call engineer assigned
  - [ ] Incident communication template prepared
  - [ ] War room established

---

## Final Sign-Off

### 21. Pre-Production Sign-Off

- [ ] **Technical lead approval**
  - [ ] Name: _______________
  - [ ] Date: _______________
  - [ ] Signature: _______________

- [ ] **Product owner approval**
  - [ ] Name: _______________
  - [ ] Date: _______________
  - [ ] Signature: _______________

- [ ] **Security team approval**
  - [ ] Name: _______________
  - [ ] Date: _______________
  - [ ] Signature: _______________

### 22. Known Issues

Document any known issues before proceeding to production:

| Issue | Workaround | Severity | Target Fix |
|-------|-----------|----------|-----------|
| | | | |
| | | | |
| | | | |

### 23. Deployment Readiness

- [ ] **All checklist items completed**: Yes / No
- [ ] **All tests passing**: Yes / No
- [ ] **All security reviews approved**: Yes / No
- [ ] **Rollback procedure tested**: Yes / No
- [ ] **Team trained and ready**: Yes / No

**Approval Date**: _______________

**Approved By**: _______________

---

## Post-Deployment Verification

### 24. Production Monitoring (First 24 hours)

- [ ] **Error rates normal**
  - [ ] Error rate < 0.1%
  - [ ] No new error types
  - [ ] User-reported issues: 0

- [ ] **Performance metrics**
  - [ ] API response time p95 < 200ms
  - [ ] WebSocket latency < 100ms
  - [ ] WebSocket connection success rate > 99%

- [ ] **Resource utilization**
  - [ ] CPU usage < 50%
  - [ ] Memory usage < 60%
  - [ ] Disk I/O healthy

- [ ] **Business metrics**
  - [ ] Active streams increasing
  - [ ] Viewer connections stable
  - [ ] Stream completion rate > 98%

### 25. Incident Response

If issues detected:

1. **Assess severity**: Critical / High / Medium / Low
2. **Gather logs**: `kubectl logs -f deployment/user-service-staging`
3. **Assess rollback feasibility**: Rollback / Fix forward
4. **Execute decision**: Follow procedure
5. **Document incident**: Post-mortem within 24 hours

---

## References

- Deployment Guide: `docs/production-deployment-guide.md`
- Troubleshooting: `docs/troubleshooting-runbook.md`
- OpenAPI Spec: `docs/openapi-streaming.yaml`
- WebSocket Protocol: `docs/websocket-protocol.md`
