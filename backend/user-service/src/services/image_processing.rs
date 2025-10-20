/// Image processing service for resizing and converting images to different variants
/// Supports JPEG, PNG, WEBP, and HEIC formats
/// Generates three size variants: thumbnail (150x150), medium (600x600), original (max 4000x4000)
use image::{imageops::FilterType, DynamicImage, GenericImageView};
use std::path::{Path, PathBuf};
use thiserror::Error;

/// Image size specifications for different variants
const THUMBNAIL_SIZE: u32 = 150;
const MEDIUM_SIZE: u32 = 600;
const ORIGINAL_MAX_SIZE: u32 = 4000;

const THUMBNAIL_QUALITY: u8 = 80;
const MEDIUM_QUALITY: u8 = 85;
const ORIGINAL_QUALITY: u8 = 90;

const THUMBNAIL_MAX_BYTES: usize = 30 * 1024; // 30KB
const MEDIUM_MAX_BYTES: usize = 100 * 1024; // 100KB
const ORIGINAL_MAX_BYTES: usize = 2 * 1024 * 1024; // 2MB

const MIN_IMAGE_SIZE: u32 = 50;

#[derive(Debug, Error)]
pub enum ImageProcessingError {
    #[error("Invalid image format: {0}")]
    InvalidFormat(String),

    #[error("Image too small: {0}x{1}px (minimum: {2}px)")]
    ImageTooSmall(u32, u32, u32),

    #[error("Image too large: {0}x{1}px (maximum: {2}px)")]
    ImageTooLarge(u32, u32, u32),

    #[error("IO error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("Image processing error: {0}")]
    ProcessingError(#[from] image::ImageError),

    #[error("File size exceeds limit: {0} bytes (max: {1} bytes)")]
    FileSizeTooLarge(usize, usize),
}

/// Result of processing an image variant
#[derive(Debug, Clone)]
pub struct ImageVariantResult {
    pub path: PathBuf,
    pub width: u32,
    pub height: u32,
    pub file_size: usize,
}

/// Results of processing all image variants
#[derive(Debug)]
pub struct ProcessedImageVariants {
    pub thumbnail: ImageVariantResult,
    pub medium: ImageVariantResult,
    pub original: ImageVariantResult,
}

/// Get dimensions of an image file
pub async fn get_image_dimensions(image_path: &Path) -> Result<(u32, u32), ImageProcessingError> {
    let img = tokio::task::spawn_blocking({
        let path = image_path.to_path_buf();
        move || image::open(&path)
    })
    .await
    .map_err(|e| {
        ImageProcessingError::ProcessingError(image::ImageError::IoError(std::io::Error::new(
            std::io::ErrorKind::Other,
            e,
        )))
    })??;

    Ok(img.dimensions())
}

/// Resize image to fit within max_width x max_height while preserving aspect ratio
/// Uses letterboxing (no cropping) to maintain the full image
fn resize_image(img: &DynamicImage, max_width: u32, max_height: u32) -> DynamicImage {
    let (width, height) = img.dimensions();

    // Calculate scaling to fit within bounds while preserving aspect ratio
    let width_ratio = max_width as f32 / width as f32;
    let height_ratio = max_height as f32 / height as f32;
    let ratio = width_ratio.min(height_ratio);

    // If image is already smaller than target, don't upscale
    if ratio >= 1.0 {
        return img.clone();
    }

    let new_width = (width as f32 * ratio) as u32;
    let new_height = (height as f32 * ratio) as u32;

    // Use Lanczos3 filter for high-quality downsampling
    img.resize(new_width, new_height, FilterType::Lanczos3)
}

/// Save image variant to disk as JPEG with specified quality
async fn save_image_variant(
    img: &DynamicImage,
    output_path: &Path,
    quality: u8,
    max_file_size: usize,
) -> Result<ImageVariantResult, ImageProcessingError> {
    let (width, height) = img.dimensions();

    // Convert to RGB8 for JPEG encoding (JPEG doesn't support transparency)
    let rgb_img = img.to_rgb8();

    // Save to disk
    let output_path_buf = output_path.to_path_buf();
    let result = tokio::task::spawn_blocking(move || {
        let mut encoder = image::codecs::jpeg::JpegEncoder::new_with_quality(
            std::fs::File::create(&output_path_buf)?,
            quality,
        );
        encoder.encode(rgb_img.as_raw(), width, height, image::ColorType::Rgb8)?;

        // Get file size
        let metadata = std::fs::metadata(&output_path_buf)?;
        let file_size = metadata.len() as usize;

        Ok::<_, ImageProcessingError>((output_path_buf, file_size))
    })
    .await
    .map_err(|e| {
        ImageProcessingError::ProcessingError(image::ImageError::IoError(std::io::Error::new(
            std::io::ErrorKind::Other,
            e,
        )))
    })??;

    let (path, file_size) = result;

    // Check file size
    if file_size > max_file_size {
        // Clean up oversized file
        let _ = tokio::fs::remove_file(&path).await;
        return Err(ImageProcessingError::FileSizeTooLarge(
            file_size,
            max_file_size,
        ));
    }

    Ok(ImageVariantResult {
        path,
        width,
        height,
        file_size,
    })
}

/// Process an image file into three variants: thumbnail, medium, and original
///
/// # Arguments
/// * `source_path` - Path to the source image file
/// * `output_dir` - Directory where variants will be saved
/// * `base_name` - Base name for output files (e.g., "post_id")
///
/// # Returns
/// ProcessedImageVariants containing paths and metadata for all three variants
pub async fn process_image_to_variants(
    source_path: &Path,
    output_dir: &Path,
    base_name: &str,
) -> Result<ProcessedImageVariants, ImageProcessingError> {
    // Load and validate the source image
    let img = tokio::task::spawn_blocking({
        let path = source_path.to_path_buf();
        move || {
            // Try to open the image and detect format
            let img = image::open(&path)?;
            Ok::<_, ImageProcessingError>(img)
        }
    })
    .await
    .map_err(|e| {
        ImageProcessingError::ProcessingError(image::ImageError::IoError(std::io::Error::new(
            std::io::ErrorKind::Other,
            e,
        )))
    })??;

    // Validate image dimensions
    let (width, height) = img.dimensions();

    if width < MIN_IMAGE_SIZE || height < MIN_IMAGE_SIZE {
        return Err(ImageProcessingError::ImageTooSmall(
            width,
            height,
            MIN_IMAGE_SIZE,
        ));
    }

    if width > ORIGINAL_MAX_SIZE || height > ORIGINAL_MAX_SIZE {
        return Err(ImageProcessingError::ImageTooLarge(
            width,
            height,
            ORIGINAL_MAX_SIZE,
        ));
    }

    // Create output directory if it doesn't exist
    tokio::fs::create_dir_all(output_dir).await?;

    // Generate thumbnail (150x150)
    let thumbnail_img = resize_image(&img, THUMBNAIL_SIZE, THUMBNAIL_SIZE);
    let thumbnail_path = output_dir.join(format!("{}_thumbnail.jpg", base_name));
    let thumbnail_result = save_image_variant(
        &thumbnail_img,
        &thumbnail_path,
        THUMBNAIL_QUALITY,
        THUMBNAIL_MAX_BYTES,
    )
    .await?;

    // Generate medium (600x600)
    let medium_img = resize_image(&img, MEDIUM_SIZE, MEDIUM_SIZE);
    let medium_path = output_dir.join(format!("{}_medium.jpg", base_name));
    let medium_result =
        save_image_variant(&medium_img, &medium_path, MEDIUM_QUALITY, MEDIUM_MAX_BYTES).await?;

    // Generate original (max 4000x4000)
    let original_img = resize_image(&img, ORIGINAL_MAX_SIZE, ORIGINAL_MAX_SIZE);
    let original_path = output_dir.join(format!("{}_original.jpg", base_name));
    let original_result = save_image_variant(
        &original_img,
        &original_path,
        ORIGINAL_QUALITY,
        ORIGINAL_MAX_BYTES,
    )
    .await?;

    Ok(ProcessedImageVariants {
        thumbnail: thumbnail_result,
        medium: medium_result,
        original: original_result,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{ImageBuffer, Rgb};
    use std::fs;
    use tempfile::TempDir;

    /// Helper function to create a test image with specified dimensions
    fn create_test_image(width: u32, height: u32, path: &Path) -> Result<(), image::ImageError> {
        let img: ImageBuffer<Rgb<u8>, Vec<u8>> = ImageBuffer::from_fn(width, height, |x, y| {
            // Create a gradient pattern
            let r = (x * 255 / width) as u8;
            let g = (y * 255 / height) as u8;
            let b = 128;
            Rgb([r, g, b])
        });

        let dynamic_img = DynamicImage::ImageRgb8(img);
        dynamic_img.save(path)?;
        Ok(())
    }

    #[tokio::test]
    async fn test_resize_to_thumbnail_size() {
        let temp_dir = TempDir::new().unwrap();
        let input_path = temp_dir.path().join("test.jpg");
        let output_dir = temp_dir.path().join("output");

        // Create a 1000x1000 test image
        create_test_image(1000, 1000, &input_path).unwrap();

        // Process image
        let result = process_image_to_variants(&input_path, &output_dir, "test").await;
        assert!(result.is_ok(), "Processing should succeed");

        let variants = result.unwrap();

        // Thumbnail should be 150x150 or smaller
        assert!(variants.thumbnail.width <= THUMBNAIL_SIZE);
        assert!(variants.thumbnail.height <= THUMBNAIL_SIZE);
        assert!(variants.thumbnail.file_size > 0);
        assert!(variants.thumbnail.file_size <= THUMBNAIL_MAX_BYTES);
    }

    #[tokio::test]
    async fn test_resize_to_medium_size() {
        let temp_dir = TempDir::new().unwrap();
        let input_path = temp_dir.path().join("test.jpg");
        let output_dir = temp_dir.path().join("output");

        // Create a 2000x2000 test image
        create_test_image(2000, 2000, &input_path).unwrap();

        // Process image
        let result = process_image_to_variants(&input_path, &output_dir, "test")
            .await
            .unwrap();

        // Medium should be 600x600 or smaller
        assert!(result.medium.width <= MEDIUM_SIZE);
        assert!(result.medium.height <= MEDIUM_SIZE);
        assert!(result.medium.file_size > 0);
        assert!(result.medium.file_size <= MEDIUM_MAX_BYTES);
    }

    #[tokio::test]
    async fn test_preserve_aspect_ratio() {
        let temp_dir = TempDir::new().unwrap();
        let input_path = temp_dir.path().join("test.jpg");
        let output_dir = temp_dir.path().join("output");

        // Create a rectangular image (800x400 = 2:1 ratio)
        create_test_image(800, 400, &input_path).unwrap();

        // Process image
        let result = process_image_to_variants(&input_path, &output_dir, "test")
            .await
            .unwrap();

        // Check that aspect ratio is preserved for thumbnail
        let thumbnail_ratio = result.thumbnail.width as f32 / result.thumbnail.height as f32;
        let original_ratio = 800.0 / 400.0;
        assert!(
            (thumbnail_ratio - original_ratio).abs() < 0.01,
            "Aspect ratio should be preserved"
        );

        // Thumbnail should fit within 150x150
        assert!(result.thumbnail.width <= THUMBNAIL_SIZE);
        assert!(result.thumbnail.height <= THUMBNAIL_SIZE);
    }

    #[tokio::test]
    async fn test_invalid_image_format() {
        let temp_dir = TempDir::new().unwrap();
        let input_path = temp_dir.path().join("test.txt");
        let output_dir = temp_dir.path().join("output");

        // Create a non-image file
        fs::write(&input_path, b"This is not an image").unwrap();

        // Process should fail
        let result = process_image_to_variants(&input_path, &output_dir, "test").await;
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            ImageProcessingError::ProcessingError(_)
        ));
    }

    #[tokio::test]
    async fn test_image_too_small() {
        let temp_dir = TempDir::new().unwrap();
        let input_path = temp_dir.path().join("test.jpg");
        let output_dir = temp_dir.path().join("output");

        // Create a 40x40 image (smaller than MIN_IMAGE_SIZE = 50)
        create_test_image(40, 40, &input_path).unwrap();

        // Process should fail
        let result = process_image_to_variants(&input_path, &output_dir, "test").await;
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            ImageProcessingError::ImageTooSmall(_, _, _)
        ));
    }

    #[tokio::test]
    async fn test_image_too_large() {
        let temp_dir = TempDir::new().unwrap();
        let input_path = temp_dir.path().join("test.jpg");
        let output_dir = temp_dir.path().join("output");

        // Create a 5000x5000 image (larger than ORIGINAL_MAX_SIZE = 4000)
        create_test_image(5000, 5000, &input_path).unwrap();

        // Process should fail
        let result = process_image_to_variants(&input_path, &output_dir, "test").await;
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            ImageProcessingError::ImageTooLarge(_, _, _)
        ));
    }

    #[tokio::test]
    async fn test_save_image_variant() {
        let temp_dir = TempDir::new().unwrap();
        let input_path = temp_dir.path().join("test.jpg");
        let output_path = temp_dir.path().join("output.jpg");

        // Create a test image
        create_test_image(500, 500, &input_path).unwrap();
        let img = image::open(&input_path).unwrap();

        // Save variant
        let result = save_image_variant(&img, &output_path, 85, 100 * 1024).await;
        assert!(result.is_ok(), "Saving variant should succeed");

        let variant = result.unwrap();
        assert_eq!(variant.width, 500);
        assert_eq!(variant.height, 500);
        assert!(variant.file_size > 0);
        assert!(output_path.exists());
    }

    #[tokio::test]
    async fn test_get_image_dimensions() {
        let temp_dir = TempDir::new().unwrap();
        let input_path = temp_dir.path().join("test.jpg");

        // Create a test image
        create_test_image(800, 600, &input_path).unwrap();

        // Get dimensions
        let result = get_image_dimensions(&input_path).await;
        assert!(result.is_ok());

        let (width, height) = result.unwrap();
        assert_eq!(width, 800);
        assert_eq!(height, 600);
    }
}
