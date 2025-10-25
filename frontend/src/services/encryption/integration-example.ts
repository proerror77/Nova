/**
 * Integration example: How to use encrypted localStorage in Nova frontend.
 *
 * This file demonstrates the complete lifecycle of encryption initialization,
 * usage, and cleanup in a React application.
 */

import { storageEncryption } from './localStorage';
import { OfflineQueue } from '../offlineQueue/Queue';

/**
 * Example 1: Initialize encryption on login
 *
 * This should be called after successful authentication.
 */
export async function onLoginSuccess(
  userId: string,
  sessionToken: string
): Promise<void> {
  console.log('User logged in, initializing encryption...');

  // Option 1: Derive key from session token
  // (More secure if you want key to be consistent across sessions)
  const keyMaterial = await deriveKeyFromSession(sessionToken, userId);
  await storageEncryption.initialize(keyMaterial);

  // Option 2: Generate random key for this session only
  // (Simpler but data can't be recovered after logout)
  // await storageEncryption.generateKey();

  console.log('Encryption initialized');
}

/**
 * Example 2: Use encrypted offline queue
 *
 * This should be used in your messaging component.
 */
export async function sendMessageWithOfflineSupport(
  conversationId: string,
  userId: string,
  messageText: string
): Promise<void> {
  const queue = new OfflineQueue();

  // Check if online
  if (navigator.onLine) {
    try {
      // Send directly
      await sendMessageToServer(conversationId, messageText);
    } catch (error) {
      // Failed to send, queue for later
      await queue.enqueue({
        conversationId,
        userId,
        plaintext: messageText,
        idempotencyKey: `${userId}-${Date.now()}-${Math.random()}`,
      });
      console.log('Message queued for offline delivery');
    }
  } else {
    // Offline, queue immediately
    await queue.enqueue({
      conversationId,
      userId,
      plaintext: messageText,
      idempotencyKey: `${userId}-${Date.now()}-${Math.random()}`,
    });
    console.log('Offline: message queued');
  }
}

/**
 * Example 3: Process offline queue when coming online
 *
 * This should be called when the app detects network connectivity.
 */
export async function processOfflineQueue(): Promise<void> {
  console.log('Network is back, processing offline queue...');

  const queue = new OfflineQueue();
  const messages = await queue.drain();

  console.log(`Found ${messages.length} queued messages`);

  for (const msg of messages) {
    try {
      await sendMessageToServer(msg.conversationId, msg.plaintext);
      console.log(`Sent queued message: ${msg.idempotencyKey}`);
    } catch (error) {
      // Failed again, re-queue
      await queue.enqueue(msg);
      console.error(`Failed to send queued message: ${msg.idempotencyKey}`, error);
    }
  }
}

/**
 * Example 4: Clean up on logout
 *
 * This should be called when user logs out.
 */
export async function onLogout(): Promise<void> {
  console.log('User logging out, cleaning up...');

  // Clear offline queue
  const queue = new OfflineQueue();
  await queue.clear();

  // Destroy encryption key
  storageEncryption.destroy();

  // Clear all localStorage (optional, but recommended)
  localStorage.clear();

  console.log('Cleanup complete');
}

/**
 * Example 5: React hook for encryption initialization
 *
 * This can be used in your App.tsx or authentication context.
 */
export function useEncryptionInitialization(
  isAuthenticated: boolean,
  userId: string | null,
  sessionToken: string | null
) {
  // React example (pseudo-code, adjust for your framework)
  /*
  useEffect(() => {
    if (isAuthenticated && userId && sessionToken) {
      // Initialize encryption when user logs in
      onLoginSuccess(userId, sessionToken).catch(console.error);
    } else {
      // Clean up when user logs out
      onLogout().catch(console.error);
    }
  }, [isAuthenticated, userId, sessionToken]);
  */
}

/**
 * Example 6: Network status listener
 *
 * This can be used in your App.tsx to automatically process queue.
 */
export function useNetworkStatusListener() {
  // React example (pseudo-code)
  /*
  useEffect(() => {
    const handleOnline = () => {
      console.log('Network online');
      processOfflineQueue().catch(console.error);
    };

    const handleOffline = () => {
      console.log('Network offline');
    };

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);
  */
}

// ============================================================================
// Helper functions (implementation depends on your backend)
// ============================================================================

/**
 * Derive encryption key from session token and user ID.
 *
 * Uses PBKDF2 to derive a 256-bit key from session token.
 * This ensures the key is deterministic (same session = same key).
 */
async function deriveKeyFromSession(
  sessionToken: string,
  userId: string
): Promise<Uint8Array> {
  // Use session token as password
  const password = new TextEncoder().encode(sessionToken);

  // Use user ID as salt (deterministic)
  const salt = new TextEncoder().encode(`nova-storage-${userId}`);

  // Import password
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    password,
    'PBKDF2',
    false,
    ['deriveBits']
  );

  // Derive 256-bit key
  const bits = await crypto.subtle.deriveBits(
    {
      name: 'PBKDF2',
      salt,
      iterations: 100000, // OWASP recommendation
      hash: 'SHA-256',
    },
    keyMaterial,
    256 // 256 bits
  );

  return new Uint8Array(bits);
}

/**
 * Send message to server (placeholder).
 * Replace with your actual API call.
 */
async function sendMessageToServer(
  conversationId: string,
  messageText: string
): Promise<void> {
  // Example API call
  const response = await fetch(`/api/conversations/${conversationId}/messages`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${localStorage.getItem('token')}`,
    },
    body: JSON.stringify({ text: messageText }),
  });

  if (!response.ok) {
    throw new Error(`Failed to send message: ${response.statusText}`);
  }
}

// ============================================================================
// Complete React component example
// ============================================================================

/**
 * Example React component that uses encrypted offline queue.
 */
export const MessagingComponentExample = () => {
  /*
  // State
  const [messageText, setMessageText] = useState('');
  const [isSending, setIsSending] = useState(false);

  // Authentication context
  const { userId, isAuthenticated } = useAuth();

  // Send message handler
  const handleSendMessage = async () => {
    if (!messageText.trim() || !userId) return;

    setIsSending(true);
    try {
      await sendMessageWithOfflineSupport(
        'conv-123', // Replace with actual conversation ID
        userId,
        messageText
      );
      setMessageText('');
    } catch (error) {
      console.error('Failed to send message', error);
    } finally {
      setIsSending(false);
    }
  };

  return (
    <div>
      <textarea
        value={messageText}
        onChange={(e) => setMessageText(e.target.value)}
        placeholder="Type a message..."
        disabled={!isAuthenticated}
      />
      <button onClick={handleSendMessage} disabled={isSending || !isAuthenticated}>
        {isSending ? 'Sending...' : 'Send'}
      </button>
      {!navigator.onLine && (
        <div className="offline-notice">
          You're offline. Message will be sent when connection is restored.
        </div>
      )}
    </div>
  );
  */
};
