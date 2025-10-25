import React, { useRef, useState } from 'react';

interface VideoPlayerProps {
  cdnUrl?: string;
  thumbnailUrl?: string;
  durationSeconds?: number;
  position?: number;
}

/**
 * VideoPlayer Component
 * Renders an HLS video player with controls
 * Supports:
 * - Play/Pause controls
 * - Fullscreen mode
 * - Progress bar with seeking
 * - Volume control
 * - Duration display
 */
const VideoPlayer: React.FC<VideoPlayerProps> = ({
  cdnUrl,
  thumbnailUrl,
  durationSeconds,
  position = 0,
}) => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [volume, setVolume] = useState(1);
  const [isFullscreen, setIsFullscreen] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  const handlePlayPause = () => {
    if (videoRef.current) {
      if (isPlaying) {
        videoRef.current.pause();
      } else {
        videoRef.current.play();
      }
      setIsPlaying(!isPlaying);
    }
  };

  const handleTimeUpdate = () => {
    if (videoRef.current) {
      setCurrentTime(videoRef.current.currentTime);
    }
  };

  const handleProgressChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newTime = parseFloat(e.target.value);
    if (videoRef.current) {
      videoRef.current.currentTime = newTime;
      setCurrentTime(newTime);
    }
  };

  const handleVolumeChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const newVolume = parseFloat(e.target.value);
    setVolume(newVolume);
    if (videoRef.current) {
      videoRef.current.volume = newVolume;
    }
  };

  const handleFullscreen = () => {
    if (containerRef.current) {
      if (!isFullscreen) {
        containerRef.current
          .requestFullscreen()
          .catch((err) => console.error('Fullscreen error:', err));
        setIsFullscreen(true);
      } else {
        document.exitFullscreen();
        setIsFullscreen(false);
      }
    }
  };

  const formatTime = (seconds: number) => {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  };

  if (!cdnUrl) {
    return (
      <div
        style={{
          padding: '16px',
          textAlign: 'center',
          background: '#f5f5f5',
          borderRadius: '8px',
        }}
      >
        No video available
      </div>
    );
  }

  return (
    <div
      ref={containerRef}
      style={{
        background: '#000',
        borderRadius: '8px',
        overflow: 'hidden',
        position: 'relative',
      }}
    >
      <video
        ref={videoRef}
        src={cdnUrl}
        poster={thumbnailUrl}
        style={{
          width: '100%',
          height: 'auto',
          display: 'block',
        }}
        onPlay={() => setIsPlaying(true)}
        onPause={() => setIsPlaying(false)}
        onTimeUpdate={handleTimeUpdate}
        onLoadStart={() => setIsLoading(true)}
        onLoadedData={() => setIsLoading(false)}
      />

      {/* Loading Indicator */}
      {isLoading && (
        <div
          style={{
            position: 'absolute',
            top: '50%',
            left: '50%',
            transform: 'translate(-50%, -50%)',
            color: 'white',
            fontSize: '14px',
          }}
        >
          Loading...
        </div>
      )}

      {/* Player Controls */}
      <div
        style={{
          background: 'linear-gradient(to top, rgba(0,0,0,0.8), rgba(0,0,0,0))',
          padding: '16px',
          position: 'absolute',
          bottom: 0,
          left: 0,
          right: 0,
          color: 'white',
        }}
      >
        {/* Progress Bar */}
        <input
          type="range"
          min="0"
          max={durationSeconds || 100}
          value={currentTime}
          onChange={handleProgressChange}
          style={{
            width: '100%',
            marginBottom: '8px',
            cursor: 'pointer',
          }}
        />

        {/* Controls Row */}
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: '12px',
            justifyContent: 'space-between',
          }}
        >
          {/* Play/Pause and Time */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <button
              onClick={handlePlayPause}
              style={{
                background: 'rgba(255,255,255,0.3)',
                border: 'none',
                color: 'white',
                padding: '8px 12px',
                borderRadius: '4px',
                cursor: 'pointer',
                fontSize: '14px',
                fontWeight: 600,
              }}
              title={isPlaying ? 'Pause' : 'Play'}
            >
              {isPlaying ? '⏸' : '▶'}
            </button>

            <span style={{ fontSize: '12px', minWidth: '100px' }}>
              {formatTime(currentTime)} / {durationSeconds ? formatTime(durationSeconds) : '--:--'}
            </span>
          </div>

          {/* Volume and Fullscreen */}
          <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
              <span style={{ fontSize: '14px' }}>🔊</span>
              <input
                type="range"
                min="0"
                max="1"
                step="0.1"
                value={volume}
                onChange={handleVolumeChange}
                style={{
                  width: '80px',
                  cursor: 'pointer',
                }}
              />
            </div>

            <button
              onClick={handleFullscreen}
              style={{
                background: 'rgba(255,255,255,0.3)',
                border: 'none',
                color: 'white',
                padding: '8px 12px',
                borderRadius: '4px',
                cursor: 'pointer',
                fontSize: '14px',
              }}
              title={isFullscreen ? 'Exit Fullscreen' : 'Fullscreen'}
            >
              {isFullscreen ? '⛶' : '⛶'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};

export default VideoPlayer;
