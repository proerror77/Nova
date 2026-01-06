// React Query hooks for Dashboard
import { useQuery } from '@tanstack/react-query';
import { dashboardApi } from '../api';

export const useDashboardStats = () => {
  return useQuery({
    queryKey: ['dashboard', 'stats'],
    queryFn: dashboardApi.getStats,
    staleTime: 30 * 1000, // 30 seconds
    refetchInterval: 60 * 1000, // Auto-refresh every minute
  });
};

export const useUserChart = (period: string = '7d') => {
  return useQuery({
    queryKey: ['dashboard', 'charts', 'users', period],
    queryFn: () => dashboardApi.getUserChart(period),
    staleTime: 60 * 1000, // 1 minute
  });
};

export const useActivityChart = (period: string = '7d') => {
  return useQuery({
    queryKey: ['dashboard', 'charts', 'activity', period],
    queryFn: () => dashboardApi.getActivityChart(period),
    staleTime: 60 * 1000, // 1 minute
  });
};

export const useRecentActivity = (limit: number = 20) => {
  return useQuery({
    queryKey: ['dashboard', 'activity', limit],
    queryFn: () => dashboardApi.getRecentActivity(limit),
    staleTime: 30 * 1000, // 30 seconds
  });
};

export const useRiskAlerts = () => {
  return useQuery({
    queryKey: ['dashboard', 'risks'],
    queryFn: dashboardApi.getRiskAlerts,
    staleTime: 30 * 1000, // 30 seconds
    refetchInterval: 60 * 1000, // Auto-refresh every minute
  });
};
