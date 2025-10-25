/**
 * Offline queue with encrypted localStorage.
 *
 * Design principles:
 * 1. Encrypt entire queue, not individual messages (simpler)
 * 2. If decryption fails, discard queue (don't return corrupted data)
 * 3. If encryption not ready, fall back to memory-only queue
 * 4. Deduplicate by idempotencyKey
 */

import { storageEncryption, type EncryptedData } from '../encryption/localStorage';

export type QueuedMessage = {
  conversationId: string;
  userId: string;
  plaintext: string;
  idempotencyKey: string;
};

const KEY = 'offline:queue:encrypted';

/**
 * Load and decrypt queue from localStorage.
 * Returns empty array if decryption fails or data is corrupted.
 */
function load(): QueuedMessage[] {
  try {
    // Check if encryption is ready
    if (!storageEncryption.isReady()) {
      console.warn('OfflineQueue: encryption not initialized, returning empty queue');
      return [];
    }

    const raw = localStorage.getItem(KEY);
    if (!raw) {
      return [];
    }

    // Parse encrypted data
    const encrypted: EncryptedData = JSON.parse(raw);

    // Decrypt synchronously (we'll handle this properly below)
    // Note: We'll need to make load() async or use a different approach
    // For now, we'll store the encrypted data and decrypt on demand
    return []; // Temporary - will fix this
  } catch (error) {
    // Decryption failed or data corrupted - discard queue
    console.error('OfflineQueue: failed to load queue, discarding', error);
    localStorage.removeItem(KEY);
    return [];
  }
}

/**
 * Encrypt and save queue to localStorage.
 */
async function save(items: QueuedMessage[]): Promise<void> {
  try {
    // Check if encryption is ready
    if (!storageEncryption.isReady()) {
      console.warn('OfflineQueue: encryption not initialized, not persisting queue');
      return;
    }

    if (items.length === 0) {
      localStorage.removeItem(KEY);
      return;
    }

    // Encrypt entire queue
    const encrypted = await storageEncryption.encrypt(items);
    localStorage.setItem(KEY, JSON.stringify(encrypted));
  } catch (error) {
    console.error('OfflineQueue: failed to save queue', error);
  }
}

/**
 * Offline message queue with encrypted persistence.
 *
 * IMPORTANT: Must initialize storageEncryption before using this class.
 * Otherwise, queue will work in memory-only mode.
 */
export class OfflineQueue {
  private memoryQueue: QueuedMessage[] = [];
  private initialized = false;

  /**
   * Initialize queue by loading from storage.
   * Call this once after encryption is ready.
   */
  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    try {
      if (!storageEncryption.isReady()) {
        console.warn('OfflineQueue: encryption not ready, using memory-only mode');
        this.initialized = true;
        return;
      }

      const raw = localStorage.getItem(KEY);
      if (!raw) {
        this.initialized = true;
        return;
      }

      // Parse and decrypt
      const encrypted: EncryptedData = JSON.parse(raw);
      this.memoryQueue = await storageEncryption.decrypt<QueuedMessage[]>(encrypted);
      this.initialized = true;
    } catch (error) {
      // Decryption failed - discard corrupted data
      console.error('OfflineQueue: failed to decrypt queue, discarding', error);
      localStorage.removeItem(KEY);
      this.memoryQueue = [];
      this.initialized = true;
    }
  }

  /**
   * Add message to queue.
   * Deduplicates by idempotencyKey.
   */
  async enqueue(item: QueuedMessage): Promise<void> {
    if (!this.initialized) {
      await this.initialize();
    }

    // Avoid duplicates by idempotencyKey
    if (this.memoryQueue.find((i) => i.idempotencyKey === item.idempotencyKey)) {
      return;
    }

    this.memoryQueue.push(item);
    await save(this.memoryQueue);
  }

  /**
   * Drain all messages from queue.
   * Returns all queued messages and clears the queue.
   */
  async drain(): Promise<QueuedMessage[]> {
    if (!this.initialized) {
      await this.initialize();
    }

    const items = [...this.memoryQueue];
    this.memoryQueue = [];
    await save([]);
    return items;
  }

  /**
   * Get current queue size without draining.
   */
  size(): number {
    return this.memoryQueue.length;
  }

  /**
   * Clear queue without returning items.
   */
  async clear(): Promise<void> {
    this.memoryQueue = [];
    await save([]);
  }
}
