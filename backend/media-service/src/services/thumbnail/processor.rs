//! Thumbnail processor - generates thumbnails from original images
//!
//! Takes an image, resizes it to the specified max dimension while maintaining aspect ratio,
//! and encodes it as JPEG with configurable quality.
//!
//! Uses `spawn_blocking` for CPU-intensive operations to avoid blocking the async runtime.

use crate::error::{AppError, Result};
use bytes::Bytes;
use image::imageops::FilterType;
use image::{DynamicImage, GenericImageView, ImageOutputFormat};
use std::io::Cursor;
use std::sync::Arc;
use tracing::debug;

/// Configuration for thumbnail generation
#[derive(Clone, Debug)]
pub struct ThumbnailConfig {
    /// Maximum dimension (width or height) in pixels
    pub max_dimension: u32,
    /// JPEG quality (0-100)
    pub quality: u8,
}

impl Default for ThumbnailConfig {
    fn default() -> Self {
        Self {
            max_dimension: 600,
            quality: 85,
        }
    }
}

/// Result of thumbnail generation
#[derive(Debug)]
pub struct ThumbnailResult {
    /// The thumbnail image data as JPEG
    pub data: Bytes,
    /// Width of the thumbnail
    pub width: u32,
    /// Height of the thumbnail
    pub height: u32,
}

/// Thumbnail processor
pub struct ThumbnailProcessor {
    config: ThumbnailConfig,
}

impl ThumbnailProcessor {
    /// Create a new processor with the given configuration
    pub fn new(config: ThumbnailConfig) -> Self {
        Self { config }
    }

    /// Create a processor with default configuration
    pub fn with_defaults() -> Self {
        Self::new(ThumbnailConfig::default())
    }

    /// Generate a thumbnail from the given image data (blocking version)
    ///
    /// **Note:** This method performs CPU-intensive operations and should not be called
    /// directly from async code. Use `generate_async` instead.
    pub fn generate(&self, original_data: &[u8]) -> Result<ThumbnailResult> {
        // Decode the image
        let img = image::load_from_memory(original_data)
            .map_err(|e| AppError::Internal(format!("Failed to decode image: {e}")))?;

        let (orig_w, orig_h) = img.dimensions();
        debug!(
            original_width = orig_w,
            original_height = orig_h,
            "Processing image for thumbnail"
        );

        // Calculate new dimensions maintaining aspect ratio
        let (new_w, new_h) = self.calculate_dimensions(orig_w, orig_h);

        // Skip if image is already smaller than max dimension
        if orig_w <= self.config.max_dimension && orig_h <= self.config.max_dimension {
            debug!("Image already within max dimensions, encoding as-is");
            let data = self.encode_jpeg(&img)?;
            return Ok(ThumbnailResult {
                data,
                width: orig_w,
                height: orig_h,
            });
        }

        // Resize with high-quality filter
        let resized = img.resize_exact(new_w.max(1), new_h.max(1), FilterType::Triangle);

        // Encode as JPEG
        let data = self.encode_jpeg(&resized)?;

        debug!(
            width = new_w,
            height = new_h,
            size = data.len(),
            "Thumbnail generated"
        );

        Ok(ThumbnailResult {
            data,
            width: new_w,
            height: new_h,
        })
    }

    /// Generate a thumbnail asynchronously using a blocking thread pool
    ///
    /// This method offloads the CPU-intensive image processing to a dedicated
    /// thread pool, preventing the async runtime from being blocked.
    ///
    /// # Example
    /// ```ignore
    /// let processor = ThumbnailProcessor::with_defaults();
    /// let result = processor.generate_async(image_bytes).await?;
    /// ```
    pub async fn generate_async(self: Arc<Self>, original_data: Bytes) -> Result<ThumbnailResult> {
        let processor = self.clone();

        tokio::task::spawn_blocking(move || processor.generate(&original_data))
            .await
            .map_err(|e| AppError::Internal(format!("Thumbnail task panicked: {e}")))?
    }

    /// Generate multiple thumbnails in parallel
    ///
    /// Processes multiple images concurrently, each on its own blocking thread.
    /// Returns results in the same order as the input.
    pub async fn generate_batch_async(
        self: Arc<Self>,
        images: Vec<Bytes>,
    ) -> Vec<Result<ThumbnailResult>> {
        let handles: Vec<_> = images
            .into_iter()
            .map(|data| {
                let processor = self.clone();
                tokio::task::spawn_blocking(move || processor.generate(&data))
            })
            .collect();

        let mut results = Vec::with_capacity(handles.len());
        for handle in handles {
            let result = match handle.await {
                Ok(r) => r,
                Err(e) => Err(AppError::Internal(format!("Thumbnail task panicked: {e}"))),
            };
            results.push(result);
        }
        results
    }

    /// Calculate new dimensions maintaining aspect ratio
    fn calculate_dimensions(&self, width: u32, height: u32) -> (u32, u32) {
        let max_dim = self.config.max_dimension;

        if width > height {
            let ratio = max_dim as f32 / width as f32;
            (max_dim, ((height as f32) * ratio).round() as u32)
        } else {
            let ratio = max_dim as f32 / height as f32;
            (((width as f32) * ratio).round() as u32, max_dim)
        }
    }

    /// Encode image as JPEG
    fn encode_jpeg(&self, img: &DynamicImage) -> Result<Bytes> {
        let mut buf = Vec::new();
        let mut cursor = Cursor::new(&mut buf);

        img.write_to(&mut cursor, ImageOutputFormat::Jpeg(self.config.quality))
            .map_err(|e| AppError::Internal(format!("Failed to encode JPEG: {e}")))?;

        Ok(Bytes::from(buf))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculate_dimensions_landscape() {
        let processor = ThumbnailProcessor::with_defaults();
        let (w, h) = processor.calculate_dimensions(1200, 800);
        assert_eq!(w, 600);
        assert_eq!(h, 400);
    }

    #[test]
    fn test_calculate_dimensions_portrait() {
        let processor = ThumbnailProcessor::with_defaults();
        let (w, h) = processor.calculate_dimensions(800, 1200);
        assert_eq!(w, 400);
        assert_eq!(h, 600);
    }

    #[test]
    fn test_calculate_dimensions_square() {
        let processor = ThumbnailProcessor::with_defaults();
        let (w, h) = processor.calculate_dimensions(1000, 1000);
        assert_eq!(w, 600);
        assert_eq!(h, 600);
    }
}
