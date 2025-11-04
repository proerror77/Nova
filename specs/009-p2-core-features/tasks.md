# Tasks: Core Feature Build-Out

## Auth (Register/Login)

- [ ] T100 Define DTOs and validators in `backend/auth-service/src/dto/`
- [ ] T101 Implement register route: validate → zxcvbn → Argon2id → persist
- [ ] T102 Implement login route: verify → issue access/refresh JWTs
- [ ] T103 Add tests: register/login/refresh/invalid creds

## Content (CreateComment)

- [ ] T200 Define `CreateComment` proto and server handler in `backend/content-service/src/`
- [ ] T201 Persist comment; validate length/links; rate limit
- [ ] T202 Emit feed invalidation event
- [ ] T203 Tests: create/fetch/invalidate

## Outbox Consumer

- [ ] T300 Add outbox table + migrations where needed
- [ ] T301 Implement consumer with retries/backoff + DLQ
- [ ] T302 Tests: retry/poison flows

## Circuit Breaker

- [ ] T400 Add middleware; instrument with metrics
- [ ] T401 Add fallbacks for critical paths (Postgres or cache)
- [ ] T402 Tests: failure injection

