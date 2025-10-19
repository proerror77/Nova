# Operational Runbook: Phase 3 Feed Ranking System

**Version**: 1.0  
**Last Updated**: 2025-10-18  
**On-Call Team**: Feed Ranking SRE

---

## Normal Operations

### Daily Health Checks (09:00 UTC)

**Metrics to Review**:
- [ ] Feed P95 latency <150ms (cache) / <800ms (CH)
- [ ] Cache hit rate ≥80%
- [ ] CDC lag <10s
- [ ] Events consumer lag <5s
- [ ] Dedup rate ≥95%
- [ ] Circuit breaker state = CLOSED

**Commands**:
```bash
# Check Prometheus metrics
curl -s "http://prometheus:9090/api/v1/query?query=feed_latency_seconds{quantile='0.95'}"

# Check ClickHouse health
clickhouse-client --query "SELECT count() FROM events WHERE event_time > now() - INTERVAL 1 HOUR"

# Check Kafka consumer lag
kafka-consumer-groups --bootstrap-server kafka:9092 --describe --group nova-events-consumer-v1
```

---

## Incident Response

### ALERT: Feed Latency Spiking (P95 >500ms)

**Severity**: P1 (Critical)  
**SLO Impact**: Violates 800ms SLO

**Immediate Actions**:
1. Check circuit breaker state:
   ```bash
   curl http://api:8080/metrics | grep feed_circuit_breaker_state
   ```
2. If OPEN → Verify PostgreSQL fallback working
3. If CLOSED → Check ClickHouse query log:
   ```sql
   SELECT
       query,
       query_duration_ms,
       read_rows
   FROM system.query_log
   WHERE event_time > now() - INTERVAL 5 MINUTE
   ORDER BY query_duration_ms DESC
   LIMIT 10;
   ```

**Root Cause Analysis**:
- ClickHouse slow queries → Add indexes, optimize MV refresh
- High concurrency → Scale ClickHouse replicas
- Network latency → Check inter-AZ latency

**Escalation**: Page on-call if >15 min

---

### ALERT: Users Reporting Duplicate Posts

**Severity**: P2 (High)

**Diagnosis**:
```bash
# Check dedup rate metric
curl http://api:8080/metrics | grep events_deduped_total

# Manual dedup validation
clickhouse-client --query "
SELECT event_id, count(*)
FROM events
WHERE event_time > now() - INTERVAL 1 HOUR
GROUP BY event_id
HAVING count() > 1
LIMIT 10;
"
```

**Fix**:
- If Redis down → Restart Redis, verify dedup keys
- If consumer bug → Rollback Events consumer

---

### ALERT: Events Not Reaching ClickHouse

**Severity**: P1 (Critical)  
**SLO Impact**: Event-to-visible latency >5s

**Diagnosis**:
```bash
# Check Events consumer lag
kafka-consumer-groups --describe --group nova-events-consumer-v1

# Check ClickHouse insert errors
clickhouse-client --query "
SELECT count()
FROM system.errors
WHERE event_time > now() - INTERVAL 10 MINUTE;
"
```

**Fix**:
1. Restart Events consumer:
   ```bash
   kubectl rollout restart deployment/events-consumer
   ```
2. Verify CDC sync:
   ```sql
   SELECT count(*) FROM posts_cdc WHERE _version > (SELECT max(_version) - 1000 FROM posts_cdc);
   ```

---

## Scaling Procedures

### Increase Kafka Partitions (Events Topic)

**When**: Events consumer lag >30s consistently

**Steps**:
```bash
# Add 6 partitions (current: 12 → new: 18)
kafka-topics --alter --topic events --partitions 18 --bootstrap-server kafka:9092

# Scale Events consumer deployment
kubectl scale deployment/events-consumer --replicas=6

# Verify rebalance
kafka-consumer-groups --describe --group nova-events-consumer-v1
```

---

### Add ClickHouse Replica

**When**: ClickHouse CPU >80% sustained

**Steps**:
1. Deploy new ClickHouse node (identical config)
2. Create replication:
   ```sql
   CREATE TABLE events_replica ON CLUSTER nova_cluster
   AS events ENGINE = ReplicatedMergeTree('/clickhouse/tables/{shard}/events', '{replica}');
   ```
3. Update DNS for load balancing

---

## References
- [Troubleshooting Guide](troubleshooting.md)
- [Deployment Playbook](../deployment/phase3-deployment.md)
