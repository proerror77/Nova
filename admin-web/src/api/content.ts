import apiClient from './client';
import type {
  PostListResponse,
  PostDetail,
  CommentListResponse,
  ModerationRequest,
  RejectRequest,
  PaginationParams,
} from './types';

export const contentApi = {
  // Posts
  /**
   * Get paginated list of posts
   */
  listPosts: async (params?: PaginationParams): Promise<PostListResponse> => {
    const response = await apiClient.get<PostListResponse>('/content/posts', { params });
    return response.data;
  },

  /**
   * Get post details by ID
   */
  getPost: async (id: string): Promise<PostDetail> => {
    const response = await apiClient.get<PostDetail>(`/content/posts/${id}`);
    return response.data;
  },

  /**
   * Approve a post
   */
  approvePost: async (id: string, data?: ModerationRequest): Promise<{ success: boolean }> => {
    const response = await apiClient.post(`/content/posts/${id}/approve`, data || {});
    return response.data;
  },

  /**
   * Reject a post
   */
  rejectPost: async (id: string, data: RejectRequest): Promise<{ success: boolean }> => {
    const response = await apiClient.post(`/content/posts/${id}/reject`, data);
    return response.data;
  },

  // Comments
  /**
   * Get paginated list of comments
   */
  listComments: async (params?: PaginationParams): Promise<CommentListResponse> => {
    const response = await apiClient.get<CommentListResponse>('/content/comments', { params });
    return response.data;
  },

  /**
   * Approve a comment
   */
  approveComment: async (id: string, data?: ModerationRequest): Promise<{ success: boolean }> => {
    const response = await apiClient.post(`/content/comments/${id}/approve`, data || {});
    return response.data;
  },

  /**
   * Reject a comment
   */
  rejectComment: async (id: string, data: RejectRequest): Promise<{ success: boolean }> => {
    const response = await apiClient.post(`/content/comments/${id}/reject`, data);
    return response.data;
  },
};

export default contentApi;
