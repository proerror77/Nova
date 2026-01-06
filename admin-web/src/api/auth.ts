import apiClient, { setTokens, clearTokens } from './client';
import type { LoginRequest, LoginResponse, AdminInfo, RefreshResponse } from './types';

export const authApi = {
  /**
   * Login with email and password
   */
  login: async (data: LoginRequest): Promise<LoginResponse> => {
    const response = await apiClient.post<LoginResponse>('/auth/login', data);
    const { access_token, refresh_token, admin } = response.data;
    setTokens(access_token, refresh_token);
    return response.data;
  },

  /**
   * Logout current session
   */
  logout: async (): Promise<void> => {
    try {
      await apiClient.post('/auth/logout');
    } finally {
      clearTokens();
    }
  },

  /**
   * Refresh access token
   */
  refresh: async (refreshToken: string): Promise<RefreshResponse> => {
    const response = await apiClient.post<RefreshResponse>('/auth/refresh', {
      refresh_token: refreshToken,
    });
    return response.data;
  },

  /**
   * Get current admin info
   */
  me: async (): Promise<AdminInfo> => {
    const response = await apiClient.get<AdminInfo>('/auth/me');
    return response.data;
  },
};

export default authApi;
