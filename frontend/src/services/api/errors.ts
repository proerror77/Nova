/**
 * Error Handling System for Nova Frontend
 * Provides typed error classes, retry logic, and error classification
 */

import axios, { AxiosError } from 'axios';

// ============================================
// Error Types and Classification
// ============================================

/** Categorized error types */
export enum ErrorType {
  // Network errors
  NETWORK_ERROR = 'NETWORK_ERROR',
  TIMEOUT = 'TIMEOUT',

  // Client errors (4xx)
  BAD_REQUEST = 'BAD_REQUEST',
  UNAUTHORIZED = 'UNAUTHORIZED',
  FORBIDDEN = 'FORBIDDEN',
  NOT_FOUND = 'NOT_FOUND',
  CONFLICT = 'CONFLICT',
  VALIDATION_ERROR = 'VALIDATION_ERROR',

  // Server errors (5xx)
  SERVER_ERROR = 'SERVER_ERROR',
  SERVICE_UNAVAILABLE = 'SERVICE_UNAVAILABLE',

  // Other errors
  UNKNOWN_ERROR = 'UNKNOWN_ERROR',
  ABORT_ERROR = 'ABORT_ERROR',
}

/** HTTP error response structure from backend */
export interface ErrorResponse {
  error: string;
  details?: string;
  status?: number;
}

/** Nova API Error - typed error wrapper */
export class NovaAPIError extends Error {
  public readonly type: ErrorType;
  public readonly statusCode?: number;
  public readonly details?: string;
  public readonly originalError?: Error;
  public readonly isRetryable: boolean;

  constructor(
    type: ErrorType,
    message: string,
    options?: {
      statusCode?: number;
      details?: string;
      originalError?: Error;
    }
  ) {
    super(message);
    this.name = 'NovaAPIError';
    this.type = type;
    this.statusCode = options?.statusCode;
    this.details = options?.details;
    this.originalError = options?.originalError;
    this.isRetryable = isRetryableError(type);

    // Maintain prototype chain for instanceof checks
    Object.setPrototypeOf(this, NovaAPIError.prototype);
  }

  toJSON() {
    return {
      name: this.name,
      type: this.type,
      message: this.message,
      statusCode: this.statusCode,
      details: this.details,
      isRetryable: this.isRetryable,
    };
  }
}

// ============================================
// Error Classifiers
// ============================================

/**
 * Determine if error is retryable (transient)
 */
export function isRetryableError(errorType: ErrorType): boolean {
  const retryableErrors = new Set([
    ErrorType.NETWORK_ERROR,
    ErrorType.TIMEOUT,
    ErrorType.SERVICE_UNAVAILABLE,
    // 408 Request Timeout
    // 429 Too Many Requests (rate limit)
  ]);
  return retryableErrors.has(errorType);
}

/**
 * Classify HTTP status code to error type
 */
function classifyStatusCode(status: number): ErrorType {
  if (status >= 400 && status < 500) {
    if (status === 400) return ErrorType.BAD_REQUEST;
    if (status === 401) return ErrorType.UNAUTHORIZED;
    if (status === 403) return ErrorType.FORBIDDEN;
    if (status === 404) return ErrorType.NOT_FOUND;
    if (status === 409) return ErrorType.CONFLICT;
    if (status === 408 || status === 429) return ErrorType.TIMEOUT;
    return ErrorType.BAD_REQUEST;
  }

  if (status >= 500 && status < 600) {
    if (status === 503 || status === 504) return ErrorType.SERVICE_UNAVAILABLE;
    return ErrorType.SERVER_ERROR;
  }

  return ErrorType.UNKNOWN_ERROR;
}

/**
 * Convert AxiosError to NovaAPIError
 */
export function axiosErrorToNovaError(error: AxiosError<ErrorResponse>): NovaAPIError {
  const status = error.response?.status;
  const data = error.response?.data;
  const message = data?.error || error.message || 'Unknown error';
  const details = data?.details;

  let errorType: ErrorType;

  if (!error.response) {
    // Network error, timeout, or abort
    if (error.code === 'ECONNABORTED') {
      errorType = ErrorType.TIMEOUT;
    } else if (error.code === 'ERR_CANCELED') {
      errorType = ErrorType.ABORT_ERROR;
    } else if (
      error.message.includes('Network') ||
      error.code === 'ERR_NETWORK'
    ) {
      errorType = ErrorType.NETWORK_ERROR;
    } else {
      errorType = ErrorType.UNKNOWN_ERROR;
    }
  } else {
    errorType = classifyStatusCode(status || 500);
  }

  return new NovaAPIError(errorType, message, {
    statusCode: status,
    details,
    originalError: error,
  });
}

/**
 * Convert any error to NovaAPIError
 */
export function toNovaError(error: unknown): NovaAPIError {
  if (error instanceof NovaAPIError) {
    return error;
  }

  if (axios.isAxiosError(error)) {
    return axiosErrorToNovaError(error as AxiosError<ErrorResponse>);
  }

  if (error instanceof Error) {
    return new NovaAPIError(ErrorType.UNKNOWN_ERROR, error.message, {
      originalError: error,
    });
  }

  return new NovaAPIError(
    ErrorType.UNKNOWN_ERROR,
    'An unexpected error occurred',
    {
      originalError: new Error(String(error)),
    }
  );
}

// ============================================
// User-Friendly Error Messages
// ============================================

/**
 * Generate user-friendly error message from error type
 */
export function getUserFriendlyMessage(error: NovaAPIError): string {
  switch (error.type) {
    case ErrorType.NETWORK_ERROR:
      return 'Network connection error. Please check your internet connection and try again.';

    case ErrorType.TIMEOUT:
      return 'Request timed out. Please try again.';

    case ErrorType.UNAUTHORIZED:
      return 'Authentication failed. Please log in again.';

    case ErrorType.FORBIDDEN:
      return 'You do not have permission to perform this action.';

    case ErrorType.NOT_FOUND:
      return 'The requested resource was not found.';

    case ErrorType.CONFLICT:
      return 'This action conflicts with existing data. Please refresh and try again.';

    case ErrorType.VALIDATION_ERROR:
    case ErrorType.BAD_REQUEST:
      return error.details || 'The request was invalid. Please check your input.';

    case ErrorType.SERVICE_UNAVAILABLE:
      return 'The service is temporarily unavailable. Please try again later.';

    case ErrorType.SERVER_ERROR:
      return 'Server error. Please try again later.';

    case ErrorType.ABORT_ERROR:
      return 'Request was cancelled.';

    case ErrorType.UNKNOWN_ERROR:
    default:
      return 'An unexpected error occurred. Please try again.';
  }
}

// ============================================
// Error Context for Logging
// ============================================

export interface ErrorContext {
  requestUrl?: string;
  requestMethod?: string;
  timestamp: number;
  userAgent?: string;
  userId?: string;
}

export function createErrorContext(userId?: string): ErrorContext {
  return {
    timestamp: Date.now(),
    userAgent: typeof navigator !== 'undefined' ? navigator.userAgent : undefined,
    userId,
  };
}

/**
 * Log error with context
 */
export function logError(
  error: NovaAPIError,
  context?: ErrorContext
): void {
  const timestamp = new Date(context?.timestamp || Date.now()).toISOString();

  const logData = {
    timestamp,
    type: error.type,
    message: error.message,
    statusCode: error.statusCode,
    details: error.details,
    url: context?.requestUrl,
    method: context?.requestMethod,
    userId: context?.userId,
    isRetryable: error.isRetryable,
  };

  // Log to console in development
  if (process.env.NODE_ENV !== 'production') {
    console.error('[NovaAPI Error]', logData);
  }

  // In production, you would send this to your error tracking service
  // Example: Sentry.captureException(error, { contexts: { api: logData } });

  // For now, store in localStorage for debugging
  try {
    const errors = JSON.parse(localStorage.getItem('nova_api_errors') || '[]');
    errors.push(logData);
    // Keep only last 50 errors
    localStorage.setItem('nova_api_errors', JSON.stringify(errors.slice(-50)));
  } catch {
    // Ignore localStorage errors
  }
}
