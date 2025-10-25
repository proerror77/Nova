/**
 * Enhanced WebSocket Client with Auto-Reconnection
 * Features: exponential backoff, heartbeat, message queueing, connection state tracking
 */

// ============================================
// Types
// ============================================

export enum ConnectionState {
  CONNECTING = 'CONNECTING',
  CONNECTED = 'CONNECTED',
  DISCONNECTED = 'DISCONNECTED',
  RECONNECTING = 'RECONNECTING',
  CLOSED = 'CLOSED',
  ERROR = 'ERROR',
}

export interface WsHandlers {
  onMessage?: (payload: any) => void;
  onTyping?: (conversationId: string, userId: string) => void;
  onOpen?: () => void;
  onClose?: () => void;
  onError?: (err: any) => void;
  onStateChange?: (state: ConnectionState) => void;
}

export interface ReconnectConfig {
  maxRetries: number;
  initialDelayMs: number;
  maxDelayMs: number;
  backoffMultiplier: number;
  backoffJitter: boolean;
}

const DEFAULT_RECONNECT_CONFIG: ReconnectConfig = {
  maxRetries: 10,           // Try up to 10 times (>30 minutes total with backoff)
  initialDelayMs: 1000,     // Start with 1 second
  maxDelayMs: 60000,        // Cap at 1 minute
  backoffMultiplier: 1.5,   // Exponential: 1s, 1.5s, 2.25s, 3.375s, ...
  backoffJitter: true,      // Add randomness to prevent thundering herd
};

const HEARTBEAT_INTERVAL_MS = 30000; // Send ping every 30 seconds
const HEARTBEAT_TIMEOUT_MS = 10000;  // Timeout after 10 seconds no pong

// ============================================
// Message Queue for Offline Support
// ============================================

interface QueuedMessage {
  type: string;
  payload: any;
  timestamp: number;
  attempts: number;
}

class MessageQueue {
  private queue: QueuedMessage[] = [];
  private maxSize = 100;

  enqueue(type: string, payload: any): void {
    if (this.queue.length >= this.maxSize) {
      this.queue.shift(); // Remove oldest
    }
    this.queue.push({
      type,
      payload,
      timestamp: Date.now(),
      attempts: 0,
    });
  }

  drain(): QueuedMessage[] {
    const items = [...this.queue];
    this.queue = [];
    return items;
  }

  clear(): void {
    this.queue = [];
  }

  size(): number {
    return this.queue.length;
  }
}

// ============================================
// Enhanced WebSocket Client
// ============================================

export class EnhancedWebSocketClient {
  private ws: WebSocket | null = null;
  private handlers: WsHandlers;
  private url: string;
  private reconnectConfig: ReconnectConfig;
  private messageQueue: MessageQueue;

  // Connection state
  private state: ConnectionState = ConnectionState.CLOSED;
  private reconnectAttempts = 0;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private heartbeatTimer: NodeJS.Timeout | null = null;
  private heartbeatTimeout: NodeJS.Timeout | null = null;
  private lastMessageTime = 0;
  private intentionallyClosed = false; // Track intentional disconnects

  // Metrics
  private connectionStartTime: number | null = null;
  private totalReconnects = 0;

  constructor(url: string, handlers: WsHandlers = {}, reconnectConfig: Partial<ReconnectConfig> = {}) {
    this.url = url;
    this.handlers = handlers;
    this.reconnectConfig = { ...DEFAULT_RECONNECT_CONFIG, ...reconnectConfig };
    this.messageQueue = new MessageQueue();
  }

  /**
   * Connect to WebSocket
   */
  connect(): void {
    if (this.state === ConnectionState.CONNECTED || this.state === ConnectionState.CONNECTING) {
      console.warn('[WebSocket] Already connected or connecting');
      return;
    }

    this.setState(ConnectionState.CONNECTING);

    try {
      this.ws = new WebSocket(this.url);
      this.connectionStartTime = Date.now();

      this.ws.onopen = () => this.onOpen();
      this.ws.onclose = () => this.onClose();
      this.ws.onerror = (event) => this.onError(event);
      this.ws.onmessage = (event) => this.onMessage(event);
    } catch (error) {
      console.error('[WebSocket] Connection failed:', error);
      this.setState(ConnectionState.ERROR);
      this.scheduleReconnect();
    }
  }

  /**
   * Disconnect and cleanup
   */
  disconnect(): void {
    this.intentionallyClosed = true; // Mark as intentional
    this.clearTimers();
    if (this.ws) {
      this.ws.close(1000, 'Normal closure');
      this.ws = null;
    }
    this.setState(ConnectionState.CLOSED);
    this.reconnectAttempts = 0;
  }

  /**
   * Send message through WebSocket
   */
  send(type: string, payload: any = {}): void {
    const message = { type, ...payload };

    if (this.state === ConnectionState.CONNECTED && this.ws && this.ws.readyState === WebSocket.OPEN) {
      try {
        this.ws.send(JSON.stringify(message));
        this.lastMessageTime = Date.now();
      } catch (error) {
        console.error('[WebSocket] Send failed:', error);
        this.messageQueue.enqueue(type, payload);
      }
    } else {
      // Queue message if not connected
      this.messageQueue.enqueue(type, payload);

      if (this.state === ConnectionState.DISCONNECTED || this.state === ConnectionState.CLOSED) {
        // Attempt reconnect if not already trying
        if (this.state === ConnectionState.CLOSED) {
          this.connect();
        }
      }
    }
  }

  /**
   * Send typing indicator
   */
  sendTyping(conversationId: string, userId: string): void {
    this.send('typing', { conversation_id: conversationId, user_id: userId });
  }

  /**
   * Get current connection state
   */
  getState(): ConnectionState {
    return this.state;
  }

  /**
   * Get connection metrics
   */
  getMetrics() {
    return {
      state: this.state,
      connected: this.state === ConnectionState.CONNECTED,
      reconnects: this.totalReconnects,
      queuedMessages: this.messageQueue.size(),
      connectionDurationMs: this.connectionStartTime ? Date.now() - this.connectionStartTime : 0,
      url: this.url,
    };
  }

  // ============================================
  // Private Methods
  // ============================================

  private setState(newState: ConnectionState): void {
    if (this.state !== newState) {
      console.log(`[WebSocket] State: ${this.state} → ${newState}`);
      this.state = newState;
      this.handlers.onStateChange?.(newState);
    }
  }

  private onOpen(): void {
    console.log('[WebSocket] Connected');
    this.setState(ConnectionState.CONNECTED);
    this.reconnectAttempts = 0;
    this.lastMessageTime = Date.now();

    // Start heartbeat
    this.startHeartbeat();

    // Drain queued messages
    this.drainMessageQueue();

    // User callback
    this.handlers.onOpen?.();
  }

  private onClose(): void {
    console.log('[WebSocket] Disconnected');
    this.stopHeartbeat();

    // Only schedule reconnect if NOT intentionally closed
    if (this.intentionallyClosed) {
      this.setState(ConnectionState.CLOSED);
      this.intentionallyClosed = false; // Reset for next connection
    } else {
      this.setState(ConnectionState.DISCONNECTED);
      this.scheduleReconnect();
    }
  }

  private onError(event: Event): void {
    console.error('[WebSocket] Error:', event);
    this.setState(ConnectionState.ERROR);
    this.stopHeartbeat();
    this.handlers.onError?.(event);

    // Schedule reconnect
    this.scheduleReconnect();
  }

  private onMessage(event: MessageEvent): void {
    try {
      const data = JSON.parse(event.data as string);

      // Validate message structure
      if (!data || typeof data !== 'object') {
        console.warn('[WebSocket] Invalid message format:', event.data);
        return;
      }

      const messageType = data.type as string | undefined;

      // Handle specific message types
      switch (messageType) {
        case 'pong':
          this.handlePong();
          break;

        case 'typing':
          this.handlers.onTyping?.(data.conversation_id, data.user_id);
          break;

        case 'message':
          this.handlers.onMessage?.(data);
          break;

        default:
          // Log unknown message types for debugging
          if (messageType) {
            console.debug('[WebSocket] Unknown message type:', messageType);
          } else {
            console.warn('[WebSocket] Message missing type field:', data);
          }

          // Still pass to handler for custom message types
          // (applications may handle additional message types)
          if (this.handlers.onMessage) {
            this.handlers.onMessage(data);
          }
      }
    } catch (error) {
      console.error('[WebSocket] Failed to parse message:', error);
    }
  }

  /**
   * Start heartbeat (ping/pong mechanism)
   */
  private startHeartbeat(): void {
    this.stopHeartbeat();

    this.heartbeatTimer = setInterval(() => {
      if (this.state === ConnectionState.CONNECTED && this.ws?.readyState === WebSocket.OPEN) {
        try {
          this.ws!.send(JSON.stringify({ type: 'ping' }));

          // Set timeout for pong response
          this.heartbeatTimeout = setTimeout(() => {
            console.warn('[WebSocket] Heartbeat timeout - no pong received');
            if (this.ws) {
              this.ws.close(1000, 'Heartbeat timeout');
            }
          }, HEARTBEAT_TIMEOUT_MS);
        } catch (error) {
          console.error('[WebSocket] Heartbeat send failed:', error);
        }
      }
    }, HEARTBEAT_INTERVAL_MS);
  }

  /**
   * Handle pong response
   */
  private handlePong(): void {
    if (this.heartbeatTimeout) {
      clearTimeout(this.heartbeatTimeout);
      this.heartbeatTimeout = null;
    }
  }

  /**
   * Stop heartbeat
   */
  private stopHeartbeat(): void {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
    if (this.heartbeatTimeout) {
      clearTimeout(this.heartbeatTimeout);
      this.heartbeatTimeout = null;
    }
  }

  /**
   * Schedule reconnect with exponential backoff
   */
  private scheduleReconnect(): void {
    if (this.reconnectAttempts >= this.reconnectConfig.maxRetries) {
      console.error('[WebSocket] Max reconnect attempts reached');
      this.setState(ConnectionState.CLOSED);
      return;
    }

    this.setState(ConnectionState.RECONNECTING);

    const delay = this.calculateBackoffDelay(this.reconnectAttempts);
    console.log(`[WebSocket] Reconnect attempt ${this.reconnectAttempts + 1}/${this.reconnectConfig.maxRetries} in ${delay}ms`);

    this.reconnectTimer = setTimeout(() => {
      this.reconnectAttempts++;
      this.totalReconnects++;
      this.connect();
    }, delay);
  }

  /**
   * Calculate exponential backoff delay with jitter
   */
  private calculateBackoffDelay(attempt: number): number {
    let delay = this.reconnectConfig.initialDelayMs * Math.pow(this.reconnectConfig.backoffMultiplier, attempt);
    delay = Math.min(delay, this.reconnectConfig.maxDelayMs);

    if (this.reconnectConfig.backoffJitter) {
      // Add jitter: delay * (0.5 to 1.0)
      delay = delay * (0.5 + Math.random() * 0.5);
    }

    return Math.round(delay);
  }

  /**
   * Drain queued messages and resend
   */
  private drainMessageQueue(): void {
    const queued = this.messageQueue.drain();

    if (queued.length === 0) {
      return;
    }

    console.log(`[WebSocket] Draining ${queued.length} queued messages`);

    for (const msg of queued) {
      if (this.state === ConnectionState.CONNECTED) {
        try {
          this.ws!.send(JSON.stringify({ type: msg.type, ...msg.payload }));
        } catch (error) {
          console.error('[WebSocket] Failed to resend queued message:', error);
          // Re-queue if send fails
          this.messageQueue.enqueue(msg.type, msg.payload);
        }
      }
    }
  }

  /**
   * Clear all timers
   */
  private clearTimers(): void {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.stopHeartbeat();
  }
}

// ============================================
// Export singleton instance
// ============================================

let websocketInstance: EnhancedWebSocketClient | null = null;

export function createWebSocketClient(
  url: string,
  handlers?: WsHandlers,
  reconnectConfig?: Partial<ReconnectConfig>
): EnhancedWebSocketClient {
  if (websocketInstance) {
    websocketInstance.disconnect();
  }
  websocketInstance = new EnhancedWebSocketClient(url, handlers, reconnectConfig);
  return websocketInstance;
}

export function getWebSocketClient(): EnhancedWebSocketClient | null {
  return websocketInstance;
}
