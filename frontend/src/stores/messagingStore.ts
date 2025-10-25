import { create } from 'zustand';
import { OfflineQueue } from '../services/offlineQueue/Queue';
import { EnhancedWebSocketClient, ConnectionState, createWebSocketClient, getWebSocketClient } from '../services/websocket/EnhancedWebSocketClient';
import { useErrorStore } from '../services/api/errorStore';
import { toNovaError, logError, createErrorContext } from '../services/api/errors';
import { useConnectionStore } from './connectionStore';

type Conversation = { id: string; name?: string | null };
type Message = { id: string; sender_id: string; sequence_number: number; created_at?: string; preview?: string };

type MessagingState = {
  apiBase: string;
  wsBase: string;
  conversations: Conversation[];
  currentConversationId: string | null;
  messages: Record<string, Message[]>;
  typing: Record<string, string[]>; // conversationId -> userIds typing
  setCurrentConversation: (id: string) => void;
  loadMessages: (conversationId: string) => Promise<void>;
  sendMessage: (conversationId: string, userId: string, plaintext: string) => Promise<void>;
  addConversation: (c: Conversation) => void;
  connectWs: (conversationId: string, userId: string) => void;
  disconnectWs: () => void;
  sendTyping: (conversationId: string, userId: string) => void;
};

const queue = new OfflineQueue();

export const useMessagingStore = create<MessagingState>((set, get) => ({
  apiBase: (import.meta as any).env?.VITE_API_BASE || 'http://localhost:8080',
  wsBase: (import.meta as any).env?.VITE_WS_BASE || 'ws://localhost:8085',
  conversations: [],
  currentConversationId: null,
  messages: {},
  typing: {},
  setCurrentConversation: (id) => set({ currentConversationId: id }),
  addConversation: (c) => set((s) => ({ conversations: [...s.conversations, c] })),
  loadMessages: async (conversationId) => {
    const base = get().apiBase;
    const errorContext = createErrorContext();
    errorContext.requestUrl = `/conversations/${conversationId}/messages`;
    errorContext.requestMethod = 'GET';

    try {
      const res = await fetch(`${base}/conversations/${conversationId}/messages`);

      if (!res.ok) {
        throw new Error(`HTTP ${res.status}: Failed to load messages`);
      }

      const list = await res.json();
      set((s) => ({ messages: { ...s.messages, [conversationId]: list } }));
    } catch (error) {
      const novaError = toNovaError(error);
      logError(novaError, errorContext);
      // Don't re-throw here - silently log to allow UI to continue
      useErrorStore.getState().addError(novaError);
    }
  },
  sendMessage: async (conversationId, userId, plaintext) => {
    const base = get().apiBase;
    const idempotencyKey = crypto.randomUUID();
    const errorContext = createErrorContext(userId);
    errorContext.requestUrl = `/conversations/${conversationId}/messages`;
    errorContext.requestMethod = 'POST';

    try {
      const res = await fetch(`${base}/conversations/${conversationId}/messages`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sender_id: userId, plaintext, idempotency_key: idempotencyKey }),
      });

      if (!res.ok) {
        throw new Error(`HTTP ${res.status}: Failed to send message`);
      }

      const payload = await res.json();
      const msg: Message = {
        id: payload.id,
        sender_id: userId,
        sequence_number: payload.sequence_number,
        preview: plaintext,
      };
      set((s) => ({
        messages: { ...s.messages, [conversationId]: [...(s.messages[conversationId] ?? []), msg] },
      }));
    } catch (error) {
      const novaError = toNovaError(error);

      // Log the error with context
      logError(novaError, errorContext);

      // Check if error is retryable (network issue, timeout)
      if (novaError.isRetryable) {
        // Offline fallback for retryable errors
        useErrorStore.getState().addError(novaError);
        queue.enqueue({ conversationId, userId, plaintext, idempotencyKey });
      } else {
        // For non-retryable errors (like 401), show error to user but don't queue
        useErrorStore.getState().addError(novaError);
        return;
      }

      // Add optimistic message
      const msg: Message = {
        id: idempotencyKey,
        sender_id: userId,
        sequence_number: (get().messages[conversationId]?.length ?? 0) + 1,
        preview: plaintext,
      };
      set((s) => ({
        messages: { ...s.messages, [conversationId]: [...(s.messages[conversationId] ?? []), msg] },
      }));
    }
  },
  connectWs: (conversationId: string, userId: string) => {
    // Close previous if any
    const prevClient = getWebSocketClient();
    if (prevClient) {
      prevClient.disconnect();
    }

    const url = `${get().wsBase}/ws?conversation_id=${conversationId}&user_id=${userId}`;

    // Create new enhanced WebSocket client with auto-reconnect
    const client = createWebSocketClient(
      url,
      {
        onMessage: (payload) => {
          try {
            const m = payload?.message;
            if (!m) return;
            set((s) => {
              const curr = s.messages[conversationId] ?? [];
              // de-dup by id or sequence_number
              if (curr.some((x) => x.id === m.id || x.sequence_number === m.sequence_number)) {
                return {} as any;
              }
              const next = [...curr, { id: m.id, sender_id: m.sender_id, sequence_number: m.sequence_number }]
                .sort((a, b) => a.sequence_number - b.sequence_number);
              return { messages: { ...s.messages, [conversationId]: next } } as any;
            });
          } catch (error) {
            console.error('[Messaging] Message processing error:', error);
          }
        },

        onTyping: (convId, user) => {
          if (convId !== conversationId) return;
          set((s) => {
            const list = new Set([...(s.typing[conversationId] ?? [])]);
            list.add(user);
            return { typing: { ...s.typing, [conversationId]: Array.from(list) } };
          });
          // Auto-clear after 3s
          setTimeout(() => {
            set((s) => {
              const curr = new Set([...(s.typing[conversationId] ?? [])]);
              curr.delete(user);
              return { typing: { ...s.typing, [conversationId]: Array.from(curr) } };
            });
          }, 3000);
        },

        onOpen: async () => {
          console.log('[Messaging] WebSocket connected');
          useConnectionStore.getState().updateState(ConnectionState.CONNECTED);

          // === CRITICAL FIX: Drain offline queue when connection restored ===
          // Send all queued messages that were accumulated while offline
          try {
            const queuedMessages = await queue.drain();
            if (queuedMessages.length > 0) {
              console.log(`[Messaging] Draining ${queuedMessages.length} offline messages`);

              // Resend each queued message
              for (const msg of queuedMessages) {
                // Only resend if it's for the current conversation
                if (msg.conversationId === conversationId) {
                  try {
                    const res = await fetch(`${get().apiBase}/conversations/${conversationId}/messages`, {
                      method: 'POST',
                      headers: { 'Content-Type': 'application/json' },
                      body: JSON.stringify({
                        sender_id: msg.userId,
                        plaintext: msg.plaintext,
                        idempotency_key: msg.idempotencyKey,
                      }),
                    });

                    if (!res.ok) {
                      console.warn(
                        `[Messaging] Failed to resend offline message (${res.status}), re-queueing`
                      );
                      // Re-queue if resend failed
                      await queue.enqueue(msg);
                    } else {
                      console.log(`[Messaging] Successfully resent offline message: ${msg.idempotencyKey}`);
                    }
                  } catch (error) {
                    console.error(`[Messaging] Error resending offline message:`, error);
                    // Re-queue on error
                    await queue.enqueue(msg);
                  }
                }
              }
            }
          } catch (error) {
            console.error('[Messaging] Failed to drain offline queue:', error);
          }
        },

        onClose: () => {
          console.log('[Messaging] WebSocket disconnected');
          useConnectionStore.getState().updateState(ConnectionState.DISCONNECTED);
        },

        onError: (error) => {
          console.error('[Messaging] WebSocket error:', error);
          useErrorStore.getState().addError(
            toNovaError(new Error('WebSocket connection error'))
          );
        },

        onStateChange: (state: ConnectionState) => {
          // Update connection store with metrics
          const wsClient = getWebSocketClient();
          if (wsClient) {
            const metrics = wsClient.getMetrics();
            useConnectionStore.getState().updateMetrics(metrics);
          }
        },
      },
      {
        maxRetries: 10,
        initialDelayMs: 1000,
        maxDelayMs: 30000,
        backoffMultiplier: 1.5,
        backoffJitter: true,
      }
    );

    client.connect();
  },

  disconnectWs: () => {
    const client = getWebSocketClient();
    if (client) {
      client.disconnect();
      useConnectionStore.getState().updateState(ConnectionState.CLOSED);
    }
  },

  sendTyping: (conversationId: string, userId: string) => {
    const client = getWebSocketClient();
    if (client && client.getState() === ConnectionState.CONNECTED) {
      client.sendTyping(conversationId, userId);
    }
  },
}));
