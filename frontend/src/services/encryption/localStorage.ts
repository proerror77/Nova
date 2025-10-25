/**
 * LocalStorage encryption using AES-GCM via Web Crypto API.
 *
 * Design principles:
 * 1. Encrypt entire data blob, not individual items (simpler)
 * 2. Store IV/nonce with ciphertext (standard practice)
 * 3. Fail hard on decryption errors (don't return corrupted data)
 * 4. Key lives in memory only (cleared on logout)
 */

export interface EncryptedData {
  /** Base64-encoded ciphertext */
  ciphertext: string;
  /** Base64-encoded initialization vector */
  iv: string;
}

/**
 * Storage encryption service.
 * Handles AES-GCM encryption/decryption for localStorage.
 */
export class StorageEncryption {
  private key: CryptoKey | null = null;

  /**
   * Initialize encryption with a user-specific key.
   * Call this after login with a key derived from user credentials or session.
   *
   * @param keyMaterial - Raw key material (must be 256 bits / 32 bytes)
   */
  async initialize(keyMaterial: Uint8Array): Promise<void> {
    if (keyMaterial.length !== 32) {
      throw new Error('Key material must be exactly 32 bytes for AES-256');
    }

    this.key = await crypto.subtle.importKey(
      'raw',
      keyMaterial,
      { name: 'AES-GCM' },
      false, // Not extractable
      ['encrypt', 'decrypt']
    );
  }

  /**
   * Generate a random encryption key.
   * Use this for ephemeral sessions or when user credentials aren't available.
   */
  async generateKey(): Promise<void> {
    const keyMaterial = crypto.getRandomValues(new Uint8Array(32));
    await this.initialize(keyMaterial);
  }

  /**
   * Clear encryption key from memory.
   * Call this on logout to ensure no residual key remains.
   */
  destroy(): void {
    this.key = null;
  }

  /**
   * Check if encryption is ready.
   */
  isReady(): boolean {
    return this.key !== null;
  }

  /**
   * Encrypt data for storage.
   *
   * @param plaintext - Data to encrypt (will be JSON-stringified)
   * @returns Encrypted data with IV
   * @throws Error if encryption not initialized
   */
  async encrypt<T>(plaintext: T): Promise<EncryptedData> {
    if (!this.key) {
      throw new Error('StorageEncryption not initialized');
    }

    // Serialize data
    const plaintextStr = JSON.stringify(plaintext);
    const plaintextBytes = new TextEncoder().encode(plaintextStr);

    // Generate random IV (12 bytes recommended for AES-GCM)
    const iv = crypto.getRandomValues(new Uint8Array(12));

    // Encrypt
    const ciphertextBytes = await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv },
      this.key,
      plaintextBytes
    );

    // Convert to base64 for storage
    return {
      ciphertext: this.arrayBufferToBase64(ciphertextBytes),
      iv: this.arrayBufferToBase64(iv),
    };
  }

  /**
   * Decrypt data from storage.
   *
   * @param encrypted - Encrypted data with IV
   * @returns Decrypted and parsed data
   * @throws Error if decryption fails or data is corrupted
   */
  async decrypt<T>(encrypted: EncryptedData): Promise<T> {
    if (!this.key) {
      throw new Error('StorageEncryption not initialized');
    }

    try {
      // Decode base64
      const ciphertextBytes = this.base64ToArrayBuffer(encrypted.ciphertext);
      const iv = this.base64ToArrayBuffer(encrypted.iv);

      // Decrypt
      const plaintextBytes = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv },
        this.key,
        ciphertextBytes
      );

      // Parse JSON
      const plaintextStr = new TextDecoder().decode(plaintextBytes);
      return JSON.parse(plaintextStr) as T;
    } catch (error) {
      // Fail hard on decryption errors (data corrupted or tampered)
      throw new Error(
        `Decryption failed: ${error instanceof Error ? error.message : 'unknown error'}`
      );
    }
  }

  // Helper: ArrayBuffer to Base64
  private arrayBufferToBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary);
  }

  // Helper: Base64 to ArrayBuffer
  private base64ToArrayBuffer(base64: string): ArrayBuffer {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
      bytes[i] = binary.charCodeAt(i);
    }
    return bytes.buffer;
  }
}

/**
 * Global singleton instance.
 * Initialize once per session, destroy on logout.
 */
export const storageEncryption = new StorageEncryption();
