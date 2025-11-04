# Feature Specification: Request Input Validation (Email/Password)

**Feature Branch**: `[005-p1-input-validation]`  
**Created**: 2025-11-04  
**Status**: Draft  
**Input**: User description: "Add email format validation and pre-hash password strength checks at handler boundary"

## Verification (code audit) — 2025-11-05

- auth-service: handlers validate inputs first, then hash with Argon2id; password strength checked (composition + zxcvbn score>=3) before hashing.
  - Handler validation: `backend/auth-service/src/handlers/auth.rs:70-96` (register) and `backend/auth-service/src/models/user.rs:33-55` (DTO validations).
  - Password checks: `backend/auth-service/src/security/password.rs:1-40` (pre-hash validation + zxcvbn), tests present.
- user-service: register/login are delegated to auth-service; local validators exist for other inputs, but no password endpoints here.

Status: Implemented in auth-service; ensure login persistence/verification is completed when DB layer is wired.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Validate email format (Priority: P1)

As a user, I get immediate, clear feedback if my email is invalid.

**Independent Test**: POST register with invalid emails returns 400 with error code; valid emails proceed.

**Acceptance Scenarios**:
1. Given `userexample.com`, When registering, Then response 400 `invalid_email_format`.
2. Given `user+tag@example.com`, Then request passes validation step.

---

### User Story 2 - Enforce password strength pre-hash (Priority: P1)

As a platform, we reject weak passwords without wasting CPU on hashing them.

**Independent Test**: Submit `password123` gets 400; strong passphrase accepted; hash only computed after pass.

**Acceptance Scenarios**:
1. Given `Password1!` may still be weak by zxcvbn score<3, Then 400 with `weak_password`.
2. Given 14+ char random passphrase, Then proceed to hash with Argon2id.

### Edge Cases

- Trim leading/trailing whitespace.
- Upper/lower case preserved where appropriate.

## Requirements *(mandatory)*

### Functional Requirements

- FR-001: Introduce request DTOs annotated with `validator` crate for email format.
- FR-002: Add `zxcvbn` check before hashing; configurable min score (default 3).
- FR-003: Centralize validation in handlers for auth-service (register/login once implemented) and any user-service endpoints accepting emails/passwords.
- FR-004: Unit tests for DTO validation; integration tests for handler behavior.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- SC-001: 100% of handlers that accept email/password perform validation first.
- SC-002: CPU saved: hashing only runs on inputs that pass strength checks.
