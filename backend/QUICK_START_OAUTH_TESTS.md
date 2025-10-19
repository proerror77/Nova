# OAuth Tests - Quick Start Guide

## TL;DR - Run Tests Now

```bash
cd /Users/proerror/Documents/nova/backend
./scripts/run_oauth_tests.sh
```

That's it! The script handles everything automatically.

---

## What Just Happened?

The script will:
1. ✅ Check Docker is running
2. ✅ Start PostgreSQL test database
3. ✅ Run database migrations
4. ✅ Set environment variables
5. ✅ Execute all 16 OAuth tests

---

## Manual Method (If Script Fails)

### Step 1: Start Database
```bash
docker run --name nova-test-db \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=nova_test \
  -p 5432:5432 \
  -d postgres:14
```

### Step 2: Run Tests
```bash
export DATABASE_URL="postgres://postgres:postgres@localhost:5432/nova_test"
cargo test --test oauth_test
```

---

## Test Overview

**16 Tests Total**:
- 6 Happy Path Tests (registration, login, linking)
- 5 Error Handling Tests (invalid codes, CSRF, network)
- 5 Business Logic Tests (unlinking, duplicates, validation)

**Test File**: `user-service/tests/oauth_test.rs` (705 lines)

---

## Common Commands

### Run All Tests
```bash
cargo test --test oauth_test
```

### Run Single Test
```bash
cargo test --test oauth_test test_oauth_google_new_user_registration
```

### Show Output
```bash
cargo test --test oauth_test -- --nocapture
```

### Generate Coverage
```bash
cargo tarpaulin --test oauth_test --out Html
```

---

## Expected Results

When tests run successfully, you'll see:
```
test result: ok. 16 passed; 0 failed; 0 ignored; 0 measured
```

When database is not ready:
```
Error: Failed to connect to test database
```
→ Solution: Run `./scripts/run_oauth_tests.sh`

---

## Test Categories

### 1. New User Registration (3 tests)
- Google OAuth registration
- Apple OAuth registration
- Facebook OAuth registration

### 2. Existing User Login (2 tests)
- Login with OAuth
- Token refresh

### 3. Account Linking (2 tests)
- Link multiple providers
- Login with any linked provider

### 4. Account Unlinking (2 tests)
- Unlink provider
- Prevent unlinking last auth method

### 5. Error Handling (5 tests)
- Invalid auth code
- State tampering (CSRF)
- Provider errors
- Network errors
- Security validation

### 6. Data Validation (2 tests)
- Token hashing
- Email validation

---

## File Locations

```
backend/
├── user-service/tests/
│   ├── oauth_test.rs              ← Main test file
│   ├── oauth_test_README.md       ← Full documentation
│   └── COVERAGE_SUMMARY.md        ← Coverage metrics
├── scripts/
│   └── run_oauth_tests.sh         ← Automated runner
└── OAUTH_TEST_DELIVERY.md         ← Delivery report
```

---

## Troubleshooting

### Docker Not Running
```
Error: Cannot connect to Docker daemon
```
**Fix**: Start Docker Desktop

### Database Connection Failed
```
Error: password authentication failed
```
**Fix**: Run `docker start nova-test-db` or use the script

### Tests Timeout
```
Error: test timed out
```
**Fix**: Run with `--test-threads=1`
```bash
cargo test --test oauth_test -- --test-threads=1
```

### Migration Errors
```
Error: no migrations found
```
**Fix**: Install sqlx-cli
```bash
cargo install sqlx-cli --no-default-features --features postgres
```

---

## Next Steps

1. ✅ Run tests: `./scripts/run_oauth_tests.sh`
2. ✅ Check coverage: `cargo tarpaulin --test oauth_test`
3. ✅ Read full docs: `user-service/tests/oauth_test_README.md`
4. ✅ Review delivery: `OAUTH_TEST_DELIVERY.md`

---

## Key Metrics

- **Total Lines**: 705
- **Test Count**: 16
- **Assertions**: 41+
- **Coverage Target**: 85%+
- **Compilation**: ✅ Zero errors

---

## Support

For detailed information:
- **Test Documentation**: `user-service/tests/oauth_test_README.md`
- **Coverage Analysis**: `user-service/tests/COVERAGE_SUMMARY.md`
- **Delivery Report**: `OAUTH_TEST_DELIVERY.md`

Task: **AUTH-3001** - Integration test: OAuth flows
Status: **✅ COMPLETE**
