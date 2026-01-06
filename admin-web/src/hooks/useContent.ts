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
      toast.success('Post approved successfully');
      queryClient.invalidateQueries({ queryKey: ['content', 'posts'] });
    },
    onError: () => {
      toast.error('Failed to approve post');
    },
  });
};

export const useRejectPost = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: RejectRequest }) =>
      contentApi.rejectPost(id, data),
    onSuccess: () => {
      toast.success('Post rejected successfully');
      queryClient.invalidateQueries({ queryKey: ['content', 'posts'] });
    },
    onError: () => {
      toast.error('Failed to reject post');
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
      toast.success('Comment approved successfully');
      queryClient.invalidateQueries({ queryKey: ['content', 'comments'] });
    },
    onError: () => {
      toast.error('Failed to approve comment');
    },
  });
};

export const useRejectComment = () => {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: RejectRequest }) =>
      contentApi.rejectComment(id, data),
    onSuccess: () => {
      toast.success('Comment rejected successfully');
      queryClient.invalidateQueries({ queryKey: ['content', 'comments'] });
    },
    onError: () => {
      toast.error('Failed to reject comment');
    },
  });
};
