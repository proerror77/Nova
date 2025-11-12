/**
 * PgBouncer Load Testing Script using k6
 *
 * Purpose: Validate PgBouncer connection pooling performance and verify:
 * 1. Connection multiplexing efficiency
 * 2. Query latency (P95, P99)
 * 3. Backend connection count stays low
 * 4. No connection queueing under load
 * 5. Zero error rate under normal load
 *
 * Prerequisites:
 * - k6 installed: brew install k6 (macOS) or apt install k6 (Ubuntu)
 * - kubectl port-forward running: kubectl port-forward -n nova svc/graphql-gateway 4000:4000
 * - Valid JWT token in environment: export JWT_TOKEN="..."
 *
 * Usage:
 *   # Baseline test (50 VUs for 5 minutes)
 *   k6 run --vus 50 --duration 5m pgbouncer-load-test.js
 *
 *   # Stress test (200 VUs for 10 minutes)
 *   k6 run --vus 200 --duration 10m pgbouncer-load-test.js
 *
 *   # Spike test (ramp up to 500 VUs)
 *   k6 run --stage 1m:50,5m:500,1m:50 pgbouncer-load-test.js
 *
 * Expected Results:
 * - P95 latency < 100ms (GraphQL queries)
 * - P99 latency < 300ms
 * - Error rate: 0%
 * - Backend connections: 25-50 (check Prometheus: pgbouncer_pools_sv_active)
 */

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// Custom metrics
const errorRate = new Rate('errors');
const queryLatency = new Trend('query_latency');
const connectionErrors = new Counter('connection_errors');
const authErrors = new Counter('auth_errors');

// Configuration
const BASE_URL = __ENV.BASE_URL || 'http://localhost:4000';
const JWT_TOKEN = __ENV.JWT_TOKEN || '';

// Test options
export const options = {
  // Thresholds define pass/fail criteria
  thresholds: {
    http_req_duration: ['p(95)<100', 'p(99)<300'], // 95% < 100ms, 99% < 300ms
    errors: ['rate<0.01'], // Error rate must be below 1%
    http_req_failed: ['rate<0.01'], // Failed request rate < 1%
  },

  // Stages for gradual ramp-up (can be overridden via CLI)
  stages: [
    { duration: '1m', target: 10 },   // Warm-up
    { duration: '2m', target: 50 },   // Normal load
    { duration: '5m', target: 100 },  // Peak load
    { duration: '2m', target: 50 },   // Scale down
    { duration: '1m', target: 0 },    // Cool down
  ],

  // Additional options
  noConnectionReuse: false, // Enable HTTP keep-alive
  userAgent: 'k6-pgbouncer-load-test/1.0',
};

// GraphQL queries for testing
const QUERIES = {
  // Read-heavy query (feed-service)
  getFeed: {
    query: `
      query GetFeed($limit: Int!) {
        feed(limit: $limit) {
          id
          title
          content
          authorId
          createdAt
          updatedAt
        }
      }
    `,
    variables: { limit: 20 },
  },

  // User query (user-service)
  getUser: {
    query: `
      query GetUser($id: ID!) {
        user(id: $id) {
          id
          username
          email
          profile {
            displayName
            bio
          }
          createdAt
        }
      }
    `,
    variables: { id: '00000000-0000-0000-0000-000000000001' },
  },

  // Content query (content-service)
  getContent: {
    query: `
      query GetContent($id: ID!) {
        content(id: $id) {
          id
          title
          body
          authorId
          tags
          publishedAt
        }
      }
    `,
    variables: { id: '00000000-0000-0000-0000-000000000001' },
  },

  // Search query (search-service via ClickHouse)
  searchContent: {
    query: `
      query SearchContent($query: String!, $limit: Int!) {
        searchContent(query: $query, limit: $limit) {
          id
          title
          snippet
          score
        }
      }
    `,
    variables: { query: 'test', limit: 10 },
  },

  // Mutation (write operation via content-service)
  createContent: {
    query: `
      mutation CreateContent($input: CreateContentInput!) {
        createContent(input: $input) {
          id
          title
          body
          createdAt
        }
      }
    `,
    variables: {
      input: {
        title: `Load Test Content ${Date.now()}`,
        body: 'This is a test content created during load testing',
        tags: ['load-test', 'pgbouncer'],
      },
    },
  },
};

/**
 * Setup function - runs once per VU before the test
 */
export function setup() {
  console.log('Starting PgBouncer load test...');
  console.log(`Base URL: ${BASE_URL}`);
  console.log(`JWT Token: ${JWT_TOKEN ? 'Provided' : 'Missing (auth will fail!)'}`);

  // Verify GraphQL endpoint is accessible
  const healthCheck = http.get(`${BASE_URL}/health`);
  const isHealthy = check(healthCheck, {
    'GraphQL endpoint is healthy': (r) => r.status === 200,
  });

  if (!isHealthy) {
    console.error('❌ GraphQL endpoint health check failed!');
    console.error(`Status: ${healthCheck.status}`);
    console.error(`Body: ${healthCheck.body}`);
  }

  return { startTime: Date.now() };
}

/**
 * Main test function - runs repeatedly for each VU
 */
export default function (data) {
  const headers = {
    'Content-Type': 'application/json',
  };

  // Add JWT token if provided
  if (JWT_TOKEN) {
    headers['Authorization'] = `Bearer ${JWT_TOKEN}`;
  }

  // Randomly select a query to execute (weighted distribution)
  const rand = Math.random();
  let selectedQuery;
  let queryName;

  if (rand < 0.4) {
    // 40% - Feed queries (most common)
    selectedQuery = QUERIES.getFeed;
    queryName = 'getFeed';
  } else if (rand < 0.7) {
    // 30% - User queries
    selectedQuery = QUERIES.getUser;
    queryName = 'getUser';
  } else if (rand < 0.9) {
    // 20% - Content queries
    selectedQuery = QUERIES.getContent;
    queryName = 'getContent';
  } else if (rand < 0.98) {
    // 8% - Search queries
    selectedQuery = QUERIES.searchContent;
    queryName = 'searchContent';
  } else {
    // 2% - Write operations (mutations)
    selectedQuery = QUERIES.createContent;
    queryName = 'createContent';
  }

  // Execute GraphQL request
  const startTime = Date.now();
  const response = http.post(
    `${BASE_URL}/graphql`,
    JSON.stringify(selectedQuery),
    { headers, tags: { query: queryName } }
  );
  const duration = Date.now() - startTime;

  // Record custom metrics
  queryLatency.add(duration);

  // Check response
  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response has data': (r) => {
      try {
        const body = JSON.parse(r.body);
        return body.data !== undefined && body.data !== null;
      } catch (e) {
        return false;
      }
    },
    'no GraphQL errors': (r) => {
      try {
        const body = JSON.parse(r.body);
        return !body.errors || body.errors.length === 0;
      } catch (e) {
        return false;
      }
    },
    'latency below 1 second': (r) => r.timings.duration < 1000,
  });

  // Record error metrics
  if (!success) {
    errorRate.add(1);

    // Categorize error types
    if (response.status === 401 || response.status === 403) {
      authErrors.add(1);
      console.error(`❌ Auth error for ${queryName}: ${response.status}`);
    } else if (response.status >= 500) {
      connectionErrors.add(1);
      console.error(`❌ Server error for ${queryName}: ${response.status}`);
    }

    // Log first 100 chars of error response
    console.error(`Error response: ${response.body.substring(0, 100)}...`);
  } else {
    errorRate.add(0);
  }

  // Think time: simulate realistic user behavior
  // Random sleep between 0.5 and 3 seconds
  sleep(Math.random() * 2.5 + 0.5);
}

/**
 * Teardown function - runs once after the test completes
 */
export function teardown(data) {
  const duration = Date.now() - data.startTime;
  console.log(`\n✅ Load test completed in ${Math.round(duration / 1000)}s`);
  console.log('\n📊 Check Grafana for detailed metrics:');
  console.log('   - PgBouncer Dashboard: http://localhost:3000/d/nova-pgbouncer');
  console.log('   - Outbox Dashboard: http://localhost:3000/d/nova-outbox-pattern');
  console.log('   - mTLS Dashboard: http://localhost:3000/d/nova-mtls-security');
  console.log('\n📈 Check Prometheus for raw metrics:');
  console.log('   - pgbouncer_pools_sv_active (should be < 50)');
  console.log('   - pgbouncer_pools_cl_active (can be 200+)');
  console.log('   - postgresql_connections (should be ~50 total)');
}
