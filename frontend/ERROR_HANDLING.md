# Frontend API Error Handling System

## Overview

Comprehensive error handling system for the Nova frontend featuring:
- **Type-safe error classes** with detailed error information
- **Automatic retry logic** with exponential backoff for transient failures
- **Centralized API client** with interceptors for authentication and error handling
- **Error store** for state management and UI notifications
- **User-friendly error messages** for different error scenarios
- **Error logging and debugging** with localStorage persistence

## Key Components

### 1. Error Types (`services/api/errors.ts`)

Defines typed error classes and error classification:

```typescript
// Error type enum
enum ErrorType {
  NETWORK_ERROR,
  TIMEOUT,
  UNAUTHORIZED,
  FORBIDDEN,
  NOT_FOUND,
  VALIDATION_ERROR,
  SERVER_ERROR,
  SERVICE_UNAVAILABLE,
  UNKNOWN_ERROR,
}

// Main error class
class NovaAPIError extends Error {
  type: ErrorType;
  statusCode?: number;
  details?: string;
  isRetryable: boolean;
}
```

**Key Functions:**
- `axiosErrorToNovaError()` - Convert Axios errors to typed errors
- `toNovaError()` - Convert any error to NovaAPIError
- `isRetryableError()` - Determine if error should be retried
- `getUserFriendlyMessage()` - Generate user-facing error messages
- `logError()` - Log error with context to localStorage and console

### 2. API Client (`services/api/client.ts`)

Centralized axios instance with automatic retry:

```typescript
// Usage
const client = new NovaAPIClient(baseURL);

// Automatic retry with exponential backoff
const data = await client.get<T>('/api/endpoint');
```

**Features:**
- Request interceptors for auth token injection
- Response interceptors for global error handling
- Automatic retry with configurable backoff
- Request timeout (30s default)
- OAuth/401 handling

**Retry Configuration:**
```typescript
{
  maxRetries: 3,           // Default: 3 attempts
  initialDelayMs: 500,     // First retry after 500ms
  maxDelayMs: 10000,       // Cap delay at 10 seconds
  backoffMultiplier: 2,    // Exponential: 500ms, 1s, 2s
  backoffJitter: true,     // Add randomness to prevent thundering herd
}
```

### 3. Error Store (`services/api/errorStore.ts`)

Zustand-based state management for error notifications:

```typescript
// Add error to store
useErrorStore.getState().addError(error, 5000); // Auto-hide after 5s

// Get active errors
const { errors, lastError } = useErrors();

// Dismiss specific error
dismissError(id);

// Clear all errors
clearErrors();
```

**Specialized Error Handlers:**
- `handleAuthenticationError()` - Logout and redirect
- `handleValidationError()` - Format validation details
- `handleRateLimitError()` - Show retry timing
- `handleOfflineError()` - Special offline handling

### 4. Error Notification Component (`components/ErrorNotification.tsx`)

React component for displaying error notifications:

```typescript
// In your app root
<ErrorNotificationContainer maxNotifications={5} />
```

**Features:**
- Auto-dismissing notifications
- Retry buttons for retryable errors
- Recovery action buttons
- Responsive mobile design
- Smooth animations
- Error type color coding

## Usage Examples

### Basic API Call with Error Handling

```typescript
import { apiClient } from '@/services/api/client';
import { useErrorStore } from '@/services/api/errorStore';

async function fetchUserData(userId: string) {
  try {
    const response = await apiClient.get<UserData>(`/api/users/${userId}`);
    return response;
  } catch (error) {
    // Error already logged and added to error store
    // UI components automatically see the error
    console.error('Failed to fetch user:', error);
    throw error;
  }
}
```

### Photo Upload with Progress and Error Handling

```typescript
import { uploadPhoto } from '@/services/api/postService';

async function handlePhotoUpload(file: File) {
  try {
    const postId = await uploadPhoto(
      file,
      caption,
      (progress) => setProgress(progress) // 0-100
    );

    console.log('Photo uploaded:', postId);
    // Success - no error notification shown
  } catch (error) {
    // Error automatically in error store and shown to user
    // No need for manual error handling
  }
}
```

### Custom Error Handling

```typescript
import { NovaAPIError, ErrorType } from '@/services/api/errors';
import { useErrorStore } from '@/services/api/errorStore';

try {
  // API call
} catch (error) {
  if (error instanceof NovaAPIError) {
    if (error.type === ErrorType.UNAUTHORIZED) {
      // Handle auth errors specifically
      localStorage.removeItem('auth_token');
    } else if (error.isRetryable) {
      // Automatically retried by client, but you can handle it
      console.log('Will retry:', error.message);
    }
  }

  // Add to error store for UI
  useErrorStore.getState().addError(error);
}
```

### Error Types and Recovery

```typescript
import { isErrorRecoverable, getErrorRecoveryAction } from '@/services/api/errorStore';

const error = /* ... */;

if (isErrorRecoverable(error)) {
  // Show retry button
  <button onClick={() => retryOperation()}>Retry</button>
}

const recovery = getErrorRecoveryAction(error);
if (recovery) {
  // Show action button
  <button onClick={() => recovery.action()}>{recovery.label}</button>
}
```

## Error Flow

### Successful Request
```
Request
  ↓
Interceptor adds auth token
  ↓
Response (200)
  ↓
Return data
```

### Failed Retryable Request (Network Error)
```
Request
  ↓
Network error (no response)
  ↓
Retry attempt 1 (wait 500ms)
  ↓
Network error
  ↓
Retry attempt 2 (wait 1000ms)
  ↓
Network error
  ↓
Retry attempt 3 (wait 2000ms)
  ↓
Success or fail after max retries
  ↓
Throw error, log to localStorage
  ↓
Error store receives error
  ↓
UI components display notification
```

### Failed Non-Retryable Request (401 Unauthorized)
```
Request
  ↓
Response 401
  ↓
Create NovaAPIError (ErrorType.UNAUTHORIZED)
  ↓
Global interceptor calls onUnauthorized callback
  ↓
Clear auth token from localStorage
  ↓
Throw error
  ↓
Error handler catches and adds to error store
  ↓
UI shows "Authentication failed. Please log in again."
```

## Debugging

### View Recent Errors

```javascript
// In browser console
JSON.parse(localStorage.getItem('nova_api_errors'))
// Shows last 50 errors with full context
```

Each error log includes:
- Timestamp
- Error type and message
- HTTP status code
- Request URL and method
- User ID (if available)
- Whether error is retryable

### Production Error Monitoring

The system is prepared for integration with error tracking services:

```typescript
// In logError() function, add:
import * as Sentry from "@sentry/react";

Sentry.captureException(error, {
  contexts: {
    api: logData
  },
  tags: {
    errorType: error.type,
    isRetryable: error.isRetryable,
  }
});
```

## Configuration

### Setting Error Context

```typescript
apiClient.setErrorContext({
  userId: currentUser.id,
  customField: 'value'
});
```

### Custom Retry Configuration

```typescript
// Retry a specific request with different settings
await apiClient.post(url, data, {}, {
  maxRetries: 5,
  initialDelayMs: 1000,
  backoffMultiplier: 1.5,
});
```

### Custom Auth Handler

```typescript
const client = new NovaAPIClient(baseURL, {}, () => {
  // Custom logout logic
  dispatch(logoutUser());
  navigate('/login');
});
```

## Best Practices

1. **Always use apiClient** for HTTP requests to benefit from retry and error handling
2. **Don't catch all errors silently** - let errors flow to error store for user notification
3. **Add error context** when possible for better debugging
4. **Use offline queue** for messaging when network is down
5. **Implement retry UI** for user-initiated actions that failed
6. **Log errors** with context for monitoring and debugging
7. **Validate input** before sending to reduce validation errors
8. **Handle 401/403** differently from other errors (auth vs permissions)

## Related Systems

- **Offline Queue** (`services/offlineQueue/Queue.ts`) - Persists messages when offline
- **WebSocket Client** (`services/websocket/WebSocketClient.ts`) - Real-time messaging
- **Messaging Store** (`stores/messagingStore.ts`) - Uses error handling system

## Migration Guide

### From Old postService to New

**Before:**
```typescript
try {
  const result = await axios.post(url, data, createAuthConfig());
} catch (error) {
  if (axios.isAxiosError(error)) {
    throw new Error(error.response?.data?.error || 'Failed');
  }
}
```

**After:**
```typescript
try {
  const result = await apiClient.post(url, data);
} catch (error) {
  // Already typed, logged, and in error store
  // Just re-throw or handle specifically
}
```

## Testing

### Mock Error Scenarios

```typescript
import { NovaAPIError, ErrorType } from '@/services/api/errors';

// Create test errors
const networkError = new NovaAPIError(
  ErrorType.NETWORK_ERROR,
  'Network failed'
);

const validationError = new NovaAPIError(
  ErrorType.VALIDATION_ERROR,
  'Validation failed',
  { details: 'email: Invalid format' }
);

// Add to store for testing UI
useErrorStore.getState().addError(networkError);
```

## Summary

This error handling system provides:
✅ **Type-safe** error handling across the frontend
✅ **Automatic retry** for transient failures
✅ **User-friendly** error messages
✅ **Production-ready** error logging
✅ **Easy integration** with existing code
✅ **Debugging support** with localStorage persistence
