/**
 * Visual verification test: Shows what encrypted data looks like in localStorage.
 *
 * This test demonstrates that data is truly encrypted and unreadable.
 */

import { describe, it, beforeEach, afterEach } from 'vitest';
import { storageEncryption } from '../localStorage';
import { OfflineQueue, type QueuedMessage } from '../../offlineQueue/Queue';

describe('Visual Verification: Encrypted Data in localStorage', () => {
  beforeEach(async () => {
    localStorage.clear();
    await storageEncryption.generateKey();
  });

  afterEach(() => {
    storageEncryption.destroy();
    localStorage.clear();
  });

  it('should show encrypted data in localStorage', async () => {
    const queue = new OfflineQueue();

    // Create some sensitive messages
    const messages: QueuedMessage[] = [
      {
        conversationId: 'secret-conversation-123',
        userId: 'user-alice',
        plaintext: 'This is a secret message that should be encrypted! 🔐',
        idempotencyKey: 'msg-1',
      },
      {
        conversationId: 'secret-conversation-123',
        userId: 'user-alice',
        plaintext: 'Another confidential message with sensitive data',
        idempotencyKey: 'msg-2',
      },
      {
        conversationId: 'secret-conversation-456',
        userId: 'user-bob',
        plaintext: 'Private conversation between Alice and Bob',
        idempotencyKey: 'msg-3',
      },
    ];

    // Enqueue messages
    for (const msg of messages) {
      await queue.enqueue(msg);
    }

    // Check what's actually stored in localStorage
    const stored = localStorage.getItem('offline:queue:encrypted');

    console.log('\n========================================');
    console.log('📦 RAW DATA IN LOCALSTORAGE:');
    console.log('========================================');
    console.log(stored);
    console.log('========================================\n');

    // Parse the encrypted structure
    const encrypted = JSON.parse(stored!);

    console.log('🔐 ENCRYPTED STRUCTURE:');
    console.log('========================================');
    console.log('Ciphertext (first 100 chars):', encrypted.ciphertext.substring(0, 100));
    console.log('Ciphertext length:', encrypted.ciphertext.length);
    console.log('IV:', encrypted.iv);
    console.log('========================================\n');

    // Verify sensitive data is NOT in ciphertext
    console.log('🔍 PLAINTEXT SEARCH IN CIPHERTEXT:');
    console.log('========================================');

    const plaintextStrings = [
      'secret',
      'confidential',
      'Alice',
      'Bob',
      'This is a secret message',
      'user-alice',
      'user-bob',
      'conversation-123',
    ];

    for (const plaintext of plaintextStrings) {
      const found = encrypted.ciphertext.includes(plaintext);
      console.log(`"${plaintext}": ${found ? '❌ FOUND (BAD!)' : '✅ NOT FOUND (GOOD!)'}`);
    }

    console.log('========================================\n');

    // Decrypt to verify it works
    const decrypted = await queue.drain();

    console.log('🔓 DECRYPTED MESSAGES:');
    console.log('========================================');
    decrypted.forEach((msg, i) => {
      console.log(`Message ${i + 1}:`);
      console.log(`  User: ${msg.userId}`);
      console.log(`  Conversation: ${msg.conversationId}`);
      console.log(`  Text: ${msg.plaintext}`);
      console.log(`  Key: ${msg.idempotencyKey}`);
      console.log('---');
    });
    console.log('========================================\n');

    // Visual comparison
    console.log('📊 BEFORE vs AFTER ENCRYPTION:');
    console.log('========================================');
    console.log('ORIGINAL (plaintext JSON):');
    console.log(JSON.stringify(messages, null, 2).substring(0, 200) + '...');
    console.log('\nENCRYPTED (what\'s in localStorage):');
    console.log(stored!.substring(0, 200) + '...');
    console.log('========================================\n');
  });

  it('should show tamper detection in action', async () => {
    const queue = new OfflineQueue();

    // Store a message
    await queue.enqueue({
      conversationId: 'conv-1',
      userId: 'user-1',
      plaintext: 'Original message',
      idempotencyKey: 'msg-1',
    });

    // Get encrypted data
    const stored = localStorage.getItem('offline:queue:encrypted')!;
    const encrypted = JSON.parse(stored);

    console.log('\n========================================');
    console.log('🔨 TAMPER DETECTION TEST:');
    console.log('========================================');

    // Tamper with ciphertext (flip some bits)
    const originalCiphertext = encrypted.ciphertext;
    const tamperedCiphertext = originalCiphertext.slice(0, -10) + 'TAMPERED!!';

    console.log('Original ciphertext (last 50 chars):', originalCiphertext.slice(-50));
    console.log('Tampered ciphertext (last 50 chars):', tamperedCiphertext.slice(-50));

    // Store tampered data
    localStorage.setItem(
      'offline:queue:encrypted',
      JSON.stringify({ ...encrypted, ciphertext: tamperedCiphertext })
    );

    // Try to load tampered data
    const tamperedQueue = new OfflineQueue();
    await tamperedQueue.initialize();

    console.log('\nResult after tampering:');
    console.log('Queue size:', tamperedQueue.size());
    console.log('Expected: 0 (tampered data discarded)');
    console.log('Status:', tamperedQueue.size() === 0 ? '✅ PASS' : '❌ FAIL');
    console.log('========================================\n');
  });

  it('should show different ciphertext for same plaintext', async () => {
    const queue1 = new OfflineQueue();
    const queue2 = new OfflineQueue();

    const message: QueuedMessage = {
      conversationId: 'conv-1',
      userId: 'user-1',
      plaintext: 'Same message encrypted twice',
      idempotencyKey: 'msg-1',
    };

    // Encrypt same message twice
    await queue1.enqueue(message);
    const encrypted1 = localStorage.getItem('offline:queue:encrypted')!;
    await queue1.clear();

    await queue2.enqueue({ ...message, idempotencyKey: 'msg-2' }); // Different key to avoid dedup
    const encrypted2 = localStorage.getItem('offline:queue:encrypted')!;

    console.log('\n========================================');
    console.log('🎲 RANDOM IV TEST (Same Plaintext):');
    console.log('========================================');
    console.log('Plaintext:', message.plaintext);
    console.log('\nFirst encryption:');
    console.log(encrypted1.substring(0, 150) + '...');
    console.log('\nSecond encryption:');
    console.log(encrypted2.substring(0, 150) + '...');
    console.log('\nAre they identical?', encrypted1 === encrypted2 ? '❌ NO (BAD!)' : '✅ NO (GOOD!)');
    console.log('========================================\n');
  });
});
