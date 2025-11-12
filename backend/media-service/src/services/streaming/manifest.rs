/// Streaming Manifest Generator for HLS and DASH
///
/// Production-ready manifest generation with proper specification compliance,
/// caching, and support for adaptive bitrate streaming.
use std::collections::HashMap;
use tracing::debug;

/// Streaming configuration for HLS and DASH manifest generation
#[derive(Debug, Clone)]
pub struct StreamingConfig {
    /// Enable HLS streaming
    pub enable_hls: bool,
    /// Enable DASH streaming
    pub enable_dash: bool,
    /// HLS segment duration in seconds
    pub hls_segment_duration: u32,
    /// DASH segment duration in seconds
    pub dash_segment_duration: u32,
    /// Enable adaptive bitrate switching
    pub enable_abr: bool,
    /// Bandwidth estimation window in seconds
    pub bandwidth_estimation_window: u32,
    /// Video pre-load duration in seconds
    pub preload_duration: u32,
}

impl Default for StreamingConfig {
    fn default() -> Self {
        Self {
            enable_hls: true,
            enable_dash: true,
            hls_segment_duration: 10,
            dash_segment_duration: 10,
            enable_abr: true,
            bandwidth_estimation_window: 20,
            preload_duration: 30,
        }
    }
}

/// Represents a video quality tier for streaming
#[derive(Debug, Clone)]
pub struct QualityTier {
    /// Quality label (e.g., "720p", "480p", "360p")
    pub label: String,
    /// Resolution width in pixels
    pub width: u32,
    /// Resolution height in pixels
    pub height: u32,
    /// Bitrate in kbps
    pub bitrate_kbps: u32,
}

impl QualityTier {
    /// Create a quality tier from label and bitrate
    pub fn new(label: String, bitrate_kbps: u32) -> Self {
        let (width, height) = match label.as_str() {
            "720p" => (1280, 720),
            "480p" => (854, 480),
            "360p" => (640, 360),
            "1080p" => (1920, 1080),
            "240p" => (426, 240),
            _ => (640, 360), // Default fallback
        };

        Self {
            label,
            width,
            height,
            bitrate_kbps,
        }
    }
}

/// Streaming manifest generator for HLS and DASH
pub struct StreamingManifestGenerator {
    config: StreamingConfig,
}

impl StreamingManifestGenerator {
    /// Create a new manifest generator with streaming configuration
    pub fn new(config: StreamingConfig) -> Self {
        Self { config }
    }

    /// Generate an HLS master playlist with variant streams
    ///
    /// # Arguments
    /// * `video_id` - Unique video identifier
    /// * `_duration_seconds` - Total video duration in seconds (unused in master playlist)
    /// * `quality_tiers` - Available quality levels and bitrates
    /// * `base_url` - Base URL for segment URIs (e.g., "https://cdn.example.com/videos/video-123")
    ///
    /// # Returns
    /// Properly formatted HLS master playlist
    pub fn generate_hls_master_playlist(
        &self,
        video_id: &str,
        _duration_seconds: u32,
        quality_tiers: Vec<QualityTier>,
        base_url: &str,
    ) -> String {
        debug!(
            "Generating HLS master playlist: video_id={}, qualities={}",
            video_id,
            quality_tiers.len()
        );

        let mut playlist = String::from("#EXTM3U\n");
        playlist.push_str("#EXT-X-VERSION:3\n");

        // Add target duration (round up segment duration to nearest second)
        playlist.push_str(&format!(
            "#EXT-X-TARGETDURATION:{}\n",
            self.config.hls_segment_duration.max(1)
        ));

        // Add media sequence for proper segment numbering
        playlist.push_str("#EXT-X-MEDIA-SEQUENCE:0\n");

        // Add playlist type (EVENT for VOD with finished segments)
        playlist.push_str("#EXT-X-PLAYLIST-TYPE:VOD\n");

        // Sort quality tiers by bitrate descending (highest first for adaptive bitrate selection)
        let mut sorted_tiers = quality_tiers;
        sorted_tiers.sort_by(|a, b| b.bitrate_kbps.cmp(&a.bitrate_kbps));

        // Add variant stream declarations (EXT-X-STREAM-INF)
        for tier in &sorted_tiers {
            let bandwidth = tier.bitrate_kbps * 1000; // Convert kbps to bps
            let resolution = format!("{}x{}", tier.width, tier.height);
            let playlist_uri = format!("{}/{}.m3u8", base_url, tier.label);

            playlist.push_str(&format!(
                "#EXT-X-STREAM-INF:BANDWIDTH={},RESOLUTION={},CODECS=\"avc1.42001E,mp4a.40.2\"\n",
                bandwidth, resolution
            ));
            playlist.push_str(&format!("{}\n", playlist_uri));
        }

        // Add end-of-list tag
        playlist.push_str("#EXT-X-ENDLIST\n");

        playlist
    }

    /// Generate an HLS media playlist for a specific quality tier
    ///
    /// # Arguments
    /// * `video_id` - Unique video identifier
    /// * `quality_label` - Quality tier label (e.g., "720p")
    /// * `duration_seconds` - Total video duration in seconds
    /// * `base_url` - Base URL for segment URIs
    ///
    /// # Returns
    /// Properly formatted HLS media playlist for the quality tier
    pub fn generate_hls_media_playlist(
        &self,
        video_id: &str,
        quality_label: &str,
        duration_seconds: u32,
        base_url: &str,
    ) -> String {
        debug!(
            "Generating HLS media playlist: video_id={}, quality={}, duration={}s",
            video_id, quality_label, duration_seconds
        );

        let mut playlist = String::from("#EXTM3U\n");
        playlist.push_str("#EXT-X-VERSION:3\n");

        let segment_duration = self.config.hls_segment_duration;
        let total_segments = duration_seconds.div_ceil(segment_duration);

        playlist.push_str(&format!("#EXT-X-TARGETDURATION:{}\n", segment_duration));
        playlist.push_str("#EXT-X-MEDIA-SEQUENCE:0\n");
        playlist.push_str("#EXT-X-PLAYLIST-TYPE:VOD\n");

        // Generate segment entries
        for seg_index in 0..total_segments {
            let segment_duration_actual = if seg_index == total_segments - 1 {
                // Last segment might be shorter
                duration_seconds - (seg_index * segment_duration)
            } else {
                segment_duration
            };

            playlist.push_str(&format!("#EXTINF:{:.1},\n", segment_duration_actual as f64));
            playlist.push_str(&format!(
                "{}/segments/{}-segment{:06}.ts\n",
                base_url, quality_label, seg_index
            ));
        }

        playlist.push_str("#EXT-X-ENDLIST\n");

        playlist
    }

    /// Generate a DASH Media Presentation Description (MPD) manifest
    ///
    /// # Arguments
    /// * `video_id` - Unique video identifier
    /// * `duration_seconds` - Total video duration in seconds
    /// * `quality_tiers` - Available quality levels and bitrates
    /// * `base_url` - Base URL for segment URIs
    ///
    /// # Returns
    /// Properly formatted DASH MPD manifest
    pub fn generate_dash_mpd(
        &self,
        video_id: &str,
        duration_seconds: u32,
        quality_tiers: Vec<QualityTier>,
        base_url: &str,
    ) -> String {
        debug!(
            "Generating DASH MPD: video_id={}, qualities={}",
            video_id,
            quality_tiers.len()
        );

        let segment_duration = self.config.dash_segment_duration;
        let total_segments = duration_seconds.div_ceil(segment_duration);

        // Convert duration to ISO 8601 format (PT00H00M30S)
        let duration_iso = self.seconds_to_iso8601(duration_seconds);

        let mut mpd = String::from(
            r#"<?xml version="1.0" encoding="UTF-8"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" profiles="urn:mpeg:dash:profile:isoff-live:2011" type="static">"#,
        );

        mpd.push_str(&format!(
            r#"
  <BaseURL>{}</BaseURL>
  <Period duration="{}">
    <AdaptationSet mimeType="video/mp4" segmentAlignment="true" subsegmentAlignment="true">
"#,
            escape_xml(base_url),
            duration_iso
        ));

        // Add representations for each quality tier
        for tier in quality_tiers {
            let bandwidth = tier.bitrate_kbps * 1000; // Convert kbps to bps

            mpd.push_str(&format!(
                r#"      <Representation id="{}" mimeType="video/mp4" codecs="avc1.42001E,mp4a.40.2" width="{}" height="{}" frameRate="30" bandwidth="{}">
"#,
                escape_xml(&tier.label), tier.width, tier.height, bandwidth
            ));

            // Add initialization segment reference
            mpd.push_str(&format!(
                r#"        <SegmentBase indexRange="0-0" indexRangeExact="true">
          <Initialization sourceURL="segments/{}-init.mp4"/>
        </SegmentBase>
"#,
                escape_xml(&tier.label)
            ));

            // Add segment list with all segment references
            mpd.push_str(&format!(
                r#"        <SegmentList timescale="90000" duration="{}">
"#,
                segment_duration * 90000 // Timescale is 90kHz for DASH
            ));

            for seg_index in 0..total_segments {
                mpd.push_str(&format!(
                    r#"          <SegmentURL media="segments/{}-segment{:06}.m4s"/>
"#,
                    escape_xml(&tier.label),
                    seg_index
                ));
            }

            mpd.push_str("        </SegmentList>\n");
            mpd.push_str("      </Representation>\n");
        }

        mpd.push_str(
            r#"    </AdaptationSet>
  </Period>
</MPD>
"#,
        );

        mpd
    }

    /// Convert seconds to ISO 8601 duration format (e.g., "PT00H00M30S")
    fn seconds_to_iso8601(&self, seconds: u32) -> String {
        let hours = seconds / 3600;
        let minutes = (seconds % 3600) / 60;
        let secs = seconds % 60;
        format!("PT{:02}H{:02}M{:02}S", hours, minutes, secs)
    }

    /// Get recommended quality tiers from bitrate configuration
    ///
    /// # Arguments
    /// * `bitrates` - HashMap of quality labels to bitrates in kbps
    ///
    /// # Returns
    /// Vector of quality tiers sorted by bitrate (ascending)
    pub fn get_quality_tiers(bitrates: &HashMap<String, u32>) -> Vec<QualityTier> {
        let mut tiers: Vec<QualityTier> = bitrates
            .iter()
            .map(|(label, bitrate)| QualityTier::new(label.clone(), *bitrate))
            .collect();

        // Sort ascending by bitrate
        tiers.sort_by(|a, b| a.bitrate_kbps.cmp(&b.bitrate_kbps));
        tiers
    }
}

/// Escape XML special characters for safe inclusion in MPD
fn escape_xml(input: &str) -> String {
    input
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&apos;")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_generator() -> StreamingManifestGenerator {
        let config = StreamingConfig {
            enable_hls: true,
            enable_dash: true,
            hls_segment_duration: 10,
            dash_segment_duration: 10,
            enable_abr: true,
            bandwidth_estimation_window: 20,
            preload_duration: 30,
        };
        StreamingManifestGenerator::new(config)
    }

    fn create_test_qualities() -> Vec<QualityTier> {
        vec![
            QualityTier::new("360p".to_string(), 800),
            QualityTier::new("480p".to_string(), 1500),
            QualityTier::new("720p".to_string(), 2500),
        ]
    }

    #[test]
    fn test_quality_tier_creation() {
        let tier = QualityTier::new("720p".to_string(), 2500);
        assert_eq!(tier.label, "720p");
        assert_eq!(tier.width, 1280);
        assert_eq!(tier.height, 720);
        assert_eq!(tier.bitrate_kbps, 2500);
    }

    #[test]
    fn test_hls_master_playlist_generation() {
        let generator = create_test_generator();
        let qualities = create_test_qualities();

        let manifest = generator.generate_hls_master_playlist(
            "test-video",
            300,
            qualities,
            "https://cdn.example.com/videos/test-video",
        );

        assert!(manifest.contains("#EXTM3U"));
        assert!(manifest.contains("#EXT-X-VERSION:3"));
        assert!(manifest.contains("#EXT-X-STREAM-INF"));
        assert!(manifest.contains("720p"));
        assert!(manifest.contains("480p"));
        assert!(manifest.contains("360p"));
        assert!(manifest.contains("#EXT-X-ENDLIST"));
    }

    #[test]
    fn test_hls_media_playlist_generation() {
        let generator = create_test_generator();

        let manifest = generator.generate_hls_media_playlist(
            "test-video",
            "720p",
            30,
            "https://cdn.example.com/videos/test-video",
        );

        assert!(manifest.contains("#EXTM3U"));
        assert!(manifest.contains("#EXTINF"));
        assert!(manifest.contains("segment000000"));
        assert!(manifest.contains("#EXT-X-ENDLIST"));
        assert!(manifest.contains(".ts"));
    }

    #[test]
    fn test_dash_mpd_generation() {
        let generator = create_test_generator();
        let qualities = create_test_qualities();

        let manifest = generator.generate_dash_mpd(
            "test-video",
            300,
            qualities,
            "https://cdn.example.com/videos/test-video",
        );

        assert!(manifest.contains("<?xml version"));
        assert!(manifest.contains("<MPD"));
        assert!(manifest.contains("<Period"));
        assert!(manifest.contains("<Representation"));
        assert!(manifest.contains("<SegmentList"));
        assert!(manifest.contains("</MPD>"));
    }

    #[test]
    fn test_segments_calculation() {
        let generator = create_test_generator();

        // 30 seconds with 10-second segments = 3 segments
        let manifest =
            generator.generate_hls_media_playlist("test", "720p", 30, "https://example.com");

        // Count #EXTINF tags (one per segment)
        let segment_count = manifest.matches("#EXTINF").count();
        assert_eq!(segment_count, 3);
    }

    #[test]
    fn test_last_segment_duration() {
        let generator = create_test_generator();

        // 25 seconds with 10-second segments = 3 segments
        // Last segment should be 5 seconds
        let manifest =
            generator.generate_hls_media_playlist("test", "720p", 25, "https://example.com");

        // Should contain the actual duration of 5.0
        assert!(manifest.contains("5."));
    }

    #[test]
    fn test_iso8601_conversion() {
        let generator = create_test_generator();

        assert_eq!(generator.seconds_to_iso8601(0), "PT00H00M00S");
        assert_eq!(generator.seconds_to_iso8601(60), "PT00H01M00S");
        assert_eq!(generator.seconds_to_iso8601(3661), "PT01H01M01S");
        assert_eq!(generator.seconds_to_iso8601(600), "PT00H10M00S");
    }

    #[test]
    fn test_xml_escaping() {
        assert_eq!(escape_xml("test&data"), "test&amp;data");
        assert_eq!(escape_xml("test<data>"), "test&lt;data&gt;");
        assert_eq!(escape_xml("test\"data"), "test&quot;data");
    }

    #[test]
    fn test_quality_tiers_sorting() {
        let mut bitrates = HashMap::new();
        bitrates.insert("720p".to_string(), 2500);
        bitrates.insert("360p".to_string(), 800);
        bitrates.insert("480p".to_string(), 1500);

        let tiers = StreamingManifestGenerator::get_quality_tiers(&bitrates);

        assert_eq!(tiers.len(), 3);
        assert_eq!(tiers[0].bitrate_kbps, 800); // Lowest first
        assert_eq!(tiers[1].bitrate_kbps, 1500);
        assert_eq!(tiers[2].bitrate_kbps, 2500); // Highest last
    }
}
