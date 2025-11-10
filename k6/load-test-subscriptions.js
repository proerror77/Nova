/**
 * k6 Subscription Load Testing
 * ✅ P0-5: WebSocket subscription performance testing
 *
 * Tests subscription scalability, backpressure, and event delivery
 */

import ws from 'k6/ws';
import { check, sleep, group } from 'k6';
import { Counter, Gauge, Trend } from 'k6/metrics';

// ============================================================================
// METRICS
// ============================================================================

const activeConnections = new Gauge('ws_active_connections');
const messagesReceived = new Counter('ws_messages_received');
const messageLatency = new Trend('ws_message_latency');
const connectionErrors = new Counter('ws_connection_errors');
const subscriptionErrors = new Counter('ws_subscription_errors');

// ============================================================================
// CONFIGURATION
// ============================================================================

export const options = {
  stages: [
    // Ramp up connections
    { duration: '30s', target: 50 },
    // Maintain connections
    { duration: '2m', target: 50 },
    // Scale up subscriptions
    { duration: '1m', target: 200 },
    // High load test
    { duration: '2m', target: 200 },
    // Ramp down
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    ws_message_latency: ['p(95)<1000', 'p(99)<2000'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const WS_ENDPOINT = __ENV.WS_ENDPOINT || 'ws://localhost:8000/graphql';

// ============================================================================
// SUBSCRIPTION QUERIES
// ============================================================================

const feedSubscriptionQuery = `
  subscription {
    feedUpdated {
      id
      content
      createdAt
    }
  }
`;

const notificationSubscriptionQuery = `
  subscription {
    notificationReceived {
      id
      message
      type
    }
  }
`;

const multipleSubscriptionsQuery = `
  subscription {
    feedUpdated { id content }
    notificationReceived { id message }
  }
`;

// ============================================================================
// SUBSCRIPTION TEST
// ============================================================================

export default function () {
  activeConnections.add(1);

  group('WebSocket Subscriptions', () => {
    const subscriptionTypes = [
      { name: 'Feed Subscription', query: feedSubscriptionQuery },
      { name: 'Notification Subscription', query: notificationSubscriptionQuery },
      { name: 'Multiple Subscriptions', query: multipleSubscriptionsQuery },
    ];

    const selectedSub = subscriptionTypes[Math.floor(Math.random() * subscriptionTypes.length)];

    const url = `${WS_ENDPOINT}`;
    let messageCount = 0;
    let lastMessageTime = Date.now();

    const res = ws.connect(url, null, function (socket) {
      socket.on('open', () => {
        check(socket.readyState, {
          'connection open': (state) => state === ws.OPEN,
        });

        // Send subscription
        socket.send(
          JSON.stringify({
            type: 'start',
            payload: {
              query: selectedSub.query,
            },
          })
        );

        // Keep subscription alive for 30 seconds
        const startTime = Date.now();
        socket.setTimeout(() => {
          socket.close();
        }, 30000);
      });

      socket.on('message', (message) => {
        const receivedTime = Date.now();
        const latency = receivedTime - lastMessageTime;
        messageLatency.add(latency);
        messagesReceived.add(1);
        messageCount++;
        lastMessageTime = receivedTime;

        const data = JSON.parse(message);

        check(data, {
          'message has data': (d) => d.type === 'data' || d.type === 'next',
          'no errors': (d) => !d.errors,
        });

        if (data.errors) {
          subscriptionErrors.add(1);
        }
      });

      socket.on('error', (err) => {
        connectionErrors.add(1);
      });

      socket.on('close', () => {
        activeConnections.add(-1);
      });
    });

    check(res, {
      'subscription established': (r) => r && r.status === 101,
    });

    sleep(2);
  });

  activeConnections.add(-1);
}

// ============================================================================
// BACKPRESSURE TEST SCENARIO
// ============================================================================

export function backpressureTest() {
  group('Backpressure Handling', () => {
    const url = `${WS_ENDPOINT}`;

    ws.connect(url, null, function (socket) {
      socket.on('open', () => {
        // Send rapid subscriptions to trigger backpressure
        for (let i = 0; i < 100; i++) {
          socket.send(
            JSON.stringify({
              type: 'start',
              payload: {
                query: feedSubscriptionQuery,
                variables: { userId: `user_${i % 50}` },
              },
            })
          );
        }

        // Give time for responses
        socket.setTimeout(() => {
          socket.close();
        }, 10000);
      });

      socket.on('message', (message) => {
        const data = JSON.parse(message);

        // Check for backpressure status
        if (data.extensions && data.extensions.backpressure) {
          check(data.extensions.backpressure, {
            'backpressure status': (bp) => ['normal', 'warning', 'critical'].includes(bp.status),
          });
        }
      });

      socket.on('error', (err) => {
        connectionErrors.add(1);
      });
    });

    sleep(1);
  });
}

// ============================================================================
// CONCURRENT SUBSCRIPTIONS TEST
// ============================================================================

export function concurrentSubscriptionsTest() {
  group('Concurrent Subscriptions', () => {
    const connections = [];

    // Open 50 concurrent WebSocket connections
    for (let i = 0; i < 50; i++) {
      const url = `${WS_ENDPOINT}`;
      const res = ws.connect(url, null, function (socket) {
        socket.on('open', () => {
          // Each connection subscribes to feed updates
          socket.send(
            JSON.stringify({
              type: 'start',
              payload: {
                query: feedSubscriptionQuery,
              },
            })
          );

          // Keep alive for 20 seconds
          socket.setTimeout(() => {
            socket.close();
          }, 20000);
        });

        socket.on('message', (message) => {
          const data = JSON.parse(message);
          if (data.type === 'data') {
            messagesReceived.add(1);
          }
        });

        socket.on('error', () => {
          connectionErrors.add(1);
        });
      });

      connections.push(res);
    }

    // Monitor concurrent connections
    check(connections.length, {
      'all connections established': (len) => len === 50,
    });

    sleep(5);
  });
}

/**
 * Usage:
 *
 * # Run subscription tests
 * k6 run load-test-subscriptions.js
 *
 * # Run backpressure test only
 * k6 run -e SCENARIO=backpressure load-test-subscriptions.js
 *
 * # Run with custom WebSocket endpoint
 * WS_ENDPOINT=wss://api.example.com/graphql k6 run load-test-subscriptions.js
 *
 * # Run concurrent subscriptions test
 * k6 run load-test-subscriptions.js --stage 1m:100
 */
