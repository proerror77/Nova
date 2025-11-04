# Implementation Plan: Request Input Validation

**Branch**: `[005-p1-input-validation]` | **Date**: 2025-11-04 | **Spec**: specs/005-p1-input-validation/spec.md

## Summary

Add DTO validation via `validator` and password strength via `zxcvbn` at handler boundaries before any hashing.

## Steps

1) Add validation DTOs in `backend/auth-service/src/dto/` (new): `RegisterRequest`, `LoginRequest`
2) Use `#[derive(Validate)]` with `#[validate(email)]` for email
3) In register handler, run `zxcvbn` on raw password; reject if score < 3
4) Only then hash with Argon2id and persist
5) Add unit + integration tests

