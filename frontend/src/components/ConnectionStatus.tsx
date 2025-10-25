/**
 * Connection Status UI Component
 * Displays real-time WebSocket connection status
 */

import React, { useEffect } from 'react';
import { useConnection, getConnectionStateColor, getConnectionStateEmoji, ConnectionState } from '../stores/connectionStore';

export interface ConnectionStatusProps {
  /** Show/hide component */
  visible?: boolean;
  /** Position: top-left, top-right, bottom-left, bottom-right */
  position?: 'top-left' | 'top-right' | 'bottom-left' | 'bottom-right';
  /** Show detailed metrics (reconnects, queued messages, duration) */
  showMetrics?: boolean;
  /** Custom className */
  className?: string;
  /** Compact mode (icon only, shows tooltip) */
  compact?: boolean;
}

/**
 * Connection Status Component
 */
export function ConnectionStatus({
  visible = true,
  position = 'top-right',
  showMetrics = false,
  className = '',
  compact = false,
}: ConnectionStatusProps) {
  const { state, isConnected, status, metrics, hasQueuedMessages, isReconnecting } = useConnection();
  const color = getConnectionStateColor(state);
  const emoji = getConnectionStateEmoji(state);

  if (!visible) {
    return null;
  }

  const positionClasses: Record<string, string> = {
    'top-left': 'top-5 left-5',
    'top-right': 'top-5 right-5',
    'bottom-left': 'bottom-5 left-5',
    'bottom-right': 'bottom-5 right-5',
  };

  if (compact) {
    return (
      <div
        className={`nova-connection-status-compact ${positionClasses[position]} ${className}`}
        title={status}
        style={{ borderColor: color }}
      >
        <span className="nova-connection-emoji">{emoji}</span>
      </div>
    );
  }

  return (
    <div
      className={`nova-connection-status ${positionClasses[position]} ${className}`}
      style={{ borderLeftColor: color }}
    >
      <div className="nova-connection-header">
        <span className="nova-connection-emoji">{emoji}</span>
        <span className="nova-connection-status-text">{status}</span>
        {hasQueuedMessages && (
          <span className="nova-connection-badge">{metrics?.queuedMessages || 0}</span>
        )}
      </div>

      {showMetrics && metrics && (
        <div className="nova-connection-metrics">
          <div className="nova-metric">
            <span className="nova-metric-label">Reconnects:</span>
            <span className="nova-metric-value">{metrics.reconnects}</span>
          </div>
          {metrics.queuedMessages > 0 && (
            <div className="nova-metric">
              <span className="nova-metric-label">Queued:</span>
              <span className="nova-metric-value">{metrics.queuedMessages}</span>
            </div>
          )}
          {isConnected && (
            <div className="nova-metric">
              <span className="nova-metric-label">Connected:</span>
              <span className="nova-metric-value">
                {Math.round(metrics.connectionDurationMs / 1000)}s
              </span>
            </div>
          )}
        </div>
      )}

      {isReconnecting && (
        <div className="nova-connection-reconnecting">
          <span>Reconnecting</span>
          <span className="nova-reconnecting-dot">.</span>
          <span className="nova-reconnecting-dot">.</span>
          <span className="nova-reconnecting-dot">.</span>
        </div>
      )}
    </div>
  );
}

/**
 * Connection Status Indicator (minimal icon only)
 */
export function ConnectionIndicator({
  className = '',
}: {
  className?: string;
}) {
  const { state } = useConnection();
  const color = getConnectionStateColor(state);
  const emoji = getConnectionStateEmoji(state);

  return (
    <div
      className={`nova-connection-indicator ${className}`}
      style={{ color }}
      title={`Connection: ${state}`}
    >
      {emoji}
    </div>
  );
}

/**
 * Connection Banner - shows when disconnected
 */
export function ConnectionBanner() {
  const { isConnected, state, hasQueuedMessages } = useConnection();

  if (isConnected) {
    return null;
  }

  return (
    <div className="nova-connection-banner">
      <div className="nova-banner-content">
        <span className="nova-banner-icon">⚠️</span>
        <div className="nova-banner-text">
          {state === ConnectionState.RECONNECTING ? (
            <>
              <p className="nova-banner-title">Reconnecting to server...</p>
              <p className="nova-banner-description">Your messages will sync automatically when connection is restored.</p>
            </>
          ) : (
            <>
              <p className="nova-banner-title">Connection lost</p>
              <p className="nova-banner-description">
                {hasQueuedMessages
                  ? 'Your messages are saved locally and will be sent when you reconnect.'
                  : 'Attempting to reconnect...'}
              </p>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

/**
 * CSS Styles for connection status components
 */
export const connectionStatusStyles = `
/* Connection Status Container */
.nova-connection-status {
  position: fixed;
  background: white;
  border: 1px solid #e5e7eb;
  border-left: 4px solid #10b981;
  border-radius: 8px;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  padding: 12px 16px;
  font-size: 13px;
  z-index: 9998;
  transition: all 300ms ease;
}

.nova-connection-status:hover {
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
}

/* Header */
.nova-connection-header {
  display: flex;
  align-items: center;
  gap: 8px;
}

.nova-connection-emoji {
  font-size: 16px;
  display: inline-block;
}

.nova-connection-status-text {
  font-weight: 500;
  color: #374151;
}

.nova-connection-badge {
  background: #ef4444;
  color: white;
  border-radius: 12px;
  padding: 2px 6px;
  font-size: 11px;
  font-weight: 600;
  margin-left: 4px;
}

/* Metrics */
.nova-connection-metrics {
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px solid #f3f4f6;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.nova-metric {
  display: flex;
  justify-content: space-between;
  color: #6b7280;
  font-size: 12px;
}

.nova-metric-label {
  font-weight: 500;
}

.nova-metric-value {
  color: #1f2937;
  font-weight: 600;
}

/* Reconnecting indicator */
.nova-connection-reconnecting {
  margin-top: 8px;
  color: #f59e0b;
  font-size: 12px;
  display: flex;
  align-items: center;
  gap: 2px;
}

.nova-reconnecting-dot {
  animation: blink 1.4s infinite;
}

.nova-reconnecting-dot:nth-child(2) {
  animation-delay: 0.2s;
}

.nova-reconnecting-dot:nth-child(3) {
  animation-delay: 0.4s;
}

@keyframes blink {
  0%, 20%, 100% { opacity: 0.3; }
  50% { opacity: 1; }
}

/* Compact mode */
.nova-connection-status-compact {
  position: fixed;
  width: 32px;
  height: 32px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: white;
  border: 2px solid #e5e7eb;
  border-left: 3px solid;
  border-radius: 8px;
  font-size: 16px;
  z-index: 9998;
  cursor: pointer;
  transition: all 200ms ease;
}

.nova-connection-status-compact:hover {
  transform: scale(1.1);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
}

/* Connection Indicator */
.nova-connection-indicator {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  transition: color 300ms ease;
}

/* Connection Banner */
.nova-connection-banner {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  background: linear-gradient(to right, #fef3c7, #fef9e7);
  border-bottom: 2px solid #f59e0b;
  padding: 12px 20px;
  z-index: 9997;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}

.nova-banner-content {
  max-width: 1200px;
  margin: 0 auto;
  display: flex;
  align-items: center;
  gap: 12px;
}

.nova-banner-icon {
  font-size: 20px;
  flex-shrink: 0;
}

.nova-banner-text {
  flex: 1;
}

.nova-banner-title {
  margin: 0;
  font-weight: 600;
  color: #92400e;
  font-size: 14px;
}

.nova-banner-description {
  margin: 4px 0 0 0;
  font-size: 13px;
  color: #b45309;
}

/* Responsive */
@media (max-width: 640px) {
  .nova-connection-status {
    max-width: calc(100vw - 40px);
    font-size: 12px;
    padding: 10px 12px;
  }

  .nova-connection-header {
    gap: 6px;
  }

  .nova-connection-emoji {
    font-size: 14px;
  }

  .nova-connection-metrics {
    font-size: 11px;
  }

  .nova-banner-content {
    flex-direction: column;
    align-items: flex-start;
  }

  .nova-banner-title {
    font-size: 13px;
  }

  .nova-banner-description {
    font-size: 12px;
  }
}
`;
