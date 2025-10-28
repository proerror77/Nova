/// Video Transcoding Service
///
/// Handles FFmpeg-based video transcoding, thumbnail extraction, and metadata parsing.
/// Manages the video processing pipeline for multi-quality output.
use crate::config::video_config::VideoProcessingConfig;
use crate::error::{AppError, Result};
use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use tracing::debug;

/// Video transcoding service
pub struct VideoTranscodingService {
    cfg: VideoProcessingConfig,
}

impl VideoTranscodingService {
    /// Create new transcoding service
    pub fn new(cfg: VideoProcessingConfig) -> Self {
        Self { cfg }
    }

    /// Extract video metadata using FFprobe
    pub async fn extract_metadata(&self, input_file: &Path) -> Result<VideoMetadata> {
        if !input_file.exists() {
            return Err(AppError::NotFound("input video not found".into()));
        }
        if self.cfg.enable_mock {
            return Ok(VideoMetadata {
                duration_seconds: 1,
                video_codec: "h264".into(),
                resolution: (1280, 720),
                frame_rate: 30.0,
                bitrate_kbps: 2500,
                audio_codec: Some("aac".into()),
                audio_sample_rate: Some(48000),
            });
        }

        // Use ffprobe to gather metadata in JSON
        let ffprobe = Command::new("ffprobe")
            .args([
                "-v",
                "error",
                "-show_streams",
                "-show_format",
                "-of",
                "json",
                input_file.to_string_lossy().as_ref(),
            ])
            .output()
            .map_err(|e| AppError::Internal(format!("ffprobe spawn error: {}", e)))?;
        if !ffprobe.status.success() {
            return Err(AppError::Internal("ffprobe failed".into()));
        }
        let json: Value = serde_json::from_slice(&ffprobe.stdout)
            .map_err(|e| AppError::Internal(format!("ffprobe json parse: {}", e)))?;
        // Extract fields
        let mut width = 0u32;
        let mut height = 0u32;
        let mut vcodec = String::new();
        let mut fps = 30.0f32;
        let mut br_kbps = 0u32;
        let mut acodec = None;
        let mut asr = None;

        if let Some(streams) = json.get("streams").and_then(|v| v.as_array()) {
            for s in streams {
                let codec_type = s.get("codec_type").and_then(|v| v.as_str()).unwrap_or("");
                if codec_type == "video" {
                    width = s.get("width").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
                    height = s.get("height").and_then(|v| v.as_u64()).unwrap_or(0) as u32;
                    vcodec = s
                        .get("codec_name")
                        .and_then(|v| v.as_str())
                        .unwrap_or("")
                        .to_string();
                    if let Some(r) = s.get("avg_frame_rate").and_then(|v| v.as_str()) {
                        if let Some((n, d)) = r.split_once('/') {
                            if let (Ok(n), Ok(d)) = (n.parse::<f32>(), d.parse::<f32>()) {
                                if d > 0.0 {
                                    fps = n / d;
                                }
                            }
                        }
                    }
                    br_kbps = s
                        .get("bit_rate")
                        .and_then(|v| v.as_str())
                        .and_then(|s| s.parse::<u32>().ok())
                        .unwrap_or(0)
                        / 1000;
                } else if codec_type == "audio" {
                    acodec = s
                        .get("codec_name")
                        .and_then(|v| v.as_str())
                        .map(|s| s.to_string());
                    asr = s
                        .get("sample_rate")
                        .and_then(|v| v.as_str())
                        .and_then(|s| s.parse::<u32>().ok());
                }
            }
        }
        let duration_seconds = json
            .get("format")
            .and_then(|f| f.get("duration"))
            .and_then(|d| d.as_str())
            .and_then(|s| s.parse::<f32>().ok())
            .unwrap_or(0.0)
            .ceil() as u32;

        Ok(VideoMetadata {
            duration_seconds: duration_seconds.max(1),
            video_codec: if vcodec.is_empty() {
                "unknown".into()
            } else {
                vcodec
            },
            resolution: (width.max(1), height.max(1)),
            frame_rate: fps,
            bitrate_kbps: br_kbps,
            audio_codec: acodec,
            audio_sample_rate: asr,
        })
    }

    /// Generate thumbnail from video
    pub async fn generate_thumbnail(&self, input_file: &Path, output_file: &Path) -> Result<()> {
        if self.cfg.enable_mock {
            if let Some(parent) = output_file.parent() {
                let _ = fs::create_dir_all(parent);
            }
            fs::write(output_file, &[])?;
            return Ok(());
        }
        if let Some(parent) = output_file.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let status = Command::new(&self.cfg.ffmpeg_path)
            .args([
                "-y",
                "-ss",
                "00:00:01",
                "-i",
                input_file.to_string_lossy().as_ref(),
                "-frames:v",
                "1",
                output_file.to_string_lossy().as_ref(),
            ])
            .status()
            .map_err(|e| AppError::Internal(format!("ffmpeg spawn error: {}", e)))?;
        if !status.success() {
            return Err(AppError::Internal("ffmpeg thumbnail failed".into()));
        }
        Ok(())
    }

    /// Transcode video to multiple bitrates
    pub async fn transcode_to_bitrates(
        &self,
        input_file: &Path,
        output_dir: &Path,
        bitrates: Vec<u32>,
    ) -> Result<Vec<PathBuf>> {
        if !input_file.exists() {
            return Err(AppError::NotFound("input video not found".into()));
        }
        let _ = fs::create_dir_all(output_dir);
        let mut outputs = Vec::new();
        if self.cfg.enable_mock {
            for br in bitrates {
                let p = output_dir.join(format!("output_{}kbps.mp4", br));
                fs::write(&p, &[])?;
                outputs.push(p);
            }
            return Ok(outputs);
        }
        for br in bitrates {
            let out = output_dir.join(format!("output_{}kbps.mp4", br));
            let br_arg = format!("{}k", br);
            let status = Command::new(&self.cfg.ffmpeg_path)
                .args([
                    "-y",
                    "-i",
                    input_file.to_string_lossy().as_ref(),
                    "-c:v",
                    "libx264",
                    "-b:v",
                    &br_arg,
                    "-preset",
                    "veryfast",
                    "-c:a",
                    "aac",
                    out.to_string_lossy().as_ref(),
                ])
                .status()
                .map_err(|e| AppError::Internal(format!("ffmpeg spawn error: {}", e)))?;
            if !status.success() {
                return Err(AppError::Internal("ffmpeg transcode failed".into()));
            }
            outputs.push(out);
        }
        Ok(outputs)
    }

    /// Get supported codecs
    pub fn get_supported_codecs(&self) -> Vec<String> {
        vec!["h264".to_string(), "hevc".to_string(), "vp9".to_string()]
    }

    // Pipeline 适配的附加方法
    pub async fn validate_video_file(&self, path: &Path) -> Result<()> {
        if !path.exists() {
            return Err(AppError::NotFound("input video not found".into()));
        }
        Ok(())
    }

    pub async fn create_transcoding_jobs(
        &self,
        video_id: &str,
        input_file: &Path,
    ) -> Result<Vec<String>> {
        debug!("create jobs for {} from {}", video_id, input_file.display());
        Ok(vec!["360p".into(), "480p".into(), "720p".into()])
    }

    pub async fn extract_thumbnail(&self, input: &Path, output: &Path, _second: u32) -> Result<()> {
        self.generate_thumbnail(input, output).await
    }

    pub fn get_config_summary(&self) -> std::collections::HashMap<String, String> {
        let mut m = std::collections::HashMap::new();
        m.insert("ffmpeg_path".into(), self.cfg.ffmpeg_path.clone());
        m.insert(
            "targets".into(),
            format!("{}", self.cfg.target_bitrates.len()),
        );
        m.insert("mock".into(), format!("{}", self.cfg.enable_mock));
        m
    }
}

/// Video file information extracted via FFprobe
#[derive(Debug, Clone)]
pub struct VideoMetadata {
    pub duration_seconds: u32,
    pub video_codec: String,
    pub resolution: (u32, u32),
    pub frame_rate: f32,
    pub bitrate_kbps: u32,
    pub audio_codec: Option<String>,
    pub audio_sample_rate: Option<u32>,
}
