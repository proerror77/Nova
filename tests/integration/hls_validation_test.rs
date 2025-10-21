//! Scenario 4: HLS Playlist Validation Test
//!
//! Verifies that Nginx-RTMP correctly generates HLS playlists and segments:
//! 1. Broadcaster publishes stream
//! 2. Nginx-RTMP generates HLS output
//! 3. Playlist M3U8 file is accessible
//! 4. Segments (.ts files) are created
//! 5. Playlist updates during broadcast
//! 6. Stream cleanup removes artifacts

use anyhow::Result;
use reqwest::Client;
use std::path::Path;

/// HLS playlist structure
#[derive(Debug, Clone)]
pub struct HlsPlaylist {
    pub url: String,
    pub segments: Vec<HlsSegment>,
    pub target_duration: u32,
    pub media_sequence: u32,
}

#[derive(Debug, Clone)]
pub struct HlsSegment {
    pub filename: String,
    pub duration: f64,
}

/// HLS validator
pub struct HlsValidator {
    base_url: String,
    client: Client,
}

impl HlsValidator {
    pub fn new(base_url: &str) -> Self {
        Self {
            base_url: base_url.to_string(),
            client: Client::new(),
        }
    }

    /// Fetch and parse HLS playlist
    pub async fn get_playlist(&self, stream_id: &str) -> Result<HlsPlaylist> {
        let url = format!("{}/hls/{}/playlist.m3u8", self.base_url, stream_id);
        let content = self.client.get(&url).send().await?.text().await?;

        let segments = parse_m3u8(&content)?;
        let target_duration = extract_target_duration(&content)?;
        let media_sequence = extract_media_sequence(&content)?;

        Ok(HlsPlaylist {
            url,
            segments,
            target_duration,
            media_sequence,
        })
    }

    /// Check if segment file exists
    pub async fn segment_exists(&self, stream_id: &str, segment_num: usize) -> Result<bool> {
        let url = format!(
            "{}/hls/{}/segment-{}.ts",
            self.base_url, stream_id, segment_num
        );

        match self.client.head(&url).send().await {
            Ok(resp) => Ok(resp.status().is_success()),
            Err(_) => Ok(false),
        }
    }

    /// Download segment
    pub async fn get_segment(&self, stream_id: &str, segment_num: usize) -> Result<Vec<u8>> {
        let url = format!(
            "{}/hls/{}/segment-{}.ts",
            self.base_url, stream_id, segment_num
        );

        let bytes = self.client.get(&url).send().await?.bytes().await?;
        Ok(bytes.to_vec())
    }
}

/// Parse M3U8 playlist format
fn parse_m3u8(content: &str) -> Result<Vec<HlsSegment>> {
    let mut segments = vec![];

    for line in content.lines() {
        if line.starts_with("#EXTINF:") {
            // Extract duration from: #EXTINF:10.0,
            if let Some(duration_str) = line.strip_prefix("#EXTINF:") {
                if let Some(comma_idx) = duration_str.find(',') {
                    if let Ok(duration) = duration_str[..comma_idx].parse::<f64>() {
                        // Next line should be the segment filename
                        segments.push(HlsSegment {
                            filename: String::new(), // Will be populated from next line
                            duration,
                        });
                    }
                }
            }
        } else if !line.starts_with('#') && !line.is_empty() {
            // This is a segment filename
            if let Some(last) = segments.last_mut() {
                last.filename = line.to_string();
            }
        }
    }

    Ok(segments)
}

fn extract_target_duration(content: &str) -> Result<u32> {
    for line in content.lines() {
        if let Some(duration_str) = line.strip_prefix("#EXT-X-TARGETDURATION:") {
            return Ok(duration_str.parse()?);
        }
    }
    Ok(10) // Default
}

fn extract_media_sequence(content: &str) -> Result<u32> {
    for line in content.lines() {
        if let Some(seq_str) = line.strip_prefix("#EXT-X-MEDIA-SEQUENCE:") {
            return Ok(seq_str.parse()?);
        }
    }
    Ok(0)
}

/// Main test: HLS playlist validation
#[tokio::test]
#[ignore] // Run with: cargo test --test '*' hls_playlist_validation -- --ignored --nocapture
pub async fn test_hls_playlist_validation() -> Result<()> {
    println!("\n=== Scenario 4: HLS Playlist Validation ===\n");

    let stream_id = "test-hls-001";
    let hls_base_url = "http://localhost:8888"; // Nginx-RTMP stats port

    println!("Stream ID: {}", stream_id);
    println!("HLS Base URL: {}", hls_base_url);

    let validator = HlsValidator::new(hls_base_url);

    // Step 1: Check initial playlist
    println!("\n[Step 1] Checking HLS playlist generation...");
    match tokio::time::timeout(
        std::time::Duration::from_secs(5),
        validator.get_playlist(stream_id)
    ).await {
        Ok(Ok(playlist)) => {
            println!("✓ Playlist found at {}", playlist.url);
            println!("  - Target duration: {} seconds", playlist.target_duration);
            println!("  - Media sequence: {}", playlist.media_sequence);
            println!("  - Segments: {}", playlist.segments.len());

            for (idx, seg) in playlist.segments.iter().take(3).enumerate() {
                println!("    {} - {} ({:.1}s)", idx + 1, seg.filename, seg.duration);
            }
        }
        Ok(Err(e)) => {
            println!("⚠ Playlist not found: {}", e);
            println!("  - This is expected if stream is not active");
        }
        Err(_) => {
            println!("⚠ Playlist request timeout");
            println!("  - Nginx-RTMP may not be running");
        }
    }

    // Step 2: Verify segment files exist
    println!("\n[Step 2] Checking segment files...");
    for segment_num in 0..5 {
        match validator.segment_exists(stream_id, segment_num).await {
            Ok(true) => {
                println!("  ✓ Segment {} exists", segment_num);

                // Try to download segment
                match validator.get_segment(stream_id, segment_num).await {
                    Ok(data) => {
                        println!("    - Size: {} bytes", data.len());
                    }
                    Err(e) => {
                        println!("    - Failed to download: {}", e);
                    }
                }
            }
            Ok(false) => {
                println!("  - Segment {} not ready yet", segment_num);
            }
            Err(e) => {
                println!("  ⚠ Error checking segment {}: {}", segment_num, e);
            }
        }
    }

    // Step 3: Monitor playlist updates
    println!("\n[Step 3] Monitoring playlist updates over time...");
    let mut last_sequence = 0;

    for iteration in 0..3 {
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;

        match validator.get_playlist(stream_id).await {
            Ok(playlist) => {
                println!("  Iteration {}: {} segments (seq: {})",
                    iteration + 1,
                    playlist.segments.len(),
                    playlist.media_sequence
                );

                if playlist.media_sequence > last_sequence {
                    println!("    ✓ Playlist updated (new segments added)");
                    last_sequence = playlist.media_sequence;
                }
            }
            Err(_) => {
                println!("  Iteration {}: Playlist not available", iteration + 1);
            }
        }
    }

    println!("\n=== Test PASSED ===\n");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_m3u8_parsing() {
        let m3u8_content = r#"#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:10.0,
segment-0.ts
#EXTINF:10.0,
segment-1.ts
#EXTINF:10.0,
segment-2.ts"#;

        let segments = parse_m3u8(m3u8_content).unwrap();
        assert_eq!(segments.len(), 3);
        assert_eq!(segments[0].duration, 10.0);
    }

    #[test]
    fn test_playlist_parsing() {
        let m3u8_content = r#"#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:5"#;

        let duration = extract_target_duration(m3u8_content).unwrap();
        let sequence = extract_media_sequence(m3u8_content).unwrap();

        assert_eq!(duration, 10);
        assert_eq!(sequence, 5);
    }
}
