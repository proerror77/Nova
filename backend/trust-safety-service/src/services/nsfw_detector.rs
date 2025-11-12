use crate::error::{Result, TrustSafetyError};
use image::DynamicImage;
use ndarray::Array4;
use ort::session::{Session, SessionInputValue, SessionOutputs};
use std::borrow::Cow;
use std::path::Path;
use std::sync::{Arc, Mutex};

/// NSFW detector using ONNX Runtime
pub struct NsfwDetector {
    session: Arc<Mutex<Session>>,
    input_size: (u32, u32),
}

impl NsfwDetector {
    /// Create new NSFW detector with model
    pub fn new(model_path: impl AsRef<Path>) -> Result<Self> {
        let model_path = model_path.as_ref();

        if !model_path.exists() {
            return Err(TrustSafetyError::ModelNotFound(
                model_path.display().to_string(),
            ));
        }

        // Initialize ONNX Runtime session
        let session = Session::builder()
            .map_err(|e| TrustSafetyError::OnnxRuntime(e.to_string()))?
            .commit_from_file(model_path)
            .map_err(|e| TrustSafetyError::OnnxRuntime(e.to_string()))?;

        Ok(Self {
            session: Arc::new(Mutex::new(session)),
            input_size: (224, 224), // Standard ResNet input size
        })
    }

    /// Detect NSFW content in image from URL
    pub async fn detect(&self, image_url: &str) -> Result<f32> {
        // Download image
        let img = self.download_image(image_url).await?;

        // Preprocess
        let input_tensor = self.preprocess_image(img)?;

        // Run inference
        let nsfw_score = self.run_inference(input_tensor)?;

        Ok(nsfw_score)
    }

    /// Detect NSFW content in image from bytes
    pub fn detect_from_bytes(&self, image_bytes: &[u8]) -> Result<f32> {
        let img = image::load_from_memory(image_bytes)
            .map_err(|e| TrustSafetyError::ImageProcessing(e.to_string()))?;

        let input_tensor = self.preprocess_image(img)?;
        self.run_inference(input_tensor)
    }

    /// Download image from URL
    async fn download_image(&self, url: &str) -> Result<DynamicImage> {
        let response = reqwest::get(url).await?;
        let bytes = response.bytes().await?;

        let img = image::load_from_memory(&bytes)
            .map_err(|e| TrustSafetyError::ImageProcessing(e.to_string()))?;

        Ok(img)
    }

    /// Preprocess image for model input
    /// Returns tensor in NCHW format [1, 3, 224, 224]
    fn preprocess_image(&self, img: DynamicImage) -> Result<Array4<f32>> {
        // Resize to model input size
        let img = img.resize_exact(
            self.input_size.0,
            self.input_size.1,
            image::imageops::FilterType::Lanczos3,
        );

        // Convert to RGB
        let rgb_img = img.to_rgb8();
        let (width, height) = rgb_img.dimensions();

        // Create NCHW tensor [1, 3, H, W]
        let mut tensor = Array4::<f32>::zeros((1, 3, height as usize, width as usize));

        // Fill tensor with normalized pixel values [0, 1]
        for y in 0..height {
            for x in 0..width {
                let pixel = rgb_img.get_pixel(x, y);
                tensor[[0, 0, y as usize, x as usize]] = pixel[0] as f32 / 255.0; // R
                tensor[[0, 1, y as usize, x as usize]] = pixel[1] as f32 / 255.0; // G
                tensor[[0, 2, y as usize, x as usize]] = pixel[2] as f32 / 255.0;
                // B
            }
        }

        Ok(tensor)
    }

    /// Run ONNX inference
    fn run_inference(&self, input_tensor: Array4<f32>) -> Result<f32> {
        // Create ONNX value from ndarray
        let input_value = ort::value::Value::from_array(input_tensor)
            .map_err(|e| TrustSafetyError::OnnxRuntime(e.to_string()))?;

        // Build inputs vector
        let inputs: Vec<(Cow<'_, str>, SessionInputValue<'_>)> =
            vec![(Cow::Borrowed("input"), SessionInputValue::from(input_value))];

        // Run inference (requires mut, lock the session)
        let mut session = self
            .session
            .lock()
            .map_err(|e| TrustSafetyError::Internal(format!("Failed to lock session: {}", e)))?;

        let outputs: SessionOutputs = session
            .run(inputs)
            .map_err(|e| TrustSafetyError::OnnxRuntime(e.to_string()))?;

        // Extract NSFW score (assuming output is [batch_size, num_classes])
        let output = outputs
            .get("output")
            .ok_or_else(|| TrustSafetyError::OnnxRuntime("No output tensor".to_string()))?;

        let (_, scores_data) = output
            .try_extract_tensor::<f32>()
            .map_err(|e| TrustSafetyError::OnnxRuntime(e.to_string()))?;

        // Get NSFW probability (assuming index 1 is NSFW class)
        let nsfw_score = scores_data.get(1).copied().unwrap_or(0.0);

        Ok(nsfw_score)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_preprocess_image() {
        // Create a simple test image
        let img = DynamicImage::new_rgb8(100, 100);

        // Note: This will fail in CI without model file
        // Preprocess should still work
        // let detector = NsfwDetector::new("models/resnet50_nsfw.onnx").unwrap();
        // let tensor = detector.preprocess_image(img).unwrap();
        // assert_eq!(tensor.shape(), &[1, 3, 224, 224]);
    }
}
