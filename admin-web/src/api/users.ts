import apiClient from './client';
import type {
  User,
  UserListResponse,
  UserHistoryResponse,
  BanUserRequest,
  WarnUserRequest,
  PaginationParams,
} from './types';

export const usersApi = {
  /**
   * Get paginated list of users
   */
  list: async (params?: PaginationParams): Promise<UserListResponse> => {
    const response = await apiClient.get<UserListResponse>('/users', { params });
    return response.data;
  },

  /**
   * Get user details by ID
   */
  getById: async (id: string): Promise<User> => {
    const response = await apiClient.get<User>(`/users/${id}`);
    return response.data;
  },

  /**
   * Get user history (bans and warnings)
   */
  getHistory: async (id: string): Promise<UserHistoryResponse> => {
    const response = await apiClient.get<UserHistoryResponse>(`/users/${id}/history`);
    return response.data;
  },

  /**
   * Ban a user
   */
  ban: async (id: string, data: BanUserRequest): Promise<{ success: boolean; ban_id: string }> => {
    const response = await apiClient.post(`/users/${id}/ban`, data);
    return response.data;
  },

  /**
   * Unban a user
   */
  unban: async (id: string): Promise<{ success: boolean }> => {
    const response = await apiClient.post(`/users/${id}/unban`);
    return response.data;
  },

  /**
   * Send warning to a user
   */
  warn: async (id: string, data: WarnUserRequest): Promise<{ success: boolean; warning_id: string }> => {
    const response = await apiClient.post(`/users/${id}/warn`, data);
    return response.data;
  },
};

export default usersApi;
