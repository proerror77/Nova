/**
 * Tests for encrypted offline queue.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { OfflineQueue, type QueuedMessage } from '../Queue';
import { storageEncryption } from '../../encryption/localStorage';

describe('OfflineQueue', () => {
  let queue: OfflineQueue;

  beforeEach(async () => {
    // Clear localStorage
    localStorage.clear();

    // Initialize encryption
    await storageEncryption.generateKey();

    // Create fresh queue
    queue = new OfflineQueue();
  });

  afterEach(() => {
    storageEncryption.destroy();
    localStorage.clear();
  });

  const createMessage = (id: string): QueuedMessage => ({
    conversationId: 'conv-1',
    userId: 'user-1',
    plaintext: `Message ${id}`,
    idempotencyKey: `key-${id}`,
  });

  describe('basic operations', () => {
    it('should start empty', async () => {
      await queue.initialize();
      expect(queue.size()).toBe(0);
    });

    it('should enqueue message', async () => {
      const msg = createMessage('1');
      await queue.enqueue(msg);

      expect(queue.size()).toBe(1);
    });

    it('should drain messages', async () => {
      const msg1 = createMessage('1');
      const msg2 = createMessage('2');

      await queue.enqueue(msg1);
      await queue.enqueue(msg2);

      const drained = await queue.drain();

      expect(drained).toHaveLength(2);
      expect(drained[0]).toEqual(msg1);
      expect(drained[1]).toEqual(msg2);
      expect(queue.size()).toBe(0);
    });

    it('should clear queue', async () => {
      await queue.enqueue(createMessage('1'));
      await queue.enqueue(createMessage('2'));

      await queue.clear();

      expect(queue.size()).toBe(0);
      expect(await queue.drain()).toHaveLength(0);
    });
  });

  describe('deduplication', () => {
    it('should deduplicate by idempotencyKey', async () => {
      const msg1 = createMessage('1');
      const msg1Duplicate = { ...msg1, plaintext: 'Different text' };

      await queue.enqueue(msg1);
      await queue.enqueue(msg1Duplicate);

      expect(queue.size()).toBe(1);

      const drained = await queue.drain();
      expect(drained[0]).toEqual(msg1); // First version wins
    });

    it('should allow different idempotencyKeys', async () => {
      const msg1 = createMessage('1');
      const msg2 = createMessage('2');

      await queue.enqueue(msg1);
      await queue.enqueue(msg2);

      expect(queue.size()).toBe(2);
    });
  });

  describe('persistence', () => {
    it('should persist to localStorage encrypted', async () => {
      const msg = createMessage('1');
      await queue.enqueue(msg);

      // Check localStorage
      const stored = localStorage.getItem('offline:queue:encrypted');
      expect(stored).toBeTruthy();

      // Should be encrypted (not plain JSON)
      expect(() => {
        const parsed = JSON.parse(stored!);
        // Should have encryption structure
        expect(parsed).toHaveProperty('ciphertext');
        expect(parsed).toHaveProperty('iv');
        // Ciphertext should not contain plaintext
        expect(parsed.ciphertext).not.toContain('Message 1');
      }).not.toThrow();
    });

    it('should restore from localStorage after restart', async () => {
      const msg1 = createMessage('1');
      const msg2 = createMessage('2');

      await queue.enqueue(msg1);
      await queue.enqueue(msg2);

      // Create new queue instance (simulating app restart)
      const newQueue = new OfflineQueue();
      await newQueue.initialize();

      expect(newQueue.size()).toBe(2);

      const drained = await newQueue.drain();
      expect(drained).toHaveLength(2);
      expect(drained[0]).toEqual(msg1);
      expect(drained[1]).toEqual(msg2);
    });

    it('should remove from localStorage when drained', async () => {
      await queue.enqueue(createMessage('1'));
      await queue.drain();

      const stored = localStorage.getItem('offline:queue:encrypted');
      expect(stored).toBeNull();
    });

    it('should remove from localStorage when cleared', async () => {
      await queue.enqueue(createMessage('1'));
      await queue.clear();

      const stored = localStorage.getItem('offline:queue:encrypted');
      expect(stored).toBeNull();
    });
  });

  describe('encryption failure handling', () => {
    it('should work in memory-only mode without encryption', async () => {
      // Destroy encryption key
      storageEncryption.destroy();

      const memoryQueue = new OfflineQueue();
      const msg = createMessage('1');

      await memoryQueue.enqueue(msg);
      expect(memoryQueue.size()).toBe(1);

      // Should not persist to localStorage
      const stored = localStorage.getItem('offline:queue:encrypted');
      expect(stored).toBeNull();

      // But should work in memory
      const drained = await memoryQueue.drain();
      expect(drained).toHaveLength(1);
      expect(drained[0]).toEqual(msg);
    });

    it('should discard corrupted data', async () => {
      // Store corrupted data
      localStorage.setItem(
        'offline:queue:encrypted',
        JSON.stringify({ ciphertext: 'corrupted', iv: 'invalid' })
      );

      const newQueue = new OfflineQueue();
      await newQueue.initialize();

      // Should start empty (corrupted data discarded)
      expect(newQueue.size()).toBe(0);

      // Corrupted data should be removed
      const stored = localStorage.getItem('offline:queue:encrypted');
      expect(stored).toBeNull();
    });

    it('should discard data encrypted with different key', async () => {
      // Enqueue with first key
      await queue.enqueue(createMessage('1'));

      // Destroy and create new key (simulating different session)
      storageEncryption.destroy();
      await storageEncryption.generateKey();

      // Try to load with different key
      const newQueue = new OfflineQueue();
      await newQueue.initialize();

      // Should start empty (can't decrypt with different key)
      expect(newQueue.size()).toBe(0);
    });

    it('should handle JSON parse errors', async () => {
      // Store invalid JSON
      localStorage.setItem('offline:queue:encrypted', 'not valid json{');

      const newQueue = new OfflineQueue();
      await newQueue.initialize();

      expect(newQueue.size()).toBe(0);
      expect(localStorage.getItem('offline:queue:encrypted')).toBeNull();
    });
  });

  describe('auto-initialization', () => {
    it('should auto-initialize on enqueue', async () => {
      const freshQueue = new OfflineQueue();
      // Don't call initialize()

      const msg = createMessage('1');
      await freshQueue.enqueue(msg);

      expect(freshQueue.size()).toBe(1);
    });

    it('should auto-initialize on drain', async () => {
      const freshQueue = new OfflineQueue();
      // Don't call initialize()

      const drained = await freshQueue.drain();
      expect(drained).toHaveLength(0);
    });

    it('should only initialize once', async () => {
      const freshQueue = new OfflineQueue();

      await freshQueue.initialize();
      await freshQueue.initialize(); // Second call should be no-op

      const msg = createMessage('1');
      await freshQueue.enqueue(msg);

      expect(freshQueue.size()).toBe(1);
    });
  });

  describe('edge cases', () => {
    it('should handle empty plaintext', async () => {
      const msg = { ...createMessage('1'), plaintext: '' };
      await queue.enqueue(msg);

      const drained = await queue.drain();
      expect(drained[0].plaintext).toBe('');
    });

    it('should handle unicode in plaintext', async () => {
      const msg = {
        ...createMessage('1'),
        plaintext: '🔐 Unicode: 你好 مرحبا',
      };

      await queue.enqueue(msg);
      const drained = await queue.drain();

      expect(drained[0].plaintext).toBe(msg.plaintext);
    });

    it('should handle large queue', async () => {
      // Enqueue 1000 messages
      for (let i = 0; i < 1000; i++) {
        await queue.enqueue(createMessage(i.toString()));
      }

      expect(queue.size()).toBe(1000);

      const drained = await queue.drain();
      expect(drained).toHaveLength(1000);
    });

    it('should handle rapid enqueue/drain cycles', async () => {
      for (let cycle = 0; cycle < 10; cycle++) {
        await queue.enqueue(createMessage('1'));
        await queue.enqueue(createMessage('2'));

        const drained = await queue.drain();
        expect(drained).toHaveLength(2);
        expect(queue.size()).toBe(0);
      }
    });
  });
});
