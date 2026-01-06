import apiClient from './client';
import type {
  DashboardStats,
  UserChartResponse,
  ActivityChartResponse,
  RecentActivity,
  RiskAlertsResponse,
} from './types';

export const dashboardApi = {
  /**
   * Get dashboard statistics
   */
  getStats: async (): Promise<DashboardStats> => {
    const response = await apiClient.get<DashboardStats>('/dashboard/stats');
    return response.data;
  },

  /**
   * Get user growth chart data
   */
  getUserChart: async (period: string = '7d'): Promise<UserChartResponse> => {
    const response = await apiClient.get<UserChartResponse>('/dashboard/charts/users', {
      params: { period },
    });
    return response.data;
  },

  /**
   * Get activity chart data
   */
  getActivityChart: async (period: string = '7d'): Promise<ActivityChartResponse> => {
    const response = await apiClient.get<ActivityChartResponse>('/dashboard/charts/activity', {
      params: { period },
    });
    return response.data;
  },

  /**
   * Get recent admin activity
   */
  getRecentActivity: async (limit: number = 20): Promise<RecentActivity[]> => {
    const response = await apiClient.get<RecentActivity[]>('/dashboard/activity', {
      params: { limit },
    });
    return response.data;
  },

  /**
   * Get risk alerts
   */
  getRiskAlerts: async (): Promise<RiskAlertsResponse> => {
    const response = await apiClient.get<RiskAlertsResponse>('/dashboard/risks');
    return response.data;
  },
};

export default dashboardApi;
