//! RTMP Client for Integration Testing
//!
//! Simple RTMP protocol client that connects to Nginx-RTMP server.
//! Implements RTMP handshake and frame streaming for test scenarios.
//!
//! This is NOT a full RTMP server - it's a minimal TCP client that:
//! 1. Connects to real Nginx-RTMP on port 1935
//! 2. Performs RTMP handshake (C0, C1, C2)
//! 3. Sends synthetic H.264 frames
//! 4. Verifies server responses

use anyhow::{anyhow, Result};
use bytes::{BytesMut, BufMut};
use std::io::{Read, Write};
use std::net::TcpStream;
use std::time::Duration;
use tokio::time::sleep;

/// RTMP Protocol Constants
const RTMP_SIGNATURE: u8 = 0x03; // RTMP version 3
const RTMP_HANDSHAKE_SIZE: usize = 1536;
const RTMP_CHUNK_SIZE: usize = 128;

/// RTMP Client for connecting to Nginx-RTMP server
pub struct RtmpClient {
    stream: TcpStream,
    chunk_size: usize,
}

impl RtmpClient {
    /// Create new RTMP client and connect to server
    pub async fn connect(addr: &str) -> Result<Self> {
        // Parse address
        let addr = addr.parse().map_err(|e| {
            anyhow!("Invalid RTMP address: {}", e)
        })?;

        // Connect with timeout
        let stream = TcpStream::connect_timeout(
            &addr,
            Duration::from_secs(5)
        ).map_err(|e| {
            anyhow!("Failed to connect to RTMP server: {}", e)
        })?;

        // Set non-blocking for async operations
        stream.set_nonblocking(true).map_err(|e| {
            anyhow!("Failed to set non-blocking mode: {}", e)
        })?;

        Ok(Self {
            stream,
            chunk_size: RTMP_CHUNK_SIZE,
        })
    }

    /// Perform RTMP handshake (C0 + C1 → S0 + S1 + S2 ← C2)
    pub fn handshake(&mut self) -> Result<()> {
        // C0: Send RTMP signature (1 byte)
        self.stream.write_all(&[RTMP_SIGNATURE]).map_err(|e| {
            anyhow!("Failed to send C0: {}", e)
        })?;

        // C1: Send client random data (1536 bytes)
        let mut c1 = vec![0u8; RTMP_HANDSHAKE_SIZE];
        c1[0..4].copy_from_slice(&[0u8; 4]); // timestamp
        c1[4..8].copy_from_slice(&[0u8; 4]); // version
        // Rest is random (zeros for testing)
        self.stream.write_all(&c1).map_err(|e| {
            anyhow!("Failed to send C1: {}", e)
        })?;

        // S0: Read server signature
        let mut s0 = [0u8; 1];
        self.stream.read_exact(&mut s0).map_err(|e| {
            anyhow!("Failed to read S0: {}", e)
        })?;

        if s0[0] != RTMP_SIGNATURE {
            return Err(anyhow!("Invalid RTMP server signature: {}", s0[0]));
        }

        // S1: Read server random data
        let mut s1 = vec![0u8; RTMP_HANDSHAKE_SIZE];
        self.stream.read_exact(&mut s1).map_err(|e| {
            anyhow!("Failed to read S1: {}", e)
        })?;

        // S2: Read server echo of C1
        let mut s2 = vec![0u8; RTMP_HANDSHAKE_SIZE];
        self.stream.read_exact(&mut s2).map_err(|e| {
            anyhow!("Failed to read S2: {}", e)
        })?;

        // C2: Send echo of S1
        self.stream.write_all(&s1).map_err(|e| {
            anyhow!("Failed to send C2: {}", e)
        })?;

        Ok(())
    }

    /// Send RTMP connect command
    pub fn connect_command(&mut self, app: &str) -> Result<()> {
        // Build AMF0 encoded connect command
        let mut payload = BytesMut::new();

        // Command: "connect" (string)
        payload.put_u8(0x02); // String type
        payload.put_u16(7); // Length
        payload.put_slice(b"connect");

        // Transaction ID: 1 (number)
        payload.put_u8(0x00); // Number type
        payload.put_f64(1.0);

        // Object: connection parameters
        payload.put_u8(0x03); // Object type

        // app (string property)
        payload.put_u16(3); // key length
        payload.put_slice(b"app");
        payload.put_u8(0x02); // String type
        payload.put_u16(app.len() as u16);
        payload.put_slice(app.as_bytes());

        // type (string property)
        payload.put_u16(4); // key length
        payload.put_slice(b"type");
        payload.put_u8(0x02); // String type
        payload.put_u16(9); // Length
        payload.put_slice(b"nonprivate");

        // Object end marker
        payload.put_u16(0); // Empty key
        payload.put_u8(0x09); // Object end

        self.send_command(&payload, 3)?; // Command on stream 0, channel 3

        Ok(())
    }

    /// Send RTMP publish command
    pub fn publish_command(&mut self, stream_name: &str) -> Result<()> {
        // Build AMF0 encoded publish command
        let mut payload = BytesMut::new();

        // Command: "publish"
        payload.put_u8(0x02); // String type
        payload.put_u16(7); // Length
        payload.put_slice(b"publish");

        // Transaction ID: 2
        payload.put_u8(0x00); // Number type
        payload.put_f64(2.0);

        // null (reserved)
        payload.put_u8(0x05);

        // Stream name
        payload.put_u8(0x02); // String type
        payload.put_u16(stream_name.len() as u16);
        payload.put_slice(stream_name.as_bytes());

        // Publish type (live/record)
        payload.put_u8(0x02); // String type
        payload.put_u16(4); // Length
        payload.put_slice(b"live");

        self.send_command(&payload, 4)?; // Channel 4 for publish

        Ok(())
    }

    /// Send raw RTMP chunk
    fn send_command(&mut self, payload: &[u8], channel_id: u8) -> Result<()> {
        // RTMP chunk header (basic header + message header)
        let mut header = vec![0u8; 12]; // Max header size

        // Basic header: fmt=0 (full header), channel_id
        header[0] = (0 << 6) | (channel_id & 0x3F);

        // Message header: timestamp (3 bytes) + length (3 bytes) + type (1 byte) + stream_id (4 bytes)
        let timestamp = 0u32;
        header[1..4].copy_from_slice(&timestamp.to_be_bytes()[1..4]);

        let len = payload.len() as u32;
        header[4..7].copy_from_slice(&len.to_be_bytes()[1..4]);

        header[7] = 0x14; // Command type (AMF0)

        let stream_id = 1u32; // Stream ID
        header[8..12].copy_from_slice(&stream_id.to_le_bytes());

        self.stream.write_all(&header).map_err(|e| {
            anyhow!("Failed to send RTMP header: {}", e)
        })?;

        self.stream.write_all(payload).map_err(|e| {
            anyhow!("Failed to send RTMP payload: {}", e)
        })?;

        Ok(())
    }

    /// Send synthetic H.264 frame data
    pub fn send_frame(&mut self, frame_data: &[u8], frame_type: FrameType) -> Result<()> {
        // Build video tag
        let mut tag = BytesMut::new();

        // FLV video tag header
        let codec_id = 0x07; // H.264
        let frame_type_bits = match frame_type {
            FrameType::Keyframe => 1u8,
            FrameType::Interframe => 2u8,
        };

        tag.put_u8((frame_type_bits << 4) | codec_id);

        // AVCPacketType: 0 = AVC sequence header, 1 = AVC NALU
        tag.put_u8(0x01);

        // CompositionTime: 0 for keyframes
        tag.put_u24(0);

        // Frame data
        tag.put_slice(frame_data);

        // Send as media data message type 9 (video)
        self.send_media(&tag, 0x09)?;

        Ok(())
    }

    /// Send media packet (video/audio)
    fn send_media(&mut self, data: &[u8], media_type: u8) -> Result<()> {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_millis() as u32;

        // RTMP chunk header
        let mut header = vec![0u8; 12];
        header[0] = 0x08; // Channel 8 for video

        // Timestamp (3 bytes)
        header[1..4].copy_from_slice(&timestamp.to_be_bytes()[1..4]);

        // Length (3 bytes)
        let len = data.len() as u32;
        header[4..7].copy_from_slice(&len.to_be_bytes()[1..4]);

        // Type
        header[7] = media_type;

        // Stream ID
        header[8..12].copy_from_slice(&1u32.to_le_bytes());

        self.stream.write_all(&header).map_err(|e| {
            anyhow!("Failed to send media header: {}", e)
        })?;

        self.stream.write_all(data).map_err(|e| {
            anyhow!("Failed to send media data: {}", e)
        })?;

        Ok(())
    }

    /// Gracefully close connection
    pub fn disconnect(&mut self) -> Result<()> {
        self.stream.shutdown(std::net::Shutdown::Both).map_err(|e| {
            anyhow!("Failed to disconnect: {}", e)
        })
    }
}

/// Frame type enumeration
#[derive(Debug, Clone, Copy)]
pub enum FrameType {
    Keyframe,
    Interframe,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rtmp_client_creation() {
        // This test verifies the module compiles
        // Actual connection tests require running docker-compose.test.yml
        assert_eq!(RTMP_HANDSHAKE_SIZE, 1536);
        assert_eq!(RTMP_CHUNK_SIZE, 128);
    }

    #[test]
    fn test_frame_type_enum() {
        let keyframe = FrameType::Keyframe;
        let interframe = FrameType::Interframe;

        // Verify enum works
        assert_eq!(std::mem::discriminant(&keyframe), std::mem::discriminant(&FrameType::Keyframe));
        assert_eq!(std::mem::discriminant(&interframe), std::mem::discriminant(&FrameType::Interframe));
    }
}
