# Server-Managed Conversation Encryption (Not E2E)

> **Important:** The current implementation provides *server-managed* encryption-at-rest. All
> conversation keys are derived from a master key that lives on the messaging-service. This means the
> service can decrypt any payload. The previous name “Strict E2E” was inaccurate and has been
> deprecated.

## What the Server Currently Does

- For every conversation we derive a 32-byte symmetric key using HKDF-SHA256 with the master key as
  the input key material and the conversation UUID as context.
- Messages are encrypted with XSalsa20-Poly1305 (`secretbox`) before being persisted or fanned out.
- Nonces are generated per message and returned alongside the ciphertext.

This model protects data at rest (e.g. if Redis snapshots or the database leak) but **does not** stop
the server—or anyone with access to the master key—from decrypting messages.

## API Response Contract

All encrypted payloads follow the same wire format, whether delivered via REST or WebSocket:

- `encrypted` – `true` when the message body is encrypted.
- `encrypted_payload` – Base64-encoded ciphertext produced by secretbox.
- `nonce` – Base64-encoded 24-byte nonce used with the cipher above.
- `content` – Intentionally left empty to avoid leaking plaintext.

Clients should cache the derived key locally and decrypt using XSalsa20-Poly1305. Because the server
controls key derivation, key rotation must be coordinated through the API (future work).

## Roadmap to Real End-to-End Encryption

Delivering genuine E2EE requires a larger redesign:

1. Client-held identity keys and per-device key management (Signal/Olm style double ratchet).
2. Server no longer derives conversation keys; instead it stores encrypted envelopes only.
3. Backwards-compatible migration plan for existing conversations and push notifications.

Until the above is implemented, the product should describe this feature as “server-side encrypted
conversations” rather than end-to-end encryption.
