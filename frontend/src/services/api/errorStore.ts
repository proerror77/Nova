/**
 * Error Notification Store
 * Manages error state and notifications for UI components
 */

import { create } from 'zustand';
import { NovaAPIError, getUserFriendlyMessage, ErrorType } from './errors';

// ============================================
// Types
// ============================================

export interface ErrorNotification {
  id: string;
  error: NovaAPIError;
  message: string; // User-friendly message
  timestamp: number;
  dismissed: boolean;
  autoHideMs?: number; // If set, auto-hide after this duration
}

export interface ErrorNotificationState {
  notifications: ErrorNotification[];
  lastError: NovaAPIError | null;
  dismissTimers: Map<string, NodeJS.Timeout>; // Track timers for cleanup

  // Actions
  addError: (error: NovaAPIError, autoHideMs?: number) => void;
  dismissError: (id: string) => void;
  clearErrors: () => void;
  getActiveErrors: () => ErrorNotification[];
}

// ============================================
// Store Implementation
// ============================================

export const useErrorStore = create<ErrorNotificationState>((set, get) => ({
  notifications: [],
  lastError: null,
  dismissTimers: new Map(),

  addError: (error: NovaAPIError, autoHideMs = 5000) => {
    const id = crypto.randomUUID();
    const message = getUserFriendlyMessage(error);

    set((state) => ({
      notifications: [
        ...state.notifications,
        {
          id,
          error,
          message,
          timestamp: Date.now(),
          dismissed: false,
          autoHideMs,
        },
      ],
      lastError: error,
    }));

    // Auto-dismiss if configured
    if (autoHideMs > 0) {
      const timer = setTimeout(() => {
        get().dismissError(id);
      }, autoHideMs);

      // Store timer for cleanup
      get().dismissTimers.set(id, timer);
    }
  },

  dismissError: (id: string) => {
    // Clear any pending timer
    const timer = get().dismissTimers.get(id);
    if (timer) {
      clearTimeout(timer);
      get().dismissTimers.delete(id);
    }

    // Remove dismissed notification instead of just marking it
    set((state) => ({
      notifications: state.notifications.filter((n) => n.id !== id),
    }));
  },

  clearErrors: () => {
    // Clear all timers
    const timers = get().dismissTimers;
    timers.forEach((timer) => clearTimeout(timer));
    timers.clear();

    set({ notifications: [], lastError: null });
  },

  getActiveErrors: () => {
    return get().notifications.filter((n) => !n.dismissed);
  },
}));

// ============================================
// Error Specific Notifications
// ============================================

/**
 * Add authentication error and trigger logout
 */
export function handleAuthenticationError(error: NovaAPIError): void {
  useErrorStore.getState().addError(error, 0); // Don't auto-hide
  localStorage.removeItem('auth_token');
  // In real app: window.location.href = '/login';
}

/**
 * Handle validation error with specific details
 */
export function handleValidationError(
  details: Record<string, string>
): void {
  const detailsStr = Object.entries(details)
    .map(([field, msg]) => `${field}: ${msg}`)
    .join('; ');

  const error = new NovaAPIError(ErrorType.VALIDATION_ERROR, 'Validation failed', {
    details: detailsStr,
  });

  useErrorStore.getState().addError(error);
}

/**
 * Handle rate limit error with retry hint
 */
export function handleRateLimitError(retryAfterMs?: number): void {
  const message = retryAfterMs
    ? `Too many requests. Please wait ${Math.ceil(retryAfterMs / 1000)} seconds before trying again.`
    : 'Too many requests. Please try again later.';

  // Use SERVER_ERROR for 429 rate limit (distinct from TIMEOUT)
  const error = new NovaAPIError(ErrorType.SERVER_ERROR, message, {
    statusCode: 429,
    details: 'Rate limit exceeded',
  });
  useErrorStore.getState().addError(error, retryAfterMs ? 0 : 5000);
}

/**
 * Handle offline errors specifically
 */
export function handleOfflineError(): void {
  const error = new NovaAPIError(
    ErrorType.NETWORK_ERROR,
    'You are offline. Changes will be synced when you reconnect.',
    { details: 'Check your internet connection' }
  );
  useErrorStore.getState().addError(error, 0); // Don't auto-hide
}

/**
 * Hook for components to use error store
 */
export function useErrors() {
  const state = useErrorStore();
  return {
    errors: state.getActiveErrors(),
    lastError: state.lastError,
    dismissError: state.dismissError,
    clearErrors: state.clearErrors,
  };
}

// ============================================
// Error Recovery Helpers
// ============================================

/**
 * Check if error is recoverable (user can retry)
 */
export function isErrorRecoverable(error: NovaAPIError): boolean {
  return error.isRetryable || error.type === ErrorType.BAD_REQUEST;
}

/**
 * Get error recovery action
 */
export function getErrorRecoveryAction(
  error: NovaAPIError
): { label: string; action: () => void } | null {
  if (error.type === ErrorType.UNAUTHORIZED) {
    return {
      label: 'Login again',
      action: () => {
        localStorage.removeItem('auth_token');
        // window.location.href = '/login';
      },
    };
  }

  if (error.type === ErrorType.FORBIDDEN) {
    return {
      label: 'Go back',
      action: () => {
        // window.history.back();
      },
    };
  }

  // Retryable errors typically don't need explicit action as they retry automatically
  return null;
}
