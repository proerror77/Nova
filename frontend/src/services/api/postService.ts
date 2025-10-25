/**
 * Post API Service
 * Handles photo and video uploads, likes, comments, and post interactions
 * Uses centralized error handling with automatic retry
 */

import { apiClient } from './client';
import { NovaAPIError, toNovaError, logError, createErrorContext } from './errors';
import { useErrorStore } from './errorStore';

// ============================================
// Types
// ============================================

export interface UploadInitRequest {
  filename: string;
  content_type: string;
  file_size: number;
  caption?: string;
}

export interface UploadInitResponse {
  presigned_url: string;
  post_id: string;
  upload_token: string;
  expires_in: number;
  instructions: string;
}

export interface UploadCompleteRequest {
  post_id: string;
  upload_token: string;
  file_hash: string;
  file_size: number;
}

export interface UploadCompleteResponse {
  post_id: string;
  status: string;
  message: string;
  image_key: string;
}

export interface VideoUploadUrlResponse {
  video_id: string;
  presigned_url: string;
  expires_in: number;
}

export interface CreateVideoRequest {
  title: string;
  description?: string;
  hashtags?: string[];
  visibility?: string;
}

export interface CreateVideoResponse {
  video_id: string;
  status: string;
  created_at: string;
  title: string;
  hashtags: string[];
}

export interface ProcessingCompleteRequest {
  duration_seconds: number;
  width: number;
  height: number;
  bitrate_kbps: number;
  fps: number;
  video_codec: string;
  visibility?: string;
  file_url?: string;
}

// ============================================
// Helper Functions
// ============================================

/**
 * Calculate SHA-256 hash of a file
 */
async function calculateFileHash(file: File): Promise<string> {
  const buffer = await file.arrayBuffer();
  const hashBuffer = await crypto.subtle.digest('SHA-256', buffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Upload file to S3 using presigned URL with error handling
 */
async function uploadToS3(presignedUrl: string, file: File, contentType: string): Promise<void> {
  const errorContext = createErrorContext();
  try {
    const response = await fetch(presignedUrl, {
      method: 'PUT',
      headers: { 'Content-Type': contentType },
      body: file,
    });

    if (!response.ok) {
      throw new NovaAPIError(
        'SERVER_ERROR' as any,
        `S3 upload failed with status ${response.status}`,
        { statusCode: response.status }
      );
    }
  } catch (error) {
    const novaError = toNovaError(error);
    logError(novaError, { ...errorContext, requestUrl: presignedUrl });
    throw novaError;
  }
}

// ============================================
// Photo Upload Flow
// ============================================

/**
 * Step 1: Initialize photo upload and get presigned URL
 * POST /api/v1/posts/upload/init
 */
export async function initPhotoUpload(
  file: File,
  caption?: string
): Promise<UploadInitResponse> {
  const request: UploadInitRequest = {
    filename: file.name,
    content_type: file.type,
    file_size: file.size,
    caption,
  };

  try {
    return await apiClient.post<UploadInitResponse>(
      '/api/v1/posts/upload/init',
      request
    );
  } catch (error) {
    const novaError = toNovaError(error);
    useErrorStore.getState().addError(novaError);
    throw novaError;
  }
}

/**
 * Step 2: Upload photo to S3 using presigned URL
 */
export async function uploadPhotoToS3(presignedUrl: string, file: File): Promise<void> {
  await uploadToS3(presignedUrl, file, file.type);
}

/**
 * Step 3: Complete photo upload
 * POST /api/v1/posts/upload/complete
 */
export async function completePhotoUpload(
  postId: string,
  uploadToken: string,
  file: File
): Promise<UploadCompleteResponse> {
  const fileHash = await calculateFileHash(file);

  const request: UploadCompleteRequest = {
    post_id: postId,
    upload_token: uploadToken,
    file_hash: fileHash,
    file_size: file.size,
  };

  try {
    return await apiClient.post<UploadCompleteResponse>(
      '/api/v1/posts/upload/complete',
      request
    );
  } catch (error) {
    const novaError = toNovaError(error);
    useErrorStore.getState().addError(novaError);
    throw novaError;
  }
}

/**
 * Full photo upload flow (all 3 steps)
 * Automatically retries transient failures
 */
export async function uploadPhoto(
  file: File,
  caption?: string,
  onProgress?: (progress: number) => void
): Promise<string> {
  const errorContext = createErrorContext();

  try {
    // Step 1: Init
    onProgress?.(10);
    const initResponse = await initPhotoUpload(file, caption);

    // Step 2: Upload to S3
    onProgress?.(30);
    await uploadPhotoToS3(initResponse.presigned_url, file);

    // Step 3: Complete
    onProgress?.(80);
    const completeResponse = await completePhotoUpload(
      initResponse.post_id,
      initResponse.upload_token,
      file
    );

    onProgress?.(100);
    return completeResponse.post_id;
  } catch (error) {
    const novaError = toNovaError(error);
    errorContext.requestMethod = 'POST';
    errorContext.requestUrl = '/api/v1/posts/upload/*';
    logError(novaError, errorContext);
    throw novaError;
  }
}

// ============================================
// Video Upload Flow
// ============================================

/**
 * Step 1: Get presigned URL for video upload
 * POST /api/v1/videos/upload-url
 */
export async function getVideoUploadUrl(): Promise<VideoUploadUrlResponse> {
  try {
    return await apiClient.post<VideoUploadUrlResponse>(
      '/api/v1/videos/upload-url',
      {}
    );
  } catch (error) {
    const novaError = toNovaError(error);
    useErrorStore.getState().addError(novaError);
    throw novaError;
  }
}

/**
 * Step 2: Upload video to S3
 */
export async function uploadVideoToS3(presignedUrl: string, file: File): Promise<void> {
  await uploadToS3(presignedUrl, file, file.type);
}

/**
 * Step 3: Create video metadata
 * POST /api/v1/videos
 */
export async function createVideoMetadata(
  title: string,
  description?: string,
  hashtags?: string[],
  visibility?: string
): Promise<CreateVideoResponse> {
  const request: CreateVideoRequest = {
    title,
    description,
    hashtags,
    visibility: visibility || 'public',
  };

  try {
    return await apiClient.post<CreateVideoResponse>(
      '/api/v1/videos',
      request
    );
  } catch (error) {
    const novaError = toNovaError(error);
    useErrorStore.getState().addError(novaError);
    throw novaError;
  }
}

/**
 * Full video upload flow
 * Automatically retries transient failures
 */
export async function uploadVideo(
  file: File,
  title: string,
  description?: string,
  hashtags?: string[],
  onProgress?: (progress: number) => void
): Promise<string> {
  const errorContext = createErrorContext();

  try {
    // Step 1: Get upload URL
    onProgress?.(10);
    const urlResponse = await getVideoUploadUrl();

    // Step 2: Upload to S3
    onProgress?.(30);
    await uploadVideoToS3(urlResponse.presigned_url, file);

    // Step 3: Create metadata
    onProgress?.(80);
    const videoResponse = await createVideoMetadata(title, description, hashtags);

    onProgress?.(100);
    return videoResponse.video_id;
  } catch (error) {
    const novaError = toNovaError(error);
    errorContext.requestMethod = 'POST';
    errorContext.requestUrl = '/api/v1/videos/*';
    logError(novaError, errorContext);
    throw novaError;
  }
}

// ============================================
// Validation
// ============================================

const MAX_PHOTO_SIZE = 50 * 1024 * 1024; // 50 MB
const MIN_PHOTO_SIZE = 100 * 1024; // 100 KB
const ALLOWED_PHOTO_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic'];
const MAX_VIDEO_SIZE = 500 * 1024 * 1024; // 500 MB
const ALLOWED_VIDEO_TYPES = ['video/mp4', 'video/quicktime', 'video/webm'];

export function validatePhotoFile(file: File): { valid: boolean; error?: string } {
  if (!ALLOWED_PHOTO_TYPES.includes(file.type)) {
    return {
      valid: false,
      error: `Invalid file type. Allowed: ${ALLOWED_PHOTO_TYPES.join(', ')}`,
    };
  }

  if (file.size < MIN_PHOTO_SIZE) {
    return { valid: false, error: 'File too small (minimum 100 KB)' };
  }

  if (file.size > MAX_PHOTO_SIZE) {
    return { valid: false, error: 'File too large (maximum 50 MB)' };
  }

  return { valid: true };
}

export function validateVideoFile(file: File): { valid: boolean; error?: string } {
  if (!ALLOWED_VIDEO_TYPES.includes(file.type)) {
    return {
      valid: false,
      error: `Invalid file type. Allowed: ${ALLOWED_VIDEO_TYPES.join(', ')}`,
    };
  }

  if (file.size > MAX_VIDEO_SIZE) {
    return { valid: false, error: 'File too large (maximum 500 MB)' };
  }

  return { valid: true };
}

// ============================================
// Like/Unlike Post
// ============================================

export interface LikeResponse {
  post_id: string;
  liked: boolean;
  like_count: number;
}

/**
 * Like a post
 * POST /api/v1/posts/{id}/like
 */
export async function likePost(postId: string): Promise<LikeResponse> {
  const errorContext = createErrorContext();
  try {
    return await apiClient.post<LikeResponse>(
      `/api/v1/posts/${postId}/like`,
      {}
    );
  } catch (error) {
    const novaError = toNovaError(error);
    errorContext.requestMethod = 'POST';
    errorContext.requestUrl = `/api/v1/posts/${postId}/like`;
    logError(novaError, errorContext);
    useErrorStore.getState().addError(novaError);
    throw novaError;
  }
}

/**
 * Unlike a post
 * DELETE /api/v1/posts/{id}/like
 */
export async function unlikePost(postId: string): Promise<LikeResponse> {
  const errorContext = createErrorContext();
  try {
    return await apiClient.delete<LikeResponse>(
      `/api/v1/posts/${postId}/like`
    );
  } catch (error) {
    const novaError = toNovaError(error);
    errorContext.requestMethod = 'DELETE';
    errorContext.requestUrl = `/api/v1/posts/${postId}/like`;
    logError(novaError, errorContext);
    useErrorStore.getState().addError(novaError);
    throw novaError;
  }
}

// ============================================
// Comments
// ============================================

export interface Comment {
  id: string;
  post_id: string;
  user_id: string;
  content: string;
  created_at: string;
  updated_at: string;
}

export interface CreateCommentRequest {
  content: string;
}

export interface CreateCommentResponse {
  comment_id: string;
  post_id: string;
  content: string;
  created_at: string;
}

export interface ListCommentsResponse {
  comments: Comment[];
  total_count: number;
  limit: number;
  offset: number;
}

/**
 * Create a comment on a post
 * POST /api/v1/posts/{id}/comments
 */
export async function createComment(
  postId: string,
  content: string
): Promise<CreateCommentResponse> {
  const errorContext = createErrorContext();
  const request: CreateCommentRequest = { content };

  try {
    return await apiClient.post<CreateCommentResponse>(
      `/api/v1/posts/${postId}/comments`,
      request
    );
  } catch (error) {
    const novaError = toNovaError(error);
    errorContext.requestMethod = 'POST';
    errorContext.requestUrl = `/api/v1/posts/${postId}/comments`;
    logError(novaError, errorContext);
    useErrorStore.getState().addError(novaError);
    throw novaError;
  }
}

/**
 * Get comments for a post
 * GET /api/v1/posts/{id}/comments
 */
export async function getComments(
  postId: string,
  limit: number = 10,
  offset: number = 0
): Promise<ListCommentsResponse> {
  const errorContext = createErrorContext();
  try {
    return await apiClient.get<ListCommentsResponse>(
      `/api/v1/posts/${postId}/comments?limit=${limit}&offset=${offset}`
    );
  } catch (error) {
    const novaError = toNovaError(error);
    errorContext.requestMethod = 'GET';
    errorContext.requestUrl = `/api/v1/posts/${postId}/comments`;
    logError(novaError, errorContext);
    useErrorStore.getState().addError(novaError);
    throw novaError;
  }
}

/**
 * Delete a comment
 * DELETE /api/v1/posts/{postId}/comments/{commentId}
 */
export async function deleteComment(postId: string, commentId: string): Promise<void> {
  const errorContext = createErrorContext();
  try {
    await apiClient.delete(`/api/v1/posts/${postId}/comments/${commentId}`);
  } catch (error) {
    const novaError = toNovaError(error);
    errorContext.requestMethod = 'DELETE';
    errorContext.requestUrl = `/api/v1/posts/${postId}/comments/${commentId}`;
    logError(novaError, errorContext);
    useErrorStore.getState().addError(novaError);
    throw novaError;
  }
}
