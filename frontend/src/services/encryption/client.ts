// Placeholder encryption client for Phase 7B frontend.
// Backend performs at-rest encryption; strict E2E client-side encryption is deferred.

export type EncryptedPayload = { ciphertext: string; nonce: string };

export async function encryptPlaintext(plaintext: string): Promise<EncryptedPayload> {
  // No-op placeholder: return base64 as "ciphertext" and random nonce
  const ciphertext = Buffer.from(plaintext, 'utf8').toString('base64');
  const nonce = Math.random().toString(36).slice(2);
  return { ciphertext, nonce };
}

export async function decryptToPlaintext(ciphertext: string): Promise<string> {
  try { return Buffer.from(ciphertext, 'base64').toString('utf8'); } catch { return ''; }
}

