#!/usr/bin/env python3
"""
Nova Streaming Broadcaster Client - Python Example

This example demonstrates how to build an RTMP broadcaster client
that sends live video to the Nova Streaming platform.

Requirements:
    pip install requests pycryptodome av

Usage:
    python python-broadcaster-client.py \
        --token <jwt_token> \
        --video <input_video.mp4|/dev/video0> \
        --fps 30 \
        --bitrate 5000

Environment Variables:
    NOVA_API_URL: API endpoint (default: https://api.nova-social.io/api/v1)
    NOVA_RTMP_URL: RTMP endpoint (default: rtmp://ingest.nova-social.io/live)
"""

import argparse
import asyncio
import json
import logging
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger(__name__)


@dataclass
class StreamConfig:
    """Stream configuration"""
    title: str
    description: str
    region: str = "us-west-2"
    tags: list = None

    def __post_init__(self):
        if self.tags is None:
            self.tags = []


@dataclass
class BroadcasterConfig:
    """Broadcaster configuration"""
    token: str
    video_input: str
    fps: int = 30
    bitrate_kbps: int = 5000
    quality: str = "1080p"
    api_url: str = os.getenv(
        "NOVA_API_URL",
        "https://api.nova-social.io/api/v1"
    )
    rtmp_url: str = os.getenv(
        "NOVA_RTMP_URL",
        "rtmp://ingest.nova-social.io/live"
    )


class NovaStreamBroadcaster:
    """RTMP Broadcaster client for Nova Streaming"""

    def __init__(self, config: BroadcasterConfig):
        self.config = config
        self.stream_id = None
        self.stream_key = None
        self.rtmp_full_url = None
        self.process = None
        self.start_time = None
        self.frame_count = 0
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {config.token}",
            "Content-Type": "application/json",
        })

    def create_stream(self, stream_config: StreamConfig) -> bool:
        """Create a new stream on the Nova platform"""
        logger.info("Creating stream...")

        payload = {
            "title": stream_config.title,
            "description": stream_config.description,
            "region": stream_config.region,
            "tags": stream_config.tags,
        }

        try:
            response = self.session.post(
                f"{self.config.api_url}/streams",
                json=payload,
            )
            response.raise_for_status()

            data = response.json()
            self.stream_id = data["id"]
            self.stream_key = data["rtmp_key"]
            self.rtmp_full_url = f"{self.config.rtmp_url}/{self.stream_key}"

            logger.info(f"✓ Stream created: {self.stream_id}")
            logger.info(f"✓ RTMP URL: {self.rtmp_full_url}")
            return True

        except requests.RequestException as e:
            logger.error(f"✗ Failed to create stream: {e}")
            return False

    def get_stream_info(self) -> Optional[dict]:
        """Get current stream information"""
        try:
            response = self.session.get(
                f"{self.config.api_url}/streams/{self.stream_id}",
            )
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            logger.error(f"✗ Failed to get stream info: {e}")
            return None

    def start_broadcasting(self) -> bool:
        """Start RTMP broadcast using FFmpeg"""
        if not self.stream_id or not self.rtmp_full_url:
            logger.error("Stream not created yet")
            return False

        logger.info("Starting RTMP broadcast...")
        logger.info(f"Input: {self.config.video_input}")
        logger.info(f"FPS: {self.config.fps}")
        logger.info(f"Bitrate: {self.config.bitrate_kbps} kbps")

        # FFmpeg command for RTMP broadcast
        # Supports both video files and live capture devices
        ffmpeg_cmd = [
            "ffmpeg",
            "-i", self.config.video_input,
            "-c:v", "libx264",
            "-preset", "fast",  # fast, medium, slow
            "-b:v", f"{self.config.bitrate_kbps}k",
            "-maxrate", f"{self.config.bitrate_kbps * 1.2}k",
            "-bufsize", f"{self.config.bitrate_kbps * 2}k",
            "-r", str(self.config.fps),
            "-c:a", "aac",
            "-b:a", "128k",
            "-ar", "44100",
            "-f", "flv",
            self.rtmp_full_url,
        ]

        try:
            self.process = subprocess.Popen(
                ffmpeg_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.start_time = time.time()
            logger.info("✓ RTMP broadcast started")
            return True

        except FileNotFoundError:
            logger.error("✗ FFmpeg not found. Install it with: brew install ffmpeg")
            return False
        except Exception as e:
            logger.error(f"✗ Failed to start broadcast: {e}")
            return False

    def monitor_broadcast(self) -> None:
        """Monitor broadcast in real-time"""
        logger.info("Monitoring broadcast (press Ctrl+C to stop)...")

        try:
            while self.process and self.process.poll() is None:
                time.sleep(5)

                # Get stream info
                info = self.get_stream_info()
                if info:
                    elapsed = int(time.time() - self.start_time)
                    logger.info(f"Status: {info['status']} | "
                              f"Duration: {elapsed}s | "
                              f"Viewers: {info['viewer_count']} | "
                              f"Peak: {info['peak_viewers']}")

                # Check for FFmpeg errors
                if self.process.poll() is not None:
                    logger.warning("✗ FFmpeg process exited")
                    _, stderr = self.process.communicate()
                    if stderr:
                        logger.error(f"FFmpeg error: {stderr}")
                    break

        except KeyboardInterrupt:
            logger.info("Stopping broadcast...")
            self.stop_broadcasting()

    def stop_broadcasting(self) -> None:
        """Stop RTMP broadcast"""
        if self.process:
            logger.info("Terminating FFmpeg process...")
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                logger.warning("Force killing FFmpeg")
                self.process.kill()
            logger.info("✓ Broadcast stopped")

    def end_stream(self) -> bool:
        """End the stream on Nova platform"""
        if not self.stream_id:
            return False

        logger.info("Ending stream...")
        try:
            response = self.session.delete(
                f"{self.config.api_url}/streams/{self.stream_id}",
            )
            response.raise_for_status()
            logger.info("✓ Stream ended")
            return True

        except requests.RequestException as e:
            logger.error(f"✗ Failed to end stream: {e}")
            return False

    def run(self, stream_config: StreamConfig) -> int:
        """Run the complete broadcast workflow"""
        try:
            # Step 1: Create stream
            if not self.create_stream(stream_config):
                return 1

            # Step 2: Start broadcasting
            if not self.start_broadcasting():
                return 1

            # Step 3: Monitor broadcast
            self.monitor_broadcast()

            # Step 4: End stream
            self.end_stream()

            return 0

        except Exception as e:
            logger.error(f"✗ Broadcast error: {e}")
            self.stop_broadcasting()
            return 1

        finally:
            # Cleanup
            if self.process:
                self.stop_broadcasting()


class MockVideoGenerator:
    """Generate a mock video file for testing"""

    @staticmethod
    def create_test_video(filename: str, duration_seconds: int = 10, fps: int = 30) -> bool:
        """Create a test video file using FFmpeg"""
        logger.info(f"Generating test video: {filename}")

        cmd = [
            "ffmpeg",
            "-f", "lavfi",
            "-i", f"color=c=blue:s=1280x720:d={duration_seconds}",
            "-f", "lavfi",
            "-i", f"sine=frequency=1000:duration={duration_seconds}",
            "-r", str(fps),
            "-c:v", "libx264",
            "-c:a", "aac",
            "-y",  # Overwrite
            filename,
        ]

        try:
            subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            logger.info(f"✓ Test video created: {filename}")
            return True
        except Exception as e:
            logger.error(f"✗ Failed to create test video: {e}")
            return False


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="Nova Streaming Broadcaster Client",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Broadcast a video file
  python broadcaster.py --token <jwt> --video stream.mp4 \\
    --title "My Stream" --description "Test broadcast"

  # Generate and broadcast a test video
  python broadcaster.py --token <jwt> --generate-test-video \\
    --title "Test Stream"

  # Broadcast from webcam (macOS)
  python broadcaster.py --token <jwt> --video "0:0" \\
    --title "Webcam Stream"
        """
    )

    parser.add_argument("--token", required=True, help="JWT authentication token")
    parser.add_argument("--video", help="Video input (file or device)")
    parser.add_argument("--title", default="Nova Stream", help="Stream title")
    parser.add_argument("--description", default="", help="Stream description")
    parser.add_argument("--region", default="us-west-2", help="Stream region")
    parser.add_argument("--tags", nargs="+", default=[], help="Stream tags")
    parser.add_argument("--fps", type=int, default=30, help="Frames per second")
    parser.add_argument("--bitrate", type=int, default=5000, help="Bitrate (kbps)")
    parser.add_argument("--generate-test-video", action="store_true",
                       help="Generate test video before broadcasting")
    parser.add_argument("--verbose", action="store_true", help="Verbose logging")

    args = parser.parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Handle test video generation
    if args.generate_test_video:
        test_video = "/tmp/nova_test_video.mp4"
        if not MockVideoGenerator.create_test_video(test_video):
            return 1
        args.video = test_video

    if not args.video:
        parser.error("--video or --generate-test-video required")

    # Create configurations
    broadcaster_config = BroadcasterConfig(
        token=args.token,
        video_input=args.video,
        fps=args.fps,
        bitrate_kbps=args.bitrate,
    )

    stream_config = StreamConfig(
        title=args.title,
        description=args.description,
        region=args.region,
        tags=args.tags,
    )

    # Create and run broadcaster
    broadcaster = NovaStreamBroadcaster(broadcaster_config)
    return broadcaster.run(stream_config)


if __name__ == "__main__":
    sys.exit(main())
