/**
 * Tests for localStorage encryption.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { StorageEncryption } from '../localStorage';

describe('StorageEncryption', () => {
  let encryption: StorageEncryption;

  beforeEach(() => {
    encryption = new StorageEncryption();
  });

  describe('initialization', () => {
    it('should not be ready before initialization', () => {
      expect(encryption.isReady()).toBe(false);
    });

    it('should be ready after initialization with valid key', async () => {
      const key = crypto.getRandomValues(new Uint8Array(32));
      await encryption.initialize(key);
      expect(encryption.isReady()).toBe(true);
    });

    it('should reject key material that is not 32 bytes', async () => {
      const key = crypto.getRandomValues(new Uint8Array(16)); // Wrong size
      await expect(encryption.initialize(key)).rejects.toThrow(
        'Key material must be exactly 32 bytes'
      );
    });

    it('should generate random key', async () => {
      await encryption.generateKey();
      expect(encryption.isReady()).toBe(true);
    });

    it('should clear key on destroy', async () => {
      await encryption.generateKey();
      expect(encryption.isReady()).toBe(true);

      encryption.destroy();
      expect(encryption.isReady()).toBe(false);
    });
  });

  describe('encryption and decryption', () => {
    beforeEach(async () => {
      await encryption.generateKey();
    });

    it('should encrypt and decrypt simple string', async () => {
      const original = 'Hello, World!';
      const encrypted = await encryption.encrypt(original);

      expect(encrypted.ciphertext).toBeTruthy();
      expect(encrypted.iv).toBeTruthy();
      expect(encrypted.ciphertext).not.toBe(original);

      const decrypted = await encryption.decrypt<string>(encrypted);
      expect(decrypted).toBe(original);
    });

    it('should encrypt and decrypt complex object', async () => {
      const original = {
        id: 'msg-123',
        text: 'Secret message',
        timestamp: 1234567890,
        nested: { foo: 'bar', arr: [1, 2, 3] },
      };

      const encrypted = await encryption.encrypt(original);
      const decrypted = await encryption.decrypt<typeof original>(encrypted);

      expect(decrypted).toEqual(original);
    });

    it('should encrypt and decrypt array', async () => {
      const original = [
        { id: '1', text: 'First' },
        { id: '2', text: 'Second' },
      ];

      const encrypted = await encryption.encrypt(original);
      const decrypted = await encryption.decrypt<typeof original>(encrypted);

      expect(decrypted).toEqual(original);
    });

    it('should produce different ciphertext for same plaintext', async () => {
      const plaintext = 'Same data';

      const encrypted1 = await encryption.encrypt(plaintext);
      const encrypted2 = await encryption.encrypt(plaintext);

      // Different IV = different ciphertext (even for same plaintext)
      expect(encrypted1.ciphertext).not.toBe(encrypted2.ciphertext);
      expect(encrypted1.iv).not.toBe(encrypted2.iv);

      // But both decrypt to same plaintext
      expect(await encryption.decrypt<string>(encrypted1)).toBe(plaintext);
      expect(await encryption.decrypt<string>(encrypted2)).toBe(plaintext);
    });

    it('should fail to encrypt without initialization', async () => {
      const uninitializedEncryption = new StorageEncryption();
      await expect(uninitializedEncryption.encrypt('data')).rejects.toThrow(
        'StorageEncryption not initialized'
      );
    });

    it('should fail to decrypt without initialization', async () => {
      const uninitializedEncryption = new StorageEncryption();
      await expect(
        uninitializedEncryption.decrypt({ ciphertext: 'xxx', iv: 'yyy' })
      ).rejects.toThrow('StorageEncryption not initialized');
    });
  });

  describe('tamper detection', () => {
    beforeEach(async () => {
      await encryption.generateKey();
    });

    it('should fail to decrypt tampered ciphertext', async () => {
      const original = 'Important data';
      const encrypted = await encryption.encrypt(original);

      // Tamper with ciphertext
      const tampered = {
        ...encrypted,
        ciphertext: encrypted.ciphertext.slice(0, -4) + 'XXXX',
      };

      await expect(encryption.decrypt(tampered)).rejects.toThrow('Decryption failed');
    });

    it('should fail to decrypt with wrong IV', async () => {
      const original = 'Important data';
      const encrypted = await encryption.encrypt(original);

      // Use different IV
      const wrongIv = {
        ...encrypted,
        iv: encrypted.iv.slice(0, -4) + 'YYYY',
      };

      await expect(encryption.decrypt(wrongIv)).rejects.toThrow('Decryption failed');
    });

    it('should fail to decrypt with different key', async () => {
      const original = 'Important data';
      const encrypted = await encryption.encrypt(original);

      // Create new encryption instance with different key
      const otherEncryption = new StorageEncryption();
      await otherEncryption.generateKey();

      await expect(otherEncryption.decrypt(encrypted)).rejects.toThrow(
        'Decryption failed'
      );
    });
  });

  describe('edge cases', () => {
    beforeEach(async () => {
      await encryption.generateKey();
    });

    it('should handle empty string', async () => {
      const encrypted = await encryption.encrypt('');
      const decrypted = await encryption.decrypt<string>(encrypted);
      expect(decrypted).toBe('');
    });

    it('should handle empty array', async () => {
      const encrypted = await encryption.encrypt([]);
      const decrypted = await encryption.decrypt<unknown[]>(encrypted);
      expect(decrypted).toEqual([]);
    });

    it('should handle empty object', async () => {
      const encrypted = await encryption.encrypt({});
      const decrypted = await encryption.decrypt<object>(encrypted);
      expect(decrypted).toEqual({});
    });

    it('should handle null', async () => {
      const encrypted = await encryption.encrypt(null);
      const decrypted = await encryption.decrypt<null>(encrypted);
      expect(decrypted).toBe(null);
    });

    it('should handle unicode characters', async () => {
      const original = '🔐 Unicode test: 你好世界 مرحبا العالم';
      const encrypted = await encryption.encrypt(original);
      const decrypted = await encryption.decrypt<string>(encrypted);
      expect(decrypted).toBe(original);
    });

    it('should handle large data', async () => {
      // Create 1MB of data
      const largeArray = Array.from({ length: 10000 }, (_, i) => ({
        id: `msg-${i}`,
        text: 'A'.repeat(100),
      }));

      const encrypted = await encryption.encrypt(largeArray);
      const decrypted = await encryption.decrypt<typeof largeArray>(encrypted);

      expect(decrypted).toEqual(largeArray);
    });
  });
});
