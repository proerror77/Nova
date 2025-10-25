/**
 * WebSocket Connection State Store
 * Tracks connection status and metrics for UI components
 */

import { create } from 'zustand';
import { ConnectionState } from '../websocket/EnhancedWebSocketClient';

export interface ConnectionMetrics {
  state: ConnectionState;
  connected: boolean;
  reconnects: number;
  queuedMessages: number;
  connectionDurationMs: number;
  url: string;
}

export interface ConnectionStore {
  // State
  state: ConnectionState;
  metrics: ConnectionMetrics | null;
  lastError: Error | null;
  isConnected: boolean;

  // Actions
  updateState: (state: ConnectionState) => void;
  updateMetrics: (metrics: ConnectionMetrics) => void;
  setError: (error: Error) => void;
  clearError: () => void;

  // Helpers
  getConnectionStatus: () => string;
  isReconnecting: () => boolean;
  hasQueuedMessages: () => boolean;
}

export const useConnectionStore = create<ConnectionStore>((set, get) => ({
  // Initial state
  state: ConnectionState.CLOSED,
  metrics: null,
  lastError: null,
  isConnected: false,

  updateState: (state: ConnectionState) => {
    set({
      state,
      isConnected: state === ConnectionState.CONNECTED,
    });
  },

  updateMetrics: (metrics: ConnectionMetrics) => {
    set({
      metrics,
      isConnected: metrics.connected,
      state: metrics.state,
    });
  },

  setError: (error: Error) => {
    set({ lastError: error });
  },

  clearError: () => {
    set({ lastError: null });
  },

  getConnectionStatus: () => {
    const state = get().state;
    const metrics = get().metrics;

    switch (state) {
      case ConnectionState.CONNECTED:
        return `Connected (${Math.round((metrics?.connectionDurationMs || 0) / 1000)}s)`;
      case ConnectionState.CONNECTING:
        return 'Connecting...';
      case ConnectionState.RECONNECTING:
        return `Reconnecting (attempt ${(metrics?.reconnects || 0) + 1})...`;
      case ConnectionState.DISCONNECTED:
        return 'Disconnected';
      case ConnectionState.ERROR:
        return 'Connection error';
      case ConnectionState.CLOSED:
        return 'Closed';
      default:
        return 'Unknown';
    }
  },

  isReconnecting: () => {
    return get().state === ConnectionState.RECONNECTING;
  },

  hasQueuedMessages: () => {
    return (get().metrics?.queuedMessages || 0) > 0;
  },
}));

/**
 * Hook for components to use connection state
 */
export function useConnection() {
  const { state, isConnected, metrics, lastError, getConnectionStatus, hasQueuedMessages, isReconnecting } =
    useConnectionStore();

  return {
    state,
    isConnected,
    metrics,
    lastError,
    status: getConnectionStatus(),
    hasQueuedMessages: hasQueuedMessages(),
    isReconnecting: isReconnecting(),
  };
}

/**
 * Get connection state color for UI
 */
export function getConnectionStateColor(state: ConnectionState): string {
  switch (state) {
    case ConnectionState.CONNECTED:
      return '#10b981'; // Green
    case ConnectionState.CONNECTING:
    case ConnectionState.RECONNECTING:
      return '#f59e0b'; // Amber
    case ConnectionState.DISCONNECTED:
      return '#ef4444'; // Red
    case ConnectionState.ERROR:
      return '#dc2626'; // Dark red
    case ConnectionState.CLOSED:
      return '#6b7280'; // Gray
    default:
      return '#9ca3af';
  }
}

/**
 * Get connection state emoji
 */
export function getConnectionStateEmoji(state: ConnectionState): string {
  switch (state) {
    case ConnectionState.CONNECTED:
      return '🟢'; // Green dot
    case ConnectionState.CONNECTING:
    case ConnectionState.RECONNECTING:
      return '🟡'; // Yellow dot
    case ConnectionState.DISCONNECTED:
      return '🔴'; // Red dot
    case ConnectionState.ERROR:
      return '⚠️'; // Warning
    case ConnectionState.CLOSED:
      return '⬜'; // Gray
    default:
      return '❓';
  }
}
