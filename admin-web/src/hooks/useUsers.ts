// React Query hooks for Users
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { usersApi, PaginationParams, BanUserRequest, WarnUserRequest } from '../api';
import { toast } from 'sonner';

export const useUsers = (params?: PaginationParams) => {
  return useQuery({
    queryKey: ['users', 'list', params],
    queryFn: () => usersApi.list(params),
    staleTime: 30 * 1000,
  });
};

export const useUser = (id: string) => {
  return useQuery({
    queryKey: ['users', 'detail', id],
    queryFn: () => usersApi.getById(id),
    enabled: !!id,
  });
};

export const useUserHistory = (id: string) => {
  return useQuery({
    queryKey: ['users', 'history', id],
    queryFn: () => usersApi.getHistory(id),
    enabled: !!id,
  });
};

export const useBanUser = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: BanUserRequest }) =>
      usersApi.ban(id, data),
    onSuccess: (_, variables) => {
      toast.success(`用户 ${variables.id} 已被封禁`);
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
    onError: () => {
      toast.error('封禁用户失败');
    },
  });
};

export const useUnbanUser = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: (id: string) => usersApi.unban(id),
    onSuccess: (_, id) => {
      toast.success(`用户 ${id} 已解除封禁`);
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
    onError: () => {
      toast.error('解除封禁失败');
    },
  });
};

export const useWarnUser = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: WarnUserRequest }) =>
      usersApi.warn(id, data),
    onSuccess: (_, variables) => {
      toast.success(`已向用户 ${variables.id} 发送警告`);
      queryClient.invalidateQueries({ queryKey: ['users'] });
    },
    onError: () => {
      toast.error('发送警告失败');
    },
  });
};
