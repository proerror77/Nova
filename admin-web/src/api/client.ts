import axios, { AxiosError, InternalAxiosRequestConfig } from 'axios';
import { toast } from 'sonner';

// API base URL - uses relative path for same-origin requests via ingress
const API_BASE_URL = import.meta.env.VITE_API_URL || '/api/admin/v1';

// Create axios instance
export const apiClient = axios.create({
  baseURL: API_BASE_URL,
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Token management
let accessToken: string | null = null;
let refreshToken: string | null = null;
let isRefreshing = false;
let failedQueue: Array<{
  resolve: (token: string) => void;
  reject: (error: Error) => void;
}> = [];

export const setTokens = (access: string, refresh: string) => {
  accessToken = access;
  refreshToken = refresh;
  // Also persist to localStorage for page refresh
  localStorage.setItem('admin_access_token', access);
  localStorage.setItem('admin_refresh_token', refresh);
};

export const getAccessToken = () => {
  if (!accessToken) {
    accessToken = localStorage.getItem('admin_access_token');
  }
  return accessToken;
};

export const getRefreshToken = () => {
  if (!refreshToken) {
    refreshToken = localStorage.getItem('admin_refresh_token');
  }
  return refreshToken;
};

export const clearTokens = () => {
  accessToken = null;
  refreshToken = null;
  localStorage.removeItem('admin_access_token');
  localStorage.removeItem('admin_refresh_token');
  localStorage.removeItem('admin-auth'); // Clear zustand persist
};

const processQueue = (error: Error | null, token: string | null = null) => {
  failedQueue.forEach((promise) => {
    if (error) {
      promise.reject(error);
    } else if (token) {
      promise.resolve(token);
    }
  });
  failedQueue = [];
};

// Request interceptor - add auth header
apiClient.interceptors.request.use(
  (config: InternalAxiosRequestConfig) => {
    const token = getAccessToken();
    if (token && config.headers) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// Response interceptor - handle errors and token refresh
apiClient.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as InternalAxiosRequestConfig & { _retry?: boolean };

    // Handle 401 Unauthorized - attempt token refresh
    if (error.response?.status === 401 && !originalRequest._retry) {
      if (isRefreshing) {
        // Wait for the ongoing refresh
        return new Promise((resolve, reject) => {
          failedQueue.push({ resolve, reject });
        })
          .then((token) => {
            if (originalRequest.headers) {
              originalRequest.headers.Authorization = `Bearer ${token}`;
            }
            return apiClient(originalRequest);
          })
          .catch((err) => Promise.reject(err));
      }

      originalRequest._retry = true;
      isRefreshing = true;

      const currentRefreshToken = getRefreshToken();
      if (!currentRefreshToken) {
        clearTokens();
        window.location.href = '/login';
        return Promise.reject(error);
      }

      try {
        const response = await axios.post(`${API_BASE_URL}/auth/refresh`, {
          refresh_token: currentRefreshToken,
        });

        const { access_token } = response.data;
        setTokens(access_token, currentRefreshToken);

        processQueue(null, access_token);

        if (originalRequest.headers) {
          originalRequest.headers.Authorization = `Bearer ${access_token}`;
        }
        return apiClient(originalRequest);
      } catch (refreshError) {
        processQueue(new Error('Token refresh failed'), null);
        clearTokens();
        window.location.href = '/login';
        return Promise.reject(refreshError);
      } finally {
        isRefreshing = false;
      }
    }

    // Handle other error codes with user-friendly messages
    if (error.response) {
      const { status, data } = error.response;
      const message = (data as { message?: string })?.message || '操作失败';

      switch (status) {
        case 400:
          toast.error(`请求错误: ${message}`);
          break;
        case 403:
          toast.error('权限不足，无法执行此操作');
          break;
        case 404:
          toast.error('请求的资源不存在');
          break;
        case 429:
          toast.error('请求过于频繁，请稍后再试');
          break;
        case 500:
          toast.error('服务器错误，请稍后重试');
          break;
        default:
          if (status !== 401) {
            toast.error(message);
          }
      }
    } else if (error.request) {
      toast.error('网络连接失败，请检查网络');
    }

    return Promise.reject(error);
  }
);

export default apiClient;
