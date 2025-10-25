/**
 * PostCreator Component Tests
 */

import { describe, it, expect, vi } from 'vitest';
import { validatePhotoFile, validateVideoFile } from '../../../services/api/postService';

describe('PostCreator - File Validation', () => {
  describe('Photo validation', () => {
    it('should accept valid JPEG photo', () => {
      const file = new File([''], 'photo.jpg', {
        type: 'image/jpeg',
      });
      Object.defineProperty(file, 'size', { value: 2 * 1024 * 1024 }); // 2MB

      const result = validatePhotoFile(file);
      expect(result.valid).toBe(true);
      expect(result.error).toBeUndefined();
    });

    it('should reject file that is too small', () => {
      const file = new File([''], 'small.jpg', {
        type: 'image/jpeg',
      });
      Object.defineProperty(file, 'size', { value: 50 * 1024 }); // 50KB

      const result = validatePhotoFile(file);
      expect(result.valid).toBe(false);
      expect(result.error).toContain('too small');
    });

    it('should reject file that is too large', () => {
      const file = new File([''], 'large.jpg', {
        type: 'image/jpeg',
      });
      Object.defineProperty(file, 'size', { value: 60 * 1024 * 1024 }); // 60MB

      const result = validatePhotoFile(file);
      expect(result.valid).toBe(false);
      expect(result.error).toContain('too large');
    });

    it('should reject unsupported file type', () => {
      const file = new File([''], 'document.pdf', {
        type: 'application/pdf',
      });
      Object.defineProperty(file, 'size', { value: 2 * 1024 * 1024 });

      const result = validatePhotoFile(file);
      expect(result.valid).toBe(false);
      expect(result.error).toContain('Invalid file type');
    });
  });

  describe('Video validation', () => {
    it('should accept valid MP4 video', () => {
      const file = new File([''], 'video.mp4', {
        type: 'video/mp4',
      });
      Object.defineProperty(file, 'size', { value: 50 * 1024 * 1024 }); // 50MB

      const result = validateVideoFile(file);
      expect(result.valid).toBe(true);
      expect(result.error).toBeUndefined();
    });

    it('should reject video that is too large', () => {
      const file = new File([''], 'large.mp4', {
        type: 'video/mp4',
      });
      Object.defineProperty(file, 'size', { value: 600 * 1024 * 1024 }); // 600MB

      const result = validateVideoFile(file);
      expect(result.valid).toBe(false);
      expect(result.error).toContain('too large');
    });

    it('should reject unsupported video type', () => {
      const file = new File([''], 'video.avi', {
        type: 'video/avi',
      });
      Object.defineProperty(file, 'size', { value: 50 * 1024 * 1024 });

      const result = validateVideoFile(file);
      expect(result.valid).toBe(false);
      expect(result.error).toContain('Invalid file type');
    });
  });
});
