/**
 * Centralized API Client with Retry Logic and Error Handling
 * Provides automatic retry with exponential backoff for transient failures
 */

import axios, { AxiosInstance, AxiosError, AxiosRequestConfig } from 'axios';
import {
  NovaAPIError,
  axiosErrorToNovaError,
  toNovaError,
  ErrorType,
  isRetryableError,
  logError,
  createErrorContext,
  ErrorContext,
} from './errors';

// ============================================
// Retry Configuration
// ============================================

export interface RetryConfig {
  maxRetries: number;
  initialDelayMs: number;
  maxDelayMs: number;
  backoffMultiplier: number;
  backoffJitter: boolean;
}

const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxRetries: 3,
  initialDelayMs: 500, // 500ms
  maxDelayMs: 10000, // 10s
  backoffMultiplier: 2,
  backoffJitter: true,
};

/**
 * Calculate delay for exponential backoff with jitter
 */
function calculateBackoffDelay(
  attempt: number,
  config: RetryConfig
): number {
  let delay = config.initialDelayMs * Math.pow(config.backoffMultiplier, attempt - 1);
  delay = Math.min(delay, config.maxDelayMs);

  if (config.backoffJitter) {
    // Add random jitter: delay * (0.5 to 1.0)
    delay = delay * (0.5 + Math.random() * 0.5);
  }

  return Math.round(delay);
}

// ============================================
// API Client Class
// ============================================

export class NovaAPIClient {
  private instance: AxiosInstance;
  private retryConfig: RetryConfig;
  private errorContext?: ErrorContext;
  private onUnauthorized?: () => void;

  constructor(
    baseURL: string,
    retryConfig: Partial<RetryConfig> = {},
    onUnauthorized?: () => void
  ) {
    this.retryConfig = { ...DEFAULT_RETRY_CONFIG, ...retryConfig };
    this.onUnauthorized = onUnauthorized;

    this.instance = axios.create({
      baseURL,
      timeout: 30000, // 30 second timeout
    });

    this.setupInterceptors();
  }

  /**
   * Setup request/response interceptors
   */
  private setupInterceptors(): void {
    // Request interceptor - add auth token
    this.instance.interceptors.request.use(
      (config) => {
        const token = this.getAuthToken();
        if (token && config.headers) {
          config.headers.Authorization = `Bearer ${token}`;
        }
        return config;
      },
      (error) => Promise.reject(error)
    );

    // Response interceptor - handle errors globally
    this.instance.interceptors.response.use(
      (response) => response,
      (error: AxiosError) => {
        // Handle 401 Unauthorized globally
        if (error.response?.status === 401) {
          this.onUnauthorized?.();
        }
        return Promise.reject(error);
      }
    );
  }

  /**
   * Get auth token from localStorage
   */
  private getAuthToken(): string | null {
    try {
      return localStorage.getItem('auth_token') || null;
    } catch {
      return null;
    }
  }

  /**
   * Set error context for logging
   */
  setErrorContext(context: Partial<ErrorContext>): void {
    this.errorContext = {
      ...createErrorContext(context.userId),
      ...context,
    };
  }

  /**
   * Log error with request context
   */
  private logErrorWithContext(
    error: NovaAPIError,
    method: string,
    url: string
  ): void {
    if (this.errorContext) {
      this.errorContext.requestUrl = url;
      this.errorContext.requestMethod = method;
      logError(error, this.errorContext);
    }
  }

  /**
   * Execute request with automatic retry
   */
  async executeWithRetry<T>(
    method: string,
    url: string,
    config?: AxiosRequestConfig,
    retryConfig?: Partial<RetryConfig>
  ): Promise<T> {
    const finalRetryConfig = { ...this.retryConfig, ...retryConfig };
    let lastError: NovaAPIError | null = null;

    for (let attempt = 1; attempt <= finalRetryConfig.maxRetries; attempt++) {
      try {
        const response = await this.instance.request<T>({
          method,
          url,
          ...config,
        });

        return response.data;
      } catch (error) {
        lastError = toNovaError(error);

        // Non-retryable errors should fail immediately, regardless of attempt number
        if (!lastError.isRetryable) {
          this.logErrorWithContext(lastError, method, url);
          throw lastError;
        }

        // If this is the last attempt, throw
        if (attempt === finalRetryConfig.maxRetries) {
          this.logErrorWithContext(lastError, method, url);
          throw lastError;
        }

        // Calculate backoff delay
        const delayMs = calculateBackoffDelay(attempt, finalRetryConfig);

        // Log retry attempt in development
        if (process.env.NODE_ENV !== 'production') {
          console.warn(
            `[NovaAPI Retry] Attempt ${attempt}/${finalRetryConfig.maxRetries} ` +
            `for ${method} ${url} - waiting ${delayMs}ms before retry. ` +
            `Error: ${lastError.message}`
          );
        }

        // Wait before retrying
        await this.sleep(delayMs);
      }
    }

    // Should never reach here, but just in case
    throw lastError || new NovaAPIError(
      ErrorType.UNKNOWN_ERROR,
      'Request failed after all retries'
    );
  }

  /**
   * Helper method to sleep
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /**
   * GET request with retry
   */
  async get<T>(
    url: string,
    config?: AxiosRequestConfig,
    retryConfig?: Partial<RetryConfig>
  ): Promise<T> {
    return this.executeWithRetry<T>('GET', url, config, retryConfig);
  }

  /**
   * POST request with retry
   */
  async post<T>(
    url: string,
    data?: any,
    config?: AxiosRequestConfig,
    retryConfig?: Partial<RetryConfig>
  ): Promise<T> {
    return this.executeWithRetry<T>('POST', url, { ...config, data }, retryConfig);
  }

  /**
   * PUT request with retry
   */
  async put<T>(
    url: string,
    data?: any,
    config?: AxiosRequestConfig,
    retryConfig?: Partial<RetryConfig>
  ): Promise<T> {
    return this.executeWithRetry<T>('PUT', url, { ...config, data }, retryConfig);
  }

  /**
   * PATCH request with retry
   */
  async patch<T>(
    url: string,
    data?: any,
    config?: AxiosRequestConfig,
    retryConfig?: Partial<RetryConfig>
  ): Promise<T> {
    return this.executeWithRetry<T>('PATCH', url, { ...config, data }, retryConfig);
  }

  /**
   * DELETE request with retry
   */
  async delete<T>(
    url: string,
    config?: AxiosRequestConfig,
    retryConfig?: Partial<RetryConfig>
  ): Promise<T> {
    return this.executeWithRetry<T>('DELETE', url, config, retryConfig);
  }

  /**
   * Get underlying axios instance for advanced usage
   */
  getAxios(): AxiosInstance {
    return this.instance;
  }
}

/**
 * Create and export default API client instance
 */
const API_BASE = import.meta.env.VITE_API_BASE || 'http://localhost:8080';

export const apiClient = new NovaAPIClient(
  API_BASE,
  {},
  () => {
    // Handle unauthorized globally
    localStorage.removeItem('auth_token');
    // In a real app, redirect to login
    // window.location.href = '/login';
  }
);
