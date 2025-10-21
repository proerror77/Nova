/**
 * Nova Streaming Viewer Client - JavaScript Example
 *
 * This example demonstrates how to build a real-time streaming viewer
 * client using the Nova Streaming API and WebSocket protocol.
 *
 * Usage:
 *   node javascript-viewer-client.js --stream-id <uuid> --token <jwt>
 *
 * In browser:
 *   const viewer = new NovaStreamViewer(streamId, token);
 *   viewer.connect();
 *   viewer.on('viewer_count_changed', (data) => {
 *     console.log('Viewers:', data.viewer_count);
 *   });
 */

class NovaStreamViewer {
  /**
   * Initialize Nova Stream Viewer
   * @param {string} streamId - UUID of the stream to watch
   * @param {string} token - JWT authentication token
   * @param {object} options - Configuration options
   */
  constructor(streamId, token, options = {}) {
    this.streamId = streamId;
    this.token = token;
    this.baseUrl = options.baseUrl || 'wss://api.nova-social.io/api/v1';
    this.reconnectDelay = options.reconnectDelay || 3000;
    this.maxReconnectAttempts = options.maxReconnectAttempts || 5;

    // State
    this.ws = null;
    this.connected = false;
    this.reconnectAttempts = 0;
    this.sessionId = null;
    this.viewerId = null;
    this.pingTimeout = null;

    // Message handlers
    this.messageHandlers = {};
    this.pendingRequests = new Map();

    // Event emitter pattern
    this.listeners = {};
  }

  /**
   * Connect to the stream
   */
  connect() {
    if (this.connected || this.ws) {
      console.warn('Already connected or connecting');
      return;
    }

    const wsUrl = new URL(`${this.baseUrl}/streams/${this.streamId}/ws`);
    wsUrl.searchParams.append('token', this.token);

    console.log(`[Connecting] Stream: ${this.streamId}`);

    this.ws = new WebSocket(wsUrl.toString());

    this.ws.addEventListener('open', () => this.onOpen());
    this.ws.addEventListener('message', (e) => this.onMessage(e));
    this.ws.addEventListener('error', (e) => this.onError(e));
    this.ws.addEventListener('close', (e) => this.onClose(e));
  }

  /**
   * Handle WebSocket open event
   * @private
   */
  onOpen() {
    console.log('[Connected] WebSocket connection established');
    this.connected = true;
    this.reconnectAttempts = 0;
    this.setupPingInterval();
    this.emit('connected');
  }

  /**
   * Handle incoming WebSocket message
   * @private
   */
  onMessage(event) {
    try {
      const message = JSON.parse(event.data);

      // Log message for debugging
      if (process.env.DEBUG) {
        console.log('[Message]', message.event, message.data);
      }

      // Route to handler
      const handler = this.messageHandlers[message.event];
      if (handler) {
        handler.call(this, message.data);
      } else {
        console.warn(`[Warning] Unknown message type: ${message.event}`);
      }
    } catch (error) {
      console.error('[Error] Failed to parse message:', error);
    }
  }

  /**
   * Handle WebSocket error
   * @private
   */
  onError(error) {
    console.error('[Error] WebSocket error:', error);
    this.emit('error', error);
  }

  /**
   * Handle WebSocket close event
   * @private
   */
  onClose(event) {
    console.log('[Disconnected] WebSocket closed', {
      code: event.code,
      reason: event.reason,
      wasClean: event.wasClean,
    });

    this.connected = false;
    this.ws = null;
    clearInterval(this.pingTimeout);
    this.emit('disconnected');

    // Attempt to reconnect
    if (!event.wasClean && this.reconnectAttempts < this.maxReconnectAttempts) {
      this.reconnectAttempts++;
      const delay = this.reconnectDelay * this.reconnectAttempts;
      console.log(`[Reconnecting] Attempt ${this.reconnectAttempts}/${this.maxReconnectAttempts} in ${delay}ms`);
      setTimeout(() => this.connect(), delay);
    }
  }

  /**
   * Setup ping/pong interval to keep connection alive
   * @private
   */
  setupPingInterval() {
    this.pingTimeout = setInterval(() => {
      if (this.connected && this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.send({
          event: 'pong',
          data: {
            timestamp: new Date().toISOString(),
          },
        });
      }
    }, 30000); // Every 30 seconds
  }

  /**
   * Send message to server
   * @param {object} message - Message to send
   */
  send(message) {
    if (!this.connected || !this.ws || this.ws.readyState !== WebSocket.OPEN) {
      console.warn('[Warning] WebSocket not connected, dropping message');
      return false;
    }

    this.ws.send(JSON.stringify(message));
    return true;
  }

  /**
   * Get current stream information
   * @returns {Promise<object>}
   */
  async getStreamInfo() {
    const requestId = `req-${Date.now()}`;
    const promise = new Promise((resolve) => {
      this.pendingRequests.set(requestId, resolve);

      // Timeout after 5 seconds
      setTimeout(() => {
        this.pendingRequests.delete(requestId);
        resolve(null);
      }, 5000);
    });

    this.send({
      event: 'get_stream_info',
      data: { request_id: requestId },
    });

    return promise;
  }

  /**
   * Report playback issue
   * @param {string} issueType - Type of issue (buffering, lag, etc.)
   * @param {string} description - Issue description
   */
  reportIssue(issueType, description) {
    this.send({
      event: 'report_issue',
      data: {
        issue_type: issueType,
        severity: 'medium',
        description,
        client_info: {
          player: 'nova-client',
          browser: this.getBrowserInfo(),
          network: navigator.connection?.effectiveType || 'unknown',
          bandwidth_estimate_kbps: navigator.connection?.downlink * 1000 || 0,
        },
      },
    });
  }

  /**
   * Get browser information
   * @private
   */
  getBrowserInfo() {
    const ua = navigator.userAgent;
    if (ua.indexOf('Firefox') > -1) return 'Firefox';
    if (ua.indexOf('Chrome') > -1) return 'Chrome';
    if (ua.indexOf('Safari') > -1) return 'Safari';
    if (ua.indexOf('Edge') > -1) return 'Edge';
    return 'Unknown';
  }

  /**
   * Register message handler
   * @param {string} event - Event type
   * @param {function} handler - Handler function
   */
  on(event, handler) {
    if (!this.messageHandlers[event]) {
      this.messageHandlers[event] = this.createMessageHandler(event);
    }
    if (!this.listeners[event]) {
      this.listeners[event] = [];
    }
    this.listeners[event].push(handler);
  }

  /**
   * Create a message handler that delegates to listeners
   * @private
   */
  createMessageHandler(event) {
    return (data) => {
      if (this.listeners[event]) {
        this.listeners[event].forEach((handler) => {
          try {
            handler(data);
          } catch (error) {
            console.error(`[Error] Handler for ${event} threw:`, error);
          }
        });
      }
    };
  }

  /**
   * Emit event to listeners
   * @private
   */
  emit(event, data) {
    if (this.listeners[event]) {
      this.listeners[event].forEach((handler) => {
        try {
          handler(data);
        } catch (error) {
          console.error(`[Error] Handler for ${event} threw:`, error);
        }
      });
    }
  }

  /**
   * Disconnect from stream
   */
  disconnect() {
    if (this.ws) {
      this.ws.close(1000, 'User requested disconnect');
    }
  }
}

// ============================================================================
// Built-in Message Handlers
// ============================================================================

/**
 * Handle connection_established message
 */
NovaStreamViewer.prototype.messageHandlers = {
  'connection_established': function (data) {
    console.log('[Connected] Session established', {
      viewer_id: data.viewer_id,
      session_id: data.session_id,
    });
    this.viewerId = data.viewer_id;
    this.sessionId = data.session_id;
    this.emit('session_established', data);
  },

  'stream_started': function (data) {
    console.log('[Stream Started]', {
      title: data.title,
      quality: data.quality,
      bitrate_kbps: data.bitrate_kbps,
    });
    this.emit('stream_started', data);
  },

  'stream_ended': function (data) {
    console.log('[Stream Ended]', {
      duration_seconds: data.duration_seconds,
      peak_viewers: data.peak_viewers,
    });
    this.emit('stream_ended', data);
  },

  'viewer_count_changed': function (data) {
    if (process.env.DEBUG) {
      console.log('[Viewers]', data.viewer_count, `(Peak: ${data.peak_viewers})`);
    }
    this.emit('viewer_count_changed', data);
  },

  'quality_changed': function (data) {
    console.log('[Quality Changed]', {
      from: data.previous_quality,
      to: data.new_quality,
      bitrate_kbps: data.new_bitrate_kbps,
      reason: data.reason,
    });
    this.emit('quality_changed', data);
  },

  'bitrate_update': function (data) {
    if (process.env.DEBUG) {
      console.log('[Bitrate]', data.current_bitrate_kbps, 'kbps, health:', data.health);
    }
    this.emit('bitrate_update', data);
  },

  'error': function (data) {
    console.error('[Stream Error]', {
      code: data.error_code,
      message: data.error_message,
      severity: data.severity,
      recoverable: data.recoverable,
    });
    this.emit('stream_error', data);
  },

  'stream_info': function (data) {
    const handler = this.pendingRequests.get(data.request_id);
    if (handler) {
      this.pendingRequests.delete(data.request_id);
      handler(data);
    }
  },

  'ping': function (data) {
    // Already handled by pong sent in setupPingInterval
    if (process.env.DEBUG) {
      console.log('[Ping] Sequence:', data.sequence);
    }
  },
};

// ============================================================================
// CLI Example (Node.js)
// ============================================================================

if (typeof module !== 'undefined' && module.exports) {
  module.exports = NovaStreamViewer;

  // CLI usage
  if (require.main === module) {
    const args = require('minimist')(process.argv.slice(2));

    if (!args['stream-id'] || !args.token) {
      console.error('Usage: node javascript-viewer-client.js --stream-id <uuid> --token <jwt>');
      process.exit(1);
    }

    const viewer = new NovaStreamViewer(args['stream-id'], args.token);

    // Set up event handlers
    viewer.on('connected', () => {
      console.log('✓ Connected to stream');

      // Request stream info
      viewer.getStreamInfo().then((info) => {
        if (info) {
          console.log('Stream info:', {
            status: info.status,
            viewers: info.viewer_count,
            quality: info.quality,
            bitrate_kbps: info.bitrate_kbps,
          });
        }
      });
    });

    viewer.on('session_established', (data) => {
      console.log('✓ Session established:', data.session_id);
    });

    viewer.on('stream_started', (data) => {
      console.log(`► Stream started: ${data.title}`);
    });

    viewer.on('viewer_count_changed', (data) => {
      console.log(`• Viewers: ${data.viewer_count} (Peak: ${data.peak_viewers})`);
    });

    viewer.on('quality_changed', (data) => {
      console.log(`~ Quality: ${data.previous_quality} → ${data.new_quality} (${data.new_bitrate_kbps} kbps)`);
    });

    viewer.on('stream_ended', (data) => {
      console.log(`✗ Stream ended (Duration: ${data.duration_seconds}s, Peak: ${data.peak_viewers})`);
      setTimeout(() => process.exit(0), 1000);
    });

    viewer.on('stream_error', (data) => {
      console.error(`✗ Stream error: ${data.error_message}`);
    });

    viewer.on('disconnected', () => {
      console.log('✗ Disconnected');
    });

    // Connect
    viewer.connect();

    // Handle process signals
    process.on('SIGINT', () => {
      console.log('\nDisconnecting...');
      viewer.disconnect();
      setTimeout(() => process.exit(0), 1000);
    });
  }
}

// ============================================================================
// Browser Usage Example
// ============================================================================

/**
 * Example HTML/React integration:
 *
 * <div id="stream-player">
 *   <video id="video" width="100%" height="100%"></video>
 *   <div id="stats">
 *     <span id="viewer-count">Loading...</span>
 *     <span id="stream-quality">-</span>
 *   </div>
 * </div>
 *
 * <script>
 *   const viewer = new NovaStreamViewer(streamId, token);
 *
 *   viewer.on('connected', () => {
 *     console.log('Stream viewer connected');
 *   });
 *
 *   viewer.on('viewer_count_changed', (data) => {
 *     document.getElementById('viewer-count').textContent = data.viewer_count;
 *   });
 *
 *   viewer.on('quality_changed', (data) => {
 *     document.getElementById('stream-quality').textContent = data.new_quality;
 *   });
 *
 *   viewer.on('stream_error', (data) => {
 *     alert(`Stream Error: ${data.error_message}`);
 *   });
 *
 *   viewer.connect();
 *
 *   window.addEventListener('beforeunload', () => {
 *     viewer.disconnect();
 *   });
 * </script>
 */
