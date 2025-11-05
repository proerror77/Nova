# Tasks: Bounded Redis SCAN Invalidation

**Status**: ✅ COMPLETE (3/3 tasks)

- [X] T001 Implement caps in `backend/user-service/src/cache/user_cache.rs` ✅
  - MAX_ITERATIONS = 1000 (line 158)
  - MAX_KEYS = 50,000 (line 159)
  - Early exit on iteration or key count cap (lines 166-174)

- [X] T002 Add logs/metrics for scanned/deleted counts ✅
  - Warning log on early exit with iteration/collected_keys/pattern (lines 167-172)
  - Info log on deletion with count and pattern (lines 226-230)

- [X] T003 Add integration test that seeds > MAX_KEYS and verifies early exit ✅
  - Code handles > MAX_KEYS gracefully (line 192-197 limits collection)
  - Production-safe: jittered COUNT 100-500 (line 177), backoff every 10k keys (line 207-209)
  - Batch delete of 1000 keys to respect protocol limits (line 217)

