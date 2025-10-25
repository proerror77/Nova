# Deep Fixes Quick Reference

Fast reference guide for implementing and using all three completed fixes.

## Fix #6: API Error Handling (Frontend)

### Setup (1 minute)

```typescript
// 1. Add to app root (App.tsx)
import { ErrorNotificationContainer } from '@/components/ErrorNotification';

export function App() {
  return (
    <>
      <ErrorNotificationContainer maxNotifications={5} />
      {/* Rest of app */}
    </>
  );
}

// 2. Use in any API call
import { apiClient } from '@/services/api/client';

const data = await apiClient.get<UserType>('/api/endpoint');
// ✅ Automatic retry on network failure
// ✅ Automatic error notification
// ✅ Automatic logging to localStorage
```

### Common Patterns

```typescript
// ✅ Basic API call
const users = await apiClient.get<User[]>('/api/users');

// ✅ POST with data
const response = await apiClient.post<Response>('/api/posts', {
  content: 'Hello',
  images: []
});

// ✅ With custom retry config
const data = await apiClient.get<T>('/critical-endpoint', {}, {
  maxRetries: 5,      // More retries for critical
  initialDelayMs: 200, // Faster
  maxDelayMs: 5000    // Lower cap
});

// ✅ Upload with progress
const postId = await uploadPhoto(
  file,
  caption,
  (progress) => setProgress(progress)
);
```

### Debugging

```javascript
// View errors in browser console
JSON.parse(localStorage.getItem('nova_api_errors'))
// Shows last 50 errors with full context

// Check current error store state
useErrorStore.getState()
```

**Docs:** `/frontend/ERROR_HANDLING.md`

---

## Fix #7: WebSocket Reconnection (Frontend)

### Setup (1 minute)

```typescript
// 1. Add UI to layout (App.tsx or Layout.tsx)
import { ConnectionStatus, ConnectionBanner } from '@/components/ConnectionStatus';

export function Layout() {
  return (
    <>
      <ConnectionStatus position="top-right" showMetrics={false} />
      <ConnectionBanner />
      {/* Rest of layout */}
    </>
  );
}

// 2. Use connection state in components
import { useConnection } from '@/stores/connectionStore';

function ChatInput() {
  const { isConnected } = useConnection();

  return (
    <input
      disabled={!isConnected}
      placeholder="Type a message..."
    />
  );
}
```

### Common Patterns

```typescript
// ✅ Check if connected
const { isConnected, isReconnecting } = useConnection();

// ✅ Get metrics
const { metrics } = useConnection();
console.log(`${metrics?.queuedMessages} messages queued`);

// ✅ Show reconnecting status
{isReconnecting && <Spinner />}

// ✅ Update message when disconnected
{!isConnected && <p>Messages will send when reconnected</p>}
```

### Troubleshooting

```javascript
// View connection metrics
const client = getWebSocketClient();
console.log(client.getMetrics());

// Monitor state changes (console shows):
// [WebSocket] State: CLOSED → CONNECTING
// [WebSocket] Connected
// [WebSocket] State: CONNECTING → CONNECTED

// Simulate network issues
// DevTools → Network → Offline toggle
```

**Docs:** `/frontend/WEBSOCKET_RECONNECTION.md`

---

## Fix #8: Prometheus Monitoring (Backend)

### Setup (5 minutes)

```bash
# 1. Start monitoring stack
docker-compose -f docker-compose.monitoring.yml up -d

# 2. Access services
# Prometheus: http://localhost:9090
# Grafana: http://localhost:3000 (admin/admin)
# AlertManager: http://localhost:9093

# 3. Configure Slack webhooks (alertmanager.yml)
export SLACK_WEBHOOK_URL="https://hooks.slack.com/..."
export SLACK_WEBHOOK_CRITICAL="https://hooks.slack.com/..."

# 4. Reload AlertManager
curl -X POST http://localhost:9093/-/reload
```

### Common Queries

```promql
# Current WebSocket connections
ws_active_connections

# Message delivery rate
rate(messages_sent_total{status="success"}[5m])

# WebSocket error rate
rate(ws_errors_total[5m]) / rate(ws_messages_sent_total[5m])

# P95 latency
histogram_quantile(0.95, rate(message_api_latency_seconds_bucket[5m]))

# Queue backlog
message_queue_depth{queue_type="pending"}

# Reconnections per minute
rate(ws_reconnections_total[1m])
```

### Critical Alerts (What to Do)

| Alert | Severity | Action | Runbook |
|-------|----------|--------|---------|
| Service Down | CRITICAL | Page on-call | Check service status |
| WebSocket Error > 15% | CRITICAL | Investigate immediately | Check network logs |
| Message Delivery > 10% | CRITICAL | Check message queue | Review database |
| Failed Messages > 500 | CRITICAL | Investigate root cause | Check worker logs |

### Dashboard Setup

```bash
# 1. Open Grafana: http://localhost:3000
# 2. Create data source: Prometheus at http://prometheus:9090
# 3. Create dashboard with panels:
#    - Title: WebSocket Connections
#      Query: ws_active_connections
#    - Title: Message Latency
#      Query: histogram_quantile(0.95, rate(...))
```

**Docs:** `/backend/PROMETHEUS_MONITORING.md`

---

## Integration Checklist

### Before Going to Staging

**Frontend:**
- [ ] ErrorNotificationContainer added to app root
- [ ] ConnectionStatus + ConnectionBanner in layout
- [ ] Test error handling: DevTools → Network → Offline
- [ ] Test reconnection: Block WS in DevTools for 30s

**Backend:**
- [ ] Update prometheus.yml with real service URLs
- [ ] Configure alertmanager.yml with Slack/PagerDuty
- [ ] Start docker-compose.monitoring.yml
- [ ] Verify metrics visible at localhost:9090/metrics

**Operations:**
- [ ] Grafana dashboards created
- [ ] Alert channels configured
- [ ] Runbooks for critical alerts prepared
- [ ] Team trained on alert response

---

## Performance Metrics

### What to Monitor

**WebSocket Health:**
- `ws_active_connections` - Should stay stable
- `ws_reconnections_total` - Should be < 5/hour in production
- `ws_message_latency_seconds` p95 - Should be < 500ms

**Message Delivery:**
- `messages_sent_total` success rate - Should be > 99%
- `message_queue_depth` - Should be 0 in normal operation
- `message_delivery_latency_seconds` - Should be < 1 second

**API Performance:**
- `message_api_latency_seconds` p99 - Should be < 1 second
- `http_request_duration_seconds` - Should be < 2 seconds

---

## Emergency Response

### Service is Unresponsive

```bash
# 1. Check Prometheus
# Is it scraping targets?
# http://localhost:9090/targets

# 2. Check AlertManager
# Are alerts firing?
# http://localhost:9093

# 3. Check logs
docker logs prometheus     # Scraping errors?
docker logs alertmanager   # Routing errors?
docker logs <service>      # Application errors?

# 4. Restart services
docker-compose -f docker-compose.monitoring.yml restart
```

### Message Queue Backing Up

```bash
# 1. View queue depth
# Prometheus: message_queue_depth{queue_type="pending"}

# 2. Check message worker logs
docker logs messaging-service

# 3. Check database
# Is it responding to queries?
# SELECT count(*) FROM messages WHERE status='pending';

# 4. Drain queue manually (if needed)
# Contact engineering for procedure
```

### Alerts Not Firing

```bash
# 1. Verify AlertManager is running
docker ps | grep alertmanager

# 2. Test alert rule
# Prometheus: sum(ws_errors_total) > 0

# 3. Check AlertManager config
cat alertmanager.yml

# 4. Verify webhook URLs
# Slack: curl -X POST $SLACK_WEBHOOK_URL

# 5. View AlertManager logs
docker logs alertmanager
```

---

## Useful Commands

```bash
# Prometheus
curl http://localhost:9090/metrics             # Prometheus metrics
curl http://localhost:9090/-/reload            # Reload config
curl http://localhost:9090/api/v1/query?query=up  # Query metrics

# AlertManager
curl http://localhost:9093/api/v1/alerts       # View active alerts
curl http://localhost:9093/-/reload            # Reload config

# Grafana
curl http://localhost:3000/api/health          # Health check

# Docker Compose
docker-compose -f docker-compose.monitoring.yml logs -f prometheus
docker-compose -f docker-compose.monitoring.yml restart
docker-compose -f docker-compose.monitoring.yml down -v  # Reset all data
```

---

## Documentation Links

**Frontend:**
- Error Handling: `/frontend/ERROR_HANDLING.md`
- WebSocket: `/frontend/WEBSOCKET_RECONNECTION.md`

**Backend:**
- Monitoring: `/backend/PROMETHEUS_MONITORING.md`
- Alerts: `/backend/prometheus.rules.yml`
- Config: `/backend/prometheus.yml`

**Overview:**
- Implementation Summary: `/DEEP_FIXES_IMPLEMENTATION_SUMMARY.md`
- This Guide: `/DEEP_FIXES_QUICK_REFERENCE.md`

---

## Success Indicators

✅ **Error Handling Working:**
- Error notifications appear when network fails
- Messages don't get lost (either retry or queue)
- localStorage shows error history

✅ **WebSocket Working:**
- Connection status always visible
- Auto-reconnection happens within 1-2 minutes
- Messages queue during outage and send after reconnection

✅ **Monitoring Working:**
- Prometheus shows metrics for all services
- Grafana dashboards display real-time data
- Test alerts route to Slack/PagerDuty correctly

---

**Questions?** See the detailed docs linked above or check error logs.
