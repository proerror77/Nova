# Chat E2E Setup (user-service)

This app uses client-side NaCl (TweetNacl) to encrypt messages for user-service endpoints.

## 1) Install Swift Package

- Xcode → File → Add Package Dependencies…
- URL: `https://github.com/bitmark-inc/tweetnacl-swiftwrap`
- Add to the iOS target

## 2) Run backend locally

```
docker-compose up -d postgres redis kafka clickhouse user-service messaging-service
```

- user-service: http://localhost:8080
- messaging-service (WS): ws://localhost:8085

- For friction‑free dev, enable auto email verification for new accounts:
  - In `docker-compose.yml` under `user-service.environment` ensure `DEV_AUTO_VERIFY_EMAIL: "true"`
  - Then restart: `docker compose up -d --build user-service`

## 3) Configure iOS base URL

`ios/NovaSocialApp/Network/Utils/AppConfig.swift` should point development to your gateway or `http://localhost:8080`.

## 4) What was added

- Crypto
  - `Services/Security/NaClCrypto.swift`: NaCl wrapper (TweetNacl)
  - `Services/Security/CryptoKeyStore.swift`: Keypair in Keychain
- API models
  - `Network/Models/MessagingModels.swift`
- Repository
  - `Network/Repositories/MessagingRepository.swift`: public key upload/fetch, send/get messages
- UI (minimal)
  - `ViewModels/Chat/ChatViewModel.swift`
  - `Views/Chat/ChatView.swift`

## 5) Backend endpoints added (user-service)

- `PUT /api/v1/users/me/public-key` (JWT required)
- `GET /api/v1/users/{id}/public-key` (public)

## 6) Usage (example)

```swift
// Present ChatView when you know conversation + peer user
let convoId: UUID = /* from server */
let peerId: UUID = /* the other member */
NavigationLink("Open Chat") {
  ChatView(vm: ChatViewModel(conversationId: convoId, peerUserId: peerId))
}
```

The ViewModel will:
- generate + store your keypair (once)
- upload your public key
- fetch peer public key
- pull history and decrypt
- encrypt + send new messages

## 7) Redis connection (email verification tokens)

- By default, user-service stores email verification tokens in Redis (`REDIS_URL`).
- If you want to script the verification step (without clicking emails), use the same Redis instance/password as user-service:
  - Check `docker-compose.yml` → `user-service.environment.REDIS_URL` (default `redis://:redis123@redis:6379/0`)
  - From host, port is forwarded to `localhost:6379`; password is `redis123` (unless you changed `REDIS_PASSWORD`).
  - The token key pattern is `verify_email:<user_id>:<email>`.

For development, prefer enabling `DEV_AUTO_VERIFY_EMAIL=true` to skip the token flow entirely.

## 8) One‑click smoke test

Use `scripts/smoke_chat.sh` to run an end‑to‑end flow:

```
bash scripts/smoke_chat.sh
```

The script will read `.env`/`.env.example` (e.g. `REDIS_URL`) and can be configured via:

- `USER_SERVICE_BASE` (default `http://localhost:8080`)
- `WS_BASE` (default `ws://localhost:8085`)
- `REDIS_HOST`/`REDIS_PORT`/`REDIS_PASS` (auto-derived from `REDIS_URL` when present)

Notes:
- If `DEV_AUTO_VERIFY_EMAIL` is enabled (recommended), the script logs in directly.
- Otherwise it will fall back to retrieving verification tokens from Redis and POST `/api/v1/auth/verify-email`.
