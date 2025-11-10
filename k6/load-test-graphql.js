/**
 * k6 Load Testing Scenarios for GraphQL Gateway
 * ✅ P0-5: Performance testing and capacity planning
 *
 * Run with:
 *   k6 run load-test-graphql.js
 *   k6 run load-test-graphql.js --vus 100 --duration 1m
 */

import http from 'k6/http';
import { check, sleep, group } from 'k6';
import { Rate, Trend, Counter, Gauge } from 'k6/metrics';

// ============================================================================
// CUSTOM METRICS
// ============================================================================

// Response time percentiles
const responseTimeP95 = new Trend('response_time_p95', true);
const responseTimeP99 = new Trend('response_time_p99', true);

// Success/failure rates
const successRate = new Rate('success_rate');
const errorRate = new Rate('error_rate');
const queryComplexityViolations = new Counter('query_complexity_violations');
const backpressureTriggered = new Counter('backpressure_triggered');

// Active subscriptions
const activeSubscriptions = new Gauge('active_subscriptions');

// ============================================================================
// CONFIGURATION
// ============================================================================

export const options = {
  stages: [
    // Ramp up 100 users over 30 seconds
    { duration: '30s', target: 100 },
    // Stay at 100 users for 2 minutes
    { duration: '2m', target: 100 },
    // Ramp up to 500 users over 1 minute
    { duration: '1m', target: 500 },
    // Stress test: 1000 users
    { duration: '2m', target: 1000 },
    // Ramp down
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
    http_req_failed: ['rate<0.1'],
    success_rate: ['rate>0.95'],
  },
};

// ============================================================================
// TEST SETUP
// ============================================================================

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const GRAPHQL_ENDPOINT = `${BASE_URL}/graphql`;
const WS_ENDPOINT = __ENV.WS_ENDPOINT || 'ws://localhost:8000/graphql';

// Test data
const USER_IDS = Array.from({ length: 100 }, (_, i) => `user_${i + 1}`);
const POST_IDS = Array.from({ length: 500 }, (_, i) => `post_${i + 1}`);

// ============================================================================
// QUERY TEMPLATES
// ============================================================================

function getSimpleQueryTest() {
  return {
    name: 'Simple Query (Low Complexity)',
    query: `{
      user(id: "user_1") {
        id
        username
      }
    }`,
  };
}

function getMediumComplexityQuery() {
  return {
    name: 'Medium Complexity (Pagination)',
    query: `{
      posts(first: 20) {
        edges {
          node {
            id
            content
            likeCount
          }
        }
        pageInfo {
          hasNextPage
          endCursor
        }
      }
    }`,
  };
}

function getHighComplexityQuery() {
  return {
    name: 'High Complexity (Nested Pagination)',
    query: `{
      posts(first: 50) {
        edges {
          node {
            id
            content
            comments(first: 10) {
              edges {
                node {
                  id
                  content
                }
              }
            }
            likeCount
          }
        }
      }
    }`,
  };
}

function getExtremeComplexityQuery() {
  return {
    name: 'Extreme Complexity (DoS Test)',
    query: `{
      posts(first: 100) {
        edges {
          node {
            id
            comments(first: 50) {
              edges {
                node {
                  id
                  content
                }
              }
            }
          }
        }
      }
    }`,
  };
}

// ============================================================================
// HTTP REQUEST FUNCTIONS
// ============================================================================

function executeQuery(query, name) {
  const response = http.post(
    GRAPHQL_ENDPOINT,
    JSON.stringify({ query }),
    {
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${__ENV.AUTH_TOKEN || 'demo_token'}`,
      },
    }
  );

  // Record metrics
  const duration = response.timings.duration;
  responseTimeP95.add(duration);
  responseTimeP99.add(duration);

  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'has data': (r) => r.body.includes('data'),
    'no errors': (r) => !r.body.includes('errors'),
    [`${name} passed`]: (r) => r.status === 200,
  });

  if (success) {
    successRate.add(true);
  } else {
    successRate.add(false);
    errorRate.add(true);

    // Check for complexity violations
    if (response.body.includes('complexity')) {
      queryComplexityViolations.add(1);
    }

    // Check for backpressure
    if (response.status === 429) {
      backpressureTriggered.add(1);
    }
  }

  return response;
}

// ============================================================================
// TEST SCENARIOS
// ============================================================================

export default function () {
  const userId = USER_IDS[Math.floor(Math.random() * USER_IDS.length)];
  const postId = POST_IDS[Math.floor(Math.random() * POST_IDS.length)];

  group('GraphQL Performance Tests', () => {
    // Test 1: Simple query (baseline)
    const simple = getSimpleQueryTest();
    executeQuery(simple.query, simple.name);
    sleep(1);

    // Test 2: Medium complexity (pagination)
    const medium = getMediumComplexityQuery();
    executeQuery(medium.query, medium.name);
    sleep(1);

    // Test 3: High complexity (nested pagination)
    const high = getHighComplexityQuery();
    executeQuery(high.query, high.name);
    sleep(1);

    // Test 4: Extreme complexity (for stress testing)
    const extreme = getExtremeComplexityQuery();
    executeQuery(extreme.query, extreme.name);
    sleep(2);

    // Test 5: Concurrent requests simulation
    group('Concurrent Request Test', () => {
      const requests = {
        'query_simple': {
          method: 'POST',
          url: GRAPHQL_ENDPOINT,
          body: JSON.stringify({ query: getSimpleQueryTest().query }),
          params: {
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${__ENV.AUTH_TOKEN || 'demo_token'}`,
            },
          },
        },
        'query_medium': {
          method: 'POST',
          url: GRAPHQL_ENDPOINT,
          body: JSON.stringify({ query: getMediumComplexityQuery().query }),
          params: {
            headers: {
              'Content-Type': 'application/json',
              'Authorization': `Bearer ${__ENV.AUTH_TOKEN || 'demo_token'}`,
            },
          },
        },
      };

      const responses = http.batch(requests);
      responses.forEach((response) => {
        check(response, {
          'concurrent request successful': (r) => r.status === 200,
        });
      });
    });

    sleep(1);
  });
}

// ============================================================================
// SUBSCRIPTION TEST (requires WebSocket support)
// ============================================================================

export function handleSummary(data) {
  return {
    'stdout': textSummary(data, { indent: ' ', enableColors: true }),
    '/tmp/k6-summary.json': JSON.stringify(data),
  };
}

/**
 * Usage Examples:
 *
 * # Run with default settings (10 VUs, 30s)
 * k6 run load-test-graphql.js
 *
 * # Run with custom VUs and duration
 * k6 run -u 100 -d 5m load-test-graphql.js
 *
 * # Run with custom base URL
 * BASE_URL=http://staging.example.com k6 run load-test-graphql.js
 *
 * # Run with authentication token
 * AUTH_TOKEN=your_token k6 run load-test-graphql.js
 *
 * # Run with detailed output
 * k6 run --verbose load-test-graphql.js
 *
 * # Run and save results
 * k6 run -o json=results.json load-test-graphql.js
 */
