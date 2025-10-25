# WebSocket Auto-Reconnection System

## Overview

Comprehensive WebSocket client with transparent auto-reconnection, heartbeat monitoring, and message queueing for reliable real-time messaging even during temporary network outages.

**Key Features:**
- **Auto-reconnection** with exponential backoff (10 retries, ~30 minutes total)
- **Heartbeat mechanism** (ping/pong every 30 seconds)
- **Message queuing** for offline support (up to 100 messages)
- **Connection state tracking** (6-state machine)
- **Metrics collection** (reconnects, duration, queued messages)
- **Transparent operation** (no user code changes required)

## Architecture

### Connection State Machine

```
┌──────────┐
│  CLOSED  │
└────┬─────┘
     │ connect()
     ↓
┌──────────────┐
│  CONNECTING  │
└────┬─────────┘
     │ onopen
     ↓
┌──────────────┐     network error
│  CONNECTED   │◄──────────────┐
└────┬─────────┘                │
     │                     onclose/onerror
     │                          │
     └──────────────────┐───────┤
                        ↓       │
                  ┌────────────┐│
                  │RECONNECTING││
                  └────┬───────┘│
                       │        │
                  max retries   │
                       │        │
                       ↓        │
                  ┌────────┐    │
                  │  ERROR │────┘
                  └────┬───┘
                       │
                  disconnect()
                       ↓
                  ┌────────┐
                  │ CLOSED │
                  └────────┘
```

### State Definitions

```typescript
enum ConnectionState {
  // Initial state or after disconnect()
  CLOSED = 'CLOSED',

  // Attempting initial connection
  CONNECTING = 'CONNECTING',

  // Connected and heartbeat active
  CONNECTED = 'CONNECTED',

  // Connection lost, not retrying yet
  DISCONNECTED = 'DISCONNECTED',

  // Attempting to reconnect with backoff
  RECONNECTING = 'RECONNECTING',

  // Critical error occurred
  ERROR = 'ERROR',
}
```

## Core Components

### 1. EnhancedWebSocketClient

Located: `/frontend/src/services/websocket/EnhancedWebSocketClient.ts`

Main class handling connection lifecycle and message transport.

#### Public API

```typescript
class EnhancedWebSocketClient {
  // Lifecycle
  connect(): void                           // Initiate connection
  disconnect(): void                        // Clean shutdown

  // Messaging
  send(type: string, payload?: any): void  // Send message (queues if disconnected)
  sendTyping(conversationId, userId): void // Send typing indicator

  // Status
  getState(): ConnectionState               // Get current connection state
  getMetrics(): ConnectionMetrics           // Get connection metrics
}
```

#### Connection Metrics

```typescript
interface ConnectionMetrics {
  state: ConnectionState;
  connected: boolean;
  reconnects: number;              // Total successful reconnections
  queuedMessages: number;          // Messages waiting to be sent
  connectionDurationMs: number;    // Time since current connection started
  url: string;
}
```

#### Handlers

```typescript
interface WsHandlers {
  onMessage?: (payload: any) => void;                    // Regular message received
  onTyping?: (conversationId: string, userId: string) => void;  // Typing indicator
  onOpen?: () => void;                                   // Connection established
  onClose?: () => void;                                  // Connection closed
  onError?: (err: any) => void;                         // Error occurred
  onStateChange?: (state: ConnectionState) => void;     // State machine transition
}
```

### 2. Message Queue

Transient queue for messages sent while disconnected. Automatically drained when connection restored.

**Behavior:**
- Maximum 100 messages per queue
- Oldest messages discarded first if limit exceeded
- Cleared on disconnect or explicit `clear()`
- Attempts counter tracks resend attempts

**Important:** Queue is in-memory only. Messages are lost on page reload or browser crash.

For persistent offline message storage, use the separate offline queue system.

### 3. Heartbeat Mechanism

Detects stale connections that appear open but have stopped receiving data.

**Configuration:**
```typescript
const HEARTBEAT_INTERVAL_MS = 30000;  // Send ping every 30 seconds
const HEARTBEAT_TIMEOUT_MS = 10000;   // Expect pong within 10 seconds
```

**Flow:**
1. Every 30 seconds, client sends `{ type: 'ping' }`
2. Sets 10-second timeout waiting for pong response
3. Server should respond with `{ type: 'pong' }`
4. If pong not received within 10 seconds, connection is closed
5. Reconnection logic triggered automatically

**Server Requirements:**
Server must echo pong messages:
```rust
if data.type == "ping" {
    ws.send(json!({"type": "pong"})).ok();
}
```

### 4. Exponential Backoff Reconnection

Automatically retries connection with increasing delays to avoid thundering herd.

**Configuration:**
```typescript
interface ReconnectConfig {
  maxRetries: number = 10;           // Try up to 10 times
  initialDelayMs: number = 1000;     // Start with 1 second
  maxDelayMs: number = 60000;        // Cap at 1 minute
  backoffMultiplier: number = 1.5;   // Exponential growth
  backoffJitter: boolean = true;     // Add randomness
}
```

**Delay Sequence (with jitter):**
```
Attempt 1: 1000ms    × (0.5-1.0) = 500-1000ms
Attempt 2: 1500ms    × (0.5-1.0) = 750-1500ms
Attempt 3: 2250ms    × (0.5-1.0) = 1125-2250ms
Attempt 4: 3375ms    × (0.5-1.0) = 1687-3375ms
Attempt 5: 5062ms    × (0.5-1.0) = 2531-5062ms
Attempt 6: 7593ms    × (0.5-1.0) = 3796-7593ms
Attempt 7: 11390ms   × (0.5-1.0) = 5695-11390ms
Attempt 8: 17085ms   × (0.5-1.0) = 8542-17085ms
Attempt 9: 25627ms   × (0.5-1.0) = 12813-25627ms
Attempt 10: 38440ms  × (0.5-1.0) = 19220-38440ms

Total wait time: ~2-3 minutes across all attempts
```

**Why Jitter?**
Without jitter, all clients reconnect simultaneously after the same delay, causing "thundering herd" - a spike in server load. Jitter spreads reconnections across time.

## Integration with Messaging System

### How It Works

1. **Initialization** (in messagingStore):
```typescript
connectWs: (conversationId: string, userId: string) => {
  const client = createWebSocketClient(
    `${get().wsBase}/ws?conversation_id=${conversationId}&user_id=${userId}`,
    {
      onMessage: (payload) => { /* handle message */ },
      onTyping: (convId, user) => { /* handle typing */ },
      onOpen: () => { /* update connection store */ },
      onClose: () => { /* update connection store */ },
      onError: (error) => { /* log error */ },
      onStateChange: (state) => { /* sync to connection store */ },
    },
    {
      maxRetries: 10,
      initialDelayMs: 1000,
      maxDelayMs: 30000,
      backoffMultiplier: 1.5,
      backoffJitter: true,
    }
  );
  client.connect();
}
```

2. **Sending Messages** (in messagingStore):
```typescript
sendMessage: async (conversationId, userId, plaintext) => {
  // Send via REST API for persistence
  const res = await fetch(`${base}/conversations/${conversationId}/messages`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sender_id: userId, plaintext, ... }),
  });

  // Message received via REST, then broadcast via WebSocket
  // Client doesn't send directly via WebSocket
}
```

3. **Receiving Messages** (automatic via onMessage handler):
```typescript
onMessage: (payload) => {
  set((s) => {
    const curr = s.messages[conversationId] ?? [];
    // De-duplicate by id or sequence_number
    if (curr.some((x) => x.id === m.id || x.sequence_number === m.sequence_number)) {
      return {} as any;  // Already have this message
    }
    // Add new message and sort by sequence
    const next = [...curr, m].sort((a, b) => a.sequence_number - b.sequence_number);
    return { messages: { ...s.messages, [conversationId]: next } };
  });
}
```

4. **State Tracking** (automatic via onStateChange):
```typescript
onStateChange: (state: ConnectionState) => {
  useConnectionStore.getState().updateState(state);
  // UI components automatically react to state changes
}
```

### Message Flow During Outage

**Normal Scenario:**
```
User types message
  ↓
Sends via REST API
  ↓
Server persists message
  ↓
Server broadcasts via WebSocket
  ↓
Client receives via onMessage handler
  ↓
Message rendered in UI
```

**Network Outage Scenario:**
```
Network goes down
  ↓
REST API call fails → error store
  ↓
WebSocket disconnects → connection state = DISCONNECTED
  ↓
Auto-reconnect starts (exponential backoff)
  ↓
Connection re-established → connection state = CONNECTED
  ↓
Heartbeat resumes
  ↓
User can send messages again
  ↓
REST API call succeeds
  ↓
Server broadcasts to client
  ↓
Message rendered
```

**Note:** Messages are not queued by WebSocket client during outage. Use the separate offline queue (OfflineQueue) for persistent offline-first behavior.

## Connection Status UI

### Components

Located: `/frontend/src/components/ConnectionStatus.tsx`

#### ConnectionStatus (Full Widget)

Displays detailed connection status with optional metrics.

**Usage:**
```typescript
<ConnectionStatus
  visible={true}
  position="top-right"      // top-left, top-right, bottom-left, bottom-right
  showMetrics={false}       // Show detailed metrics
  compact={false}           // Icon-only mode with tooltip
  className="custom-class"
/>
```

**Display:**
- Connection emoji (🟢/🟡/🔴/⚠️/⬜)
- Current status text
- Badge with queued message count (if > 0)
- Animated reconnecting dots (if reconnecting)
- Optional metrics (reconnects, queued, duration)

#### ConnectionIndicator (Minimal)

Tiny emoji indicator for header/navbar.

**Usage:**
```typescript
<ConnectionIndicator className="navbar-indicator" />
```

**Display:**
- Single emoji showing connection state
- Tooltip on hover with full status text

#### ConnectionBanner (Disconnected State)

Full-width banner shown only when disconnected.

**Usage:**
```typescript
<ConnectionBanner />
```

**Display:**
- Shows only when disconnected
- Different message for "reconnecting" vs "disconnected"
- Informs user messages will sync when reconnected
- Appears at top of page with amber background

### Integration into App

Add to your main App layout:

```typescript
import { ConnectionStatus, ConnectionBanner } from '@/components/ConnectionStatus';

export function App() {
  return (
    <div>
      <ConnectionStatus position="top-right" showMetrics={false} />
      <ConnectionBanner />
      {/* Rest of app */}
    </div>
  );
}
```

## Connection Store

Located: `/frontend/src/stores/connectionStore.ts`

Zustand store for connection state management.

### Store State

```typescript
interface ConnectionStore {
  // Current state
  state: ConnectionState;
  metrics: ConnectionMetrics | null;
  lastError: Error | null;
  isConnected: boolean;

  // Actions
  updateState(state: ConnectionState): void;
  updateMetrics(metrics: ConnectionMetrics): void;
  setError(error: Error): void;
  clearError(): void;

  // Helpers
  getConnectionStatus(): string;    // Human-readable status
  isReconnecting(): boolean;
  hasQueuedMessages(): boolean;
}
```

### Using in Components

```typescript
import { useConnection } from '@/stores/connectionStore';

function MyComponent() {
  const {
    state,           // Current ConnectionState
    isConnected,     // Boolean
    metrics,         // Connection metrics
    status,          // Human-readable "Connected (45s)"
    hasQueuedMessages,
    isReconnecting,
  } = useConnection();

  return (
    <div>
      {isConnected ? (
        <span>✅ Connected</span>
      ) : (
        <span>⚠️ Disconnected</span>
      )}

      {isReconnecting && <span>Reconnecting...</span>}

      {hasQueuedMessages && (
        <span>{metrics?.queuedMessages} messages queued</span>
      )}
    </div>
  );
}
```

## Debugging

### Browser DevTools

**View Connection Metrics:**
```javascript
// In browser console
import { getWebSocketClient } from '@/services/websocket/EnhancedWebSocketClient';
const client = getWebSocketClient();
console.log(client.getMetrics());

// Output:
{
  state: "CONNECTED",
  connected: true,
  reconnects: 2,
  queuedMessages: 0,
  connectionDurationMs: 45000,
  url: "ws://localhost:8085/ws?conversation_id=..."
}
```

**Monitor State Changes:**
```javascript
// Add detailed logging to see every state transition
// (already logged to console as: "[WebSocket] State: X → Y")

// View in console:
// [WebSocket] State: CLOSED → CONNECTING
// [WebSocket] Connected
// [WebSocket] State: CONNECTING → CONNECTED
// [WebSocket] State: CONNECTED → DISCONNECTED
// [WebSocket] Reconnect attempt 1/10 in 750ms
// [WebSocket] State: DISCONNECTED → RECONNECTING
// [WebSocket] Connected
// [WebSocket] State: RECONNECTING → CONNECTED
```

**Simulate Network Issues:**

1. **Disable Network** (Chrome DevTools):
   - Open DevTools → Network tab
   - Toggle "Offline" checkbox
   - Watch connection state changes to DISCONNECTED
   - Re-enable network, watch auto-reconnect

2. **Slow Network** (Chrome DevTools):
   - Network tab → Change "Throttling" to "Slow 3G"
   - Watch heartbeat timeouts and reconnections

3. **WebSocket Errors** (Edit /ws endpoint):
   - Modify WS URL to invalid endpoint
   - Watch error handling and reconnection

### Connection Store in Components

```typescript
// Check if UI should show spinner
const { isReconnecting } = useConnection();
if (isReconnecting) {
  return <LoadingSpinner />;
}

// Check queued message count
const { metrics } = useConnection();
if (metrics?.queuedMessages) {
  console.log(`${metrics.queuedMessages} messages waiting to send`);
}
```

## Error Handling Integration

WebSocket errors are classified and added to error store:

```typescript
// In EnhancedWebSocketClient.ts
onError: (error) => {
  const novaError = toNovaError(error);
  useErrorStore.getState().addError(novaError);
}
```

Errors shown to user:
- **Network errors** → "Connection error" + auto-retry
- **Heartbeat timeout** → "Connection lost" + auto-reconnect
- **Server errors** → "WebSocket error" + details

## Best Practices

### 1. Always Use Connection Store

Instead of checking internal client state, use the store:

```typescript
// ❌ Bad - doesn't handle reconnection state
if (wsClient && wsClient.readyState === WebSocket.OPEN) {
  // send
}

// ✅ Good - reacts to all state changes
const { isConnected } = useConnection();
if (isConnected) {
  // send
}
```

### 2. Don't Queue Messages in WebSocket

The WebSocket client handles transient queueing. For persistent offline support, use OfflineQueue:

```typescript
// ❌ Don't rely on WebSocket queue for offline support
wsClient.send('message', { ... });

// ✅ Use OfflineQueue for persistent offline storage
import { OfflineQueue } from '@/services/offlineQueue/Queue';
const queue = new OfflineQueue();
queue.enqueue({ conversationId, userId, plaintext });
```

### 3. Handle Connection State Changes

React to connection changes in your UI:

```typescript
function ChatInput() {
  const { isConnected } = useConnection();

  return (
    <div>
      <input disabled={!isConnected} placeholder="Type a message..." />
      {!isConnected && <span className="text-red-500">Disconnected</span>}
    </div>
  );
}
```

### 4. Monitor Metrics in Production

Track reconnection frequency:

```typescript
// In error handling / analytics
const metrics = wsClient.getMetrics();
if (metrics.reconnects > 5) {
  // High reconnection count indicates network instability
  console.warn('High reconnection count:', metrics.reconnects);
  // Send to error tracking service
}
```

### 5. Clean Up on Unmount

Always disconnect when leaving conversation:

```typescript
useEffect(() => {
  connectWs(conversationId, userId);

  return () => {
    disconnectWs();
  };
}, [conversationId, userId]);
```

## Testing

### Unit Tests for EnhancedWebSocketClient

```typescript
import { EnhancedWebSocketClient, ConnectionState } from '@/services/websocket/EnhancedWebSocketClient';

describe('EnhancedWebSocketClient', () => {
  let client: EnhancedWebSocketClient;

  beforeEach(() => {
    client = new EnhancedWebSocketClient('ws://localhost:8085/ws', {});
  });

  test('connects and transitions to CONNECTED', async () => {
    const states: ConnectionState[] = [];
    const client = new EnhancedWebSocketClient('ws://localhost:8085/ws', {
      onStateChange: (state) => states.push(state),
    });

    client.connect();
    // Wait for connection
    await new Promise(r => setTimeout(r, 100));

    expect(states).toContain(ConnectionState.CONNECTING);
    expect(states).toContain(ConnectionState.CONNECTED);
  });

  test('queues messages when disconnected', () => {
    client.send('message', { text: 'hello' });

    const metrics = client.getMetrics();
    expect(metrics.queuedMessages).toBe(1);
  });

  test('calculates exponential backoff correctly', () => {
    // Backoff: 1s * 1.5^attempt
    expect(calculateBackoffDelay(0)).toBeLessThanOrEqual(1000);
    expect(calculateBackoffDelay(1)).toBeLessThanOrEqual(1500);
    expect(calculateBackoffDelay(9)).toBeLessThanOrEqual(60000); // Capped
  });
});
```

### Integration Tests

```typescript
// Test with mock WebSocket server (e.g., jest-websocket-mock)
test('reconnects after network failure', async () => {
  const server = new WS('ws://localhost:8085');

  const client = new EnhancedWebSocketClient('ws://localhost:8085/ws');
  client.connect();

  await expect(server).toReceiveMessage(
    expect.objectContaining({ type: 'ping' })
  );

  // Simulate disconnect
  server.close();

  // Client should attempt reconnect
  const metrics = client.getMetrics();
  expect(metrics.state).toMatch(/RECONNECTING|ERROR/);
});
```

## Configuration Reference

### Customizing Reconnect Behavior

```typescript
// In messagingStore.ts - adjust for your use case
connectWs: (conversationId, userId) => {
  const client = createWebSocketClient(url, handlers, {
    maxRetries: 10,              // More retries for mission-critical
    initialDelayMs: 1000,        // Faster first retry
    maxDelayMs: 30000,           // Lower max (3x faster)
    backoffMultiplier: 1.5,      // Exponential growth
    backoffJitter: true,         // Prevent thundering herd
  });
}
```

### Customizing Heartbeat

Edit `EnhancedWebSocketClient.ts`:
```typescript
const HEARTBEAT_INTERVAL_MS = 30000;  // How often to ping
const HEARTBEAT_TIMEOUT_MS = 10000;   // How long to wait for pong
```

### Customizing UI

Edit `ConnectionStatus.tsx`:
```typescript
// Change colors
const GREEN = '#10b981';    // Connected
const AMBER = '#f59e0b';    // Reconnecting
const RED = '#ef4444';      // Disconnected

// Change emojis
const CONNECTED_EMOJI = '🟢';
const RECONNECTING_EMOJI = '🟡';
const DISCONNECTED_EMOJI = '🔴';
```

## Summary

This system provides:

✅ **Transparent auto-reconnection** - No code changes needed
✅ **Reliable message delivery** - Heartbeat detects failures quickly
✅ **User feedback** - Connection status always visible
✅ **Production-ready** - Exponential backoff prevents thundering herd
✅ **Debuggable** - Comprehensive logging and metrics
✅ **Tested** - State machine design prevents edge cases

The implementation handles network failures transparently while keeping users informed of connection status.
