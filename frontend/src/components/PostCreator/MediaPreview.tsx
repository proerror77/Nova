/**
 * MediaPreview Component
 * Shows preview of selected photos and videos before upload
 */

import React from 'react';

interface MediaPreviewProps {
  files: File[];
  onRemove: (index: number) => void;
}

const MediaPreview: React.FC<MediaPreviewProps> = ({ files, onRemove }) => {
  const [previews, setPreviews] = React.useState<string[]>([]);

  React.useEffect(() => {
    // Generate preview URLs for all files
    const urls = files.map(file => URL.createObjectURL(file));
    setPreviews(urls);

    // Cleanup URLs on unmount
    return () => {
      urls.forEach(url => URL.revokeObjectURL(url));
    };
  }, [files]);

  if (files.length === 0) {
    return null;
  }

  return (
    <div className="media-preview">
      <div className="preview-grid">
        {files.map((file, index) => {
          const isVideo = file.type.startsWith('video/');

          return (
            <div key={index} className="preview-item">
              <button
                type="button"
                className="remove-btn"
                onClick={() => onRemove(index)}
                aria-label={`Remove ${file.name}`}
              >
                ×
              </button>

              {isVideo ? (
                <video
                  src={previews[index]}
                  controls
                  className="preview-media"
                  aria-label={file.name}
                >
                  Your browser does not support video preview
                </video>
              ) : (
                <img
                  src={previews[index]}
                  alt={file.name}
                  className="preview-media"
                />
              )}

              <div className="file-info">
                <span className="file-name" title={file.name}>
                  {file.name}
                </span>
                <span className="file-size">
                  {(file.size / 1024 / 1024).toFixed(2)} MB
                </span>
              </div>
            </div>
          );
        })}
      </div>

      <style>{`
        .media-preview {
          margin: 16px 0;
          padding: 16px;
          background: #f5f5f5;
          border-radius: 8px;
        }

        .preview-grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
          gap: 16px;
        }

        .preview-item {
          position: relative;
          background: white;
          border-radius: 8px;
          overflow: hidden;
          box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
        }

        .remove-btn {
          position: absolute;
          top: 8px;
          right: 8px;
          width: 32px;
          height: 32px;
          background: rgba(0, 0, 0, 0.7);
          color: white;
          border: none;
          border-radius: 50%;
          font-size: 24px;
          line-height: 1;
          cursor: pointer;
          z-index: 10;
          transition: background 0.2s;
        }

        .remove-btn:hover {
          background: rgba(255, 0, 0, 0.8);
        }

        .remove-btn:focus {
          outline: 2px solid #007bff;
          outline-offset: 2px;
        }

        .preview-media {
          width: 100%;
          height: 200px;
          object-fit: cover;
          display: block;
        }

        .file-info {
          padding: 8px;
          display: flex;
          flex-direction: column;
          gap: 4px;
        }

        .file-name {
          font-size: 12px;
          font-weight: 500;
          white-space: nowrap;
          overflow: hidden;
          text-overflow: ellipsis;
        }

        .file-size {
          font-size: 11px;
          color: #666;
        }

        @media (max-width: 768px) {
          .preview-grid {
            grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
            gap: 12px;
          }

          .preview-media {
            height: 150px;
          }
        }
      `}</style>
    </div>
  );
};

export default MediaPreview;
