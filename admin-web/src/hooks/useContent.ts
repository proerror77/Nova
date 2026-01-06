// React Query hooks for Content
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { contentApi, PaginationParams, RejectRequest, ModerationRequest } from '../api';
import { toast } from 'sonner';

// Posts
export const usePosts = (params?: PaginationParams) => {
  return useQuery({
    queryKey: ['content', 'posts', params],
    queryFn: () => contentApi.listPosts(params),
    staleTime: 30 * 1000,
  });
};

export const usePost = (id: string) => {
  return useQuery({
    queryKey: ['content', 'posts', 'detail', id],
    queryFn: () => contentApi.getPost(id),
    enabled: !!id,
  });
};

export const useApprovePost = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data?: ModerationRequest }) =>
      contentApi.approvePost(id, data),
    onSuccess: () => {
      toast.success('帖子已通过审核');
      queryClient.invalidateQueries({ queryKey: ['content', 'posts'] });
    },
    onError: () => {
      toast.error('审核操作失败');
    },
  });
};

export const useRejectPost = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: RejectRequest }) =>
      contentApi.rejectPost(id, data),
    onSuccess: () => {
      toast.success('帖子已拒绝');
      queryClient.invalidateQueries({ queryKey: ['content', 'posts'] });
    },
    onError: () => {
      toast.error('拒绝操作失败');
    },
  });
};

// Comments
export const useComments = (params?: PaginationParams) => {
  return useQuery({
    queryKey: ['content', 'comments', params],
    queryFn: () => contentApi.listComments(params),
    staleTime: 30 * 1000,
  });
};

export const useApproveComment = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data?: ModerationRequest }) =>
      contentApi.approveComment(id, data),
    onSuccess: () => {
      toast.success('评论已通过审核');
      queryClient.invalidateQueries({ queryKey: ['content', 'comments'] });
    },
    onError: () => {
      toast.error('审核操作失败');
    },
  });
};

export const useRejectComment = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: RejectRequest }) =>
      contentApi.rejectComment(id, data),
    onSuccess: () => {
      toast.success('评论已拒绝');
      queryClient.invalidateQueries({ queryKey: ['content', 'comments'] });
    },
    onError: () => {
      toast.error('拒绝操作失败');
    },
  });
};
