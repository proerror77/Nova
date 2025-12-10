# ICE Servers API Testing Guide

**Endpoint**: `GET /api/calls/ice-servers`
**Authentication**: Required (Bearer token)
**Purpose**: Returns TURN/STUN server configuration for WebRTC ICE

## Quick Test

### 1. Using curl

```bash
# Replace $TOKEN with actual JWT token
curl -H "Authorization: Bearer $TOKEN" \
     http://localhost:3000/api/calls/ice-servers
```

### 2. Expected Response

```json
{
  "iceServers": [
    {
      "urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]
    },
    {
      "urls": ["turn:turn.example.com:3478"],
      "username": "testuser",
      "credential": "testpass",
      "credentialType": "password"
    }
  ],
  "iceTransportPolicy": "all",
  "ttlSeconds": 86400
}
```

### 3. Environment Configuration

Set these environment variables to configure TURN/STUN servers:

```bash
# STUN servers (comma-separated)
export RTC_STUN_URLS="stun:stun.l.google.com:19302,stun:stun1.l.google.com:19302"

# TURN servers (comma-separated)
export RTC_TURN_URLS="turn:turn.example.com:3478,turn:turn.example.com:3479"

# TURN authentication
export RTC_TURN_USERNAME="your-username"
export RTC_TURN_PASSWORD="your-password"
export RTC_TURN_CREDENTIAL_TYPE="password"  # or "oauth"

# ICE credential TTL (default: 86400 = 24 hours)
export ICE_TTL_SECONDS=86400
```

### 4. Default Behavior

If no `RTC_TURN_URLS` is set, only STUN servers will be returned:

```json
{
  "iceServers": [
    {
      "urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]
    }
  ],
  "iceTransportPolicy": "all",
  "ttlSeconds": 86400
}
```

## WebRTC Client Integration

### JavaScript Example

```javascript
async function getICEServers() {
  const response = await fetch('/api/calls/ice-servers', {
    headers: {
      'Authorization': `Bearer ${userToken}`
    }
  });

  const config = await response.json();
  return config;
}

// Use with RTCPeerConnection
const iceConfig = await getICEServers();
const peerConnection = new RTCPeerConnection(iceConfig);
```

### React Example

```jsx
import { useEffect, useState } from 'react';

function useICEServers() {
  const [iceConfig, setIceConfig] = useState(null);

  useEffect(() => {
    async function fetchICEServers() {
      const response = await fetch('/api/calls/ice-servers', {
        headers: {
          'Authorization': `Bearer ${localStorage.getItem('token')}`
        }
      });
      const config = await response.json();
      setIceConfig(config);
    }

    fetchICEServers();
  }, []);

  return iceConfig;
}

// In component
function VideoCall() {
  const iceConfig = useICEServers();

  const startCall = async () => {
    if (!iceConfig) return;

    const pc = new RTCPeerConnection(iceConfig);
    // ... setup call
  };

  // ...
}
```

## Production Setup

### TURN Server Deployment

For production, deploy your own TURN server (e.g., coturn):

```bash
# Install coturn
apt-get install coturn

# Edit /etc/turnserver.conf
listening-port=3478
fingerprint
use-auth-secret
static-auth-secret=your-secret-key
realm=turn.yourdomain.com
total-quota=100
stale-nonce=600
cert=/etc/letsencrypt/live/turn.yourdomain.com/cert.pem
pkey=/etc/letsencrypt/live/turn.yourdomain.com/privkey.pem

# Start coturn
systemctl start coturn
```

Then configure environment:

```bash
export RTC_TURN_URLS="turn:turn.yourdomain.com:3478"
export RTC_TURN_USERNAME="your-username"
export RTC_TURN_PASSWORD="your-secret-key"
```

### Google STUN Servers (Free)

Default configuration uses Google's public STUN servers:
- `stun:stun.l.google.com:19302`
- `stun:stun1.l.google.com:19302`

These are free but have rate limits. For production, consider:
- Running your own STUN server
- Using a commercial TURN/STUN provider (Twilio, Agora, etc.)

## Testing Checklist

- [ ] Default STUN servers work without configuration
- [ ] Custom STUN servers can be configured via `RTC_STUN_URLS`
- [ ] TURN servers appear when `RTC_TURN_URLS` is set
- [ ] TURN credentials are included correctly
- [ ] `ttlSeconds` matches `ICE_TTL_SECONDS` environment variable
- [ ] Authentication is enforced (401 without token)
- [ ] Response time is < 100ms

## Integration with Matrix VoIP

This endpoint is used by both:

1. **WebSocket-based calls** (current implementation)
   - Client fetches ICE servers
   - Exchanges SDP and ICE candidates via WebSocket
   - No Matrix integration

2. **Matrix VoIP calls** (future with SDK 0.16)
   - Client fetches ICE servers
   - ICE servers included in `m.call.invite` event
   - SDP and ICE candidates relayed via Matrix E2EE

## Monitoring

Key metrics to track:

```prometheus
# Request count
http_requests_total{endpoint="/api/calls/ice-servers"}

# Response time
http_request_duration_seconds{endpoint="/api/calls/ice-servers"}

# Error rate
http_requests_errors_total{endpoint="/api/calls/ice-servers"}
```

## Troubleshooting

### Issue: Empty `iceServers` array

**Cause**: Both `RTC_STUN_URLS` and `RTC_TURN_URLS` are empty

**Fix**: Set at least `RTC_STUN_URLS` environment variable

### Issue: TURN servers not appearing

**Cause**: `RTC_TURN_URLS` not set or `RTC_TURN_USERNAME`/`RTC_TURN_PASSWORD` missing

**Fix**: Set all three environment variables:
```bash
export RTC_TURN_URLS="turn:..."
export RTC_TURN_USERNAME="..."
export RTC_TURN_PASSWORD="..."
```

### Issue: 401 Unauthorized

**Cause**: Missing or invalid JWT token

**Fix**: Include valid Bearer token in `Authorization` header

## Related Documentation

- [CALL_SERVICE_MATRIX_INTEGRATION.md](./CALL_SERVICE_MATRIX_INTEGRATION.md) - Matrix VoIP integration plan
- [MATRIX_VOIP_DESIGN.md](./MATRIX_VOIP_DESIGN.md) - Overall VoIP architecture
- [WebRTC ICE Specification](https://datatracker.ietf.org/doc/html/rfc8445) - ICE protocol details
