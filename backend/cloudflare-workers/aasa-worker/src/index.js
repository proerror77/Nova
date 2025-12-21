/**
 * ICERED Apple App Site Association (AASA) Worker
 *
 * Serves the AASA file for Passkey/WebAuthn and Universal Links
 * Deployed at: icered.com and app.icered.com
 */

const AASA_CONTENT = {
  "webcredentials": {
    "apps": ["2C77AZCA8W.com.libruce.icered"]
  },
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "2C77AZCA8W.com.libruce.icered",
        "paths": [
          "/reset-password/*",
          "/verify/*",
          "/invite/*",
          "/callback/*",
          "/auth/*"
        ]
      }
    ]
  }
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Handle AASA requests
    if (url.pathname === '/.well-known/apple-app-site-association' ||
        url.pathname === '/apple-app-site-association') {
      return new Response(JSON.stringify(AASA_CONTENT), {
        status: 200,
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'public, max-age=3600',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
        }
      });
    }

    // Handle OPTIONS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, OPTIONS',
          'Access-Control-Max-Age': '86400',
        }
      });
    }

    // For all other requests, pass through to origin
    // This allows the Worker to coexist with other routes
    return fetch(request);
  },
};
