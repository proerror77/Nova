/**
 * PostCreator Component
 * Main component for creating posts with photo and video uploads
 *
 * Usage:
 * <PostCreator onSuccess={(postId) => console.log('Created:', postId)} />
 */

import React, { useState, useRef } from 'react';
import MediaPreview from './MediaPreview';
import {
  uploadPhoto,
  uploadVideo,
  validatePhotoFile,
  validateVideoFile,
} from '../../services/api/postService';

interface PostCreatorProps {
  onSuccess?: (postId: string) => void;
  onError?: (error: Error) => void;
}

interface UploadProgress {
  fileIndex: number;
  fileName: string;
  progress: number;
  status: 'pending' | 'uploading' | 'completed' | 'error';
  error?: string;
}

const PostCreator: React.FC<PostCreatorProps> = ({ onSuccess, onError }) => {
  const [caption, setCaption] = useState('');
  const [photos, setPhotos] = useState<File[]>([]);
  const [videos, setVideos] = useState<File[]>([]);
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState<UploadProgress[]>([]);
  const [error, setError] = useState<string | null>(null);

  const photoInputRef = useRef<HTMLInputElement>(null);
  const videoInputRef = useRef<HTMLInputElement>(null);

  // ============================================
  // File Selection Handlers
  // ============================================

  const handlePhotoSelect = (event: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(event.target.files || []);
    const validFiles: File[] = [];
    const errors: string[] = [];

    files.forEach(file => {
      const validation = validatePhotoFile(file);
      if (validation.valid) {
        validFiles.push(file);
      } else {
        errors.push(`${file.name}: ${validation.error}`);
      }
    });

    if (errors.length > 0) {
      setError(errors.join('\n'));
    } else {
      setError(null);
    }

    setPhotos(prev => [...prev, ...validFiles]);

    // Reset input
    if (photoInputRef.current) {
      photoInputRef.current.value = '';
    }
  };

  const handleVideoSelect = (event: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(event.target.files || []);
    const validFiles: File[] = [];
    const errors: string[] = [];

    files.forEach(file => {
      const validation = validateVideoFile(file);
      if (validation.valid) {
        validFiles.push(file);
      } else {
        errors.push(`${file.name}: ${validation.error}`);
      }
    });

    if (errors.length > 0) {
      setError(errors.join('\n'));
    } else {
      setError(null);
    }

    setVideos(prev => [...prev, ...validFiles]);

    // Reset input
    if (videoInputRef.current) {
      videoInputRef.current.value = '';
    }
  };

  // ============================================
  // Remove Handlers
  // ============================================

  const handleRemovePhoto = (index: number) => {
    setPhotos(prev => prev.filter((_, i) => i !== index));
  };

  const handleRemoveVideo = (index: number) => {
    setVideos(prev => prev.filter((_, i) => i !== index));
  };

  // ============================================
  // Upload Handler
  // ============================================

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();

    if (photos.length === 0 && videos.length === 0) {
      setError('Please select at least one photo or video');
      return;
    }

    setUploading(true);
    setError(null);

    const allFiles = [...photos, ...videos];
    const progress: UploadProgress[] = allFiles.map((file, index) => ({
      fileIndex: index,
      fileName: file.name,
      progress: 0,
      status: 'pending',
    }));
    setUploadProgress(progress);

    try {
      const uploadPromises = [];

      // Upload photos
      for (let i = 0; i < photos.length; i++) {
        const photo = photos[i];
        const fileIndex = i;

        const promise = uploadPhoto(
          photo,
          i === 0 ? caption : undefined, // Only attach caption to first photo
          (progressPercent) => {
            setUploadProgress(prev =>
              prev.map(p =>
                p.fileIndex === fileIndex
                  ? { ...p, progress: progressPercent, status: 'uploading' }
                  : p
              )
            );
          }
        ).then(postId => {
          setUploadProgress(prev =>
            prev.map(p =>
              p.fileIndex === fileIndex
                ? { ...p, progress: 100, status: 'completed' }
                : p
            )
          );
          return postId;
        });

        uploadPromises.push(promise);
      }

      // Upload videos
      for (let i = 0; i < videos.length; i++) {
        const video = videos[i];
        const fileIndex = photos.length + i;
        const title = caption || video.name;

        const promise = uploadVideo(
          video,
          title,
          caption,
          [], // No hashtags for now
          (progressPercent) => {
            setUploadProgress(prev =>
              prev.map(p =>
                p.fileIndex === fileIndex
                  ? { ...p, progress: progressPercent, status: 'uploading' }
                  : p
              )
            );
          }
        ).then(videoId => {
          setUploadProgress(prev =>
            prev.map(p =>
              p.fileIndex === fileIndex
                ? { ...p, progress: 100, status: 'completed' }
                : p
            )
          );
          return videoId;
        });

        uploadPromises.push(promise);
      }

      const results = await Promise.all(uploadPromises);

      // Success - reset form
      setCaption('');
      setPhotos([]);
      setVideos([]);
      setUploadProgress([]);

      onSuccess?.(results[0]); // Return first uploaded item ID
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : 'Upload failed';
      setError(errorMessage);
      onError?.(err instanceof Error ? err : new Error(errorMessage));

      // Mark all pending/uploading as error
      setUploadProgress(prev =>
        prev.map(p =>
          p.status === 'pending' || p.status === 'uploading'
            ? { ...p, status: 'error', error: errorMessage }
            : p
        )
      );
    } finally {
      setUploading(false);
    }
  };

  // ============================================
  // Render
  // ============================================

  const hasFiles = photos.length > 0 || videos.length > 0;
  const isDisabled = uploading || !hasFiles;

  return (
    <div className="post-creator">
      <h2>Create Post</h2>

      <form onSubmit={handleSubmit}>
        {/* Caption Input */}
        <div className="form-group">
          <label htmlFor="caption">Caption</label>
          <textarea
            id="caption"
            value={caption}
            onChange={(e) => setCaption(e.target.value)}
            placeholder="Write a caption..."
            rows={4}
            maxLength={2200}
            disabled={uploading}
          />
          <div className="char-count">
            {caption.length} / 2200
          </div>
        </div>

        {/* File Upload Buttons */}
        <div className="upload-buttons">
          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => photoInputRef.current?.click()}
            disabled={uploading}
            aria-label="Upload photos"
          >
            📷 Add Photos
          </button>

          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => videoInputRef.current?.click()}
            disabled={uploading}
            aria-label="Upload videos"
          >
            🎥 Add Videos
          </button>

          <input
            ref={photoInputRef}
            type="file"
            accept="image/jpeg,image/png,image/webp,image/heic"
            multiple
            onChange={handlePhotoSelect}
            style={{ display: 'none' }}
            aria-hidden="true"
          />

          <input
            ref={videoInputRef}
            type="file"
            accept="video/mp4,video/quicktime,video/webm"
            multiple
            onChange={handleVideoSelect}
            style={{ display: 'none' }}
            aria-hidden="true"
          />
        </div>

        {/* Photo Previews */}
        {photos.length > 0 && (
          <div className="media-section">
            <h3>Photos ({photos.length})</h3>
            <MediaPreview files={photos} onRemove={handleRemovePhoto} />
          </div>
        )}

        {/* Video Previews */}
        {videos.length > 0 && (
          <div className="media-section">
            <h3>Videos ({videos.length})</h3>
            <MediaPreview files={videos} onRemove={handleRemoveVideo} />
          </div>
        )}

        {/* Upload Progress */}
        {uploadProgress.length > 0 && (
          <div className="upload-progress">
            <h3>Upload Progress</h3>
            {uploadProgress.map((progress) => (
              <div key={progress.fileIndex} className="progress-item">
                <div className="progress-header">
                  <span className="file-name">{progress.fileName}</span>
                  <span className="progress-status">
                    {progress.status === 'completed' && '✓ Done'}
                    {progress.status === 'uploading' && `${progress.progress}%`}
                    {progress.status === 'pending' && 'Waiting...'}
                    {progress.status === 'error' && '✗ Failed'}
                  </span>
                </div>
                <div className="progress-bar">
                  <div
                    className={`progress-fill ${progress.status}`}
                    style={{ width: `${progress.progress}%` }}
                  />
                </div>
                {progress.error && (
                  <div className="progress-error">{progress.error}</div>
                )}
              </div>
            ))}
          </div>
        )}

        {/* Error Display */}
        {error && (
          <div className="error-message" role="alert">
            {error}
          </div>
        )}

        {/* Submit Button */}
        <button
          type="submit"
          className="btn btn-primary"
          disabled={isDisabled}
        >
          {uploading ? 'Uploading...' : 'Create Post'}
        </button>
      </form>

      <style>{`
        .post-creator {
          max-width: 800px;
          margin: 0 auto;
          padding: 24px;
          background: white;
          border-radius: 12px;
          box-shadow: 0 2px 12px rgba(0, 0, 0, 0.1);
        }

        .post-creator h2 {
          margin: 0 0 24px 0;
          font-size: 24px;
          font-weight: 600;
        }

        .form-group {
          margin-bottom: 24px;
        }

        .form-group label {
          display: block;
          margin-bottom: 8px;
          font-weight: 500;
          font-size: 14px;
        }

        textarea {
          width: 100%;
          padding: 12px;
          border: 1px solid #ddd;
          border-radius: 8px;
          font-size: 14px;
          font-family: inherit;
          resize: vertical;
          transition: border-color 0.2s;
        }

        textarea:focus {
          outline: none;
          border-color: #007bff;
          box-shadow: 0 0 0 3px rgba(0, 123, 255, 0.1);
        }

        textarea:disabled {
          background: #f5f5f5;
          cursor: not-allowed;
        }

        .char-count {
          margin-top: 4px;
          font-size: 12px;
          color: #666;
          text-align: right;
        }

        .upload-buttons {
          display: flex;
          gap: 12px;
          margin-bottom: 24px;
          flex-wrap: wrap;
        }

        .btn {
          padding: 12px 24px;
          border: none;
          border-radius: 8px;
          font-size: 14px;
          font-weight: 500;
          cursor: pointer;
          transition: all 0.2s;
        }

        .btn:disabled {
          opacity: 0.5;
          cursor: not-allowed;
        }

        .btn-primary {
          background: #007bff;
          color: white;
          width: 100%;
        }

        .btn-primary:hover:not(:disabled) {
          background: #0056b3;
        }

        .btn-secondary {
          background: #f5f5f5;
          color: #333;
        }

        .btn-secondary:hover:not(:disabled) {
          background: #e0e0e0;
        }

        .btn:focus {
          outline: 2px solid #007bff;
          outline-offset: 2px;
        }

        .media-section {
          margin-bottom: 24px;
        }

        .media-section h3 {
          margin: 0 0 12px 0;
          font-size: 16px;
          font-weight: 600;
        }

        .upload-progress {
          margin: 24px 0;
          padding: 16px;
          background: #f9f9f9;
          border-radius: 8px;
        }

        .upload-progress h3 {
          margin: 0 0 16px 0;
          font-size: 16px;
          font-weight: 600;
        }

        .progress-item {
          margin-bottom: 16px;
        }

        .progress-item:last-child {
          margin-bottom: 0;
        }

        .progress-header {
          display: flex;
          justify-content: space-between;
          align-items: center;
          margin-bottom: 8px;
        }

        .file-name {
          font-size: 13px;
          font-weight: 500;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .progress-status {
          font-size: 12px;
          font-weight: 600;
        }

        .progress-bar {
          height: 6px;
          background: #e0e0e0;
          border-radius: 3px;
          overflow: hidden;
        }

        .progress-fill {
          height: 100%;
          background: #007bff;
          transition: width 0.3s ease;
        }

        .progress-fill.completed {
          background: #28a745;
        }

        .progress-fill.error {
          background: #dc3545;
        }

        .progress-error {
          margin-top: 4px;
          font-size: 12px;
          color: #dc3545;
        }

        .error-message {
          margin: 16px 0;
          padding: 12px;
          background: #fee;
          color: #c33;
          border-radius: 8px;
          font-size: 14px;
          white-space: pre-line;
        }

        @media (max-width: 768px) {
          .post-creator {
            padding: 16px;
          }

          .upload-buttons {
            flex-direction: column;
          }

          .btn-secondary {
            width: 100%;
          }
        }
      `}</style>
    </div>
  );
};

export default PostCreator;
