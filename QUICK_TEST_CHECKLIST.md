# Quick Test Checklist - Social Data Consolidation

## ⚡ 5-Minute Smoke Test

### Test 1: Like a Post (30 seconds)
1. ❤️ Like any post from Home feed
2. 👤 Go to Profile → Liked tab
3. ✅ **Check**: Post appears at top

### Test 2: Save a Post (30 seconds)
1. 🔖 Save any post from Home feed
2. 👤 Go to Profile → Saved tab
3. ✅ **Check**: Post appears at top

### Test 3: Unlike a Post (30 seconds)
1. 💔 Unlike the post from Liked tab
2. 🔄 Pull to refresh
3. ✅ **Check**: Post disappears

### Test 4: Unsave a Post (30 seconds)
1. 🗑️ Unsave the post from Saved tab
2. 🔄 Pull to refresh
3. ✅ **Check**: Post disappears

### Test 5: Pagination (1 minute)
1. 📜 Scroll to bottom of Liked tab
2. ✅ **Check**: More posts load
3. 📜 Scroll to bottom of Saved tab
4. ✅ **Check**: More posts load

---

## 🚨 Red Flags to Watch For

| Symptom | Severity | Action |
|---------|----------|--------|
| Liked post doesn't appear in Liked tab | 🔴 Critical | Stop testing, report immediately |
| Saved post doesn't appear in Saved tab | 🔴 Critical | Stop testing, report immediately |
| App crashes when opening Liked/Saved tab | 🔴 Critical | Stop testing, report immediately |
| Posts disappear after refresh | 🟠 High | Document and continue testing |
| Pagination doesn't work | 🟡 Medium | Document and continue testing |
| Slow loading (>3 seconds) | 🟢 Low | Document and continue testing |

---

## 📱 Test Devices

Minimum test coverage:
- [ ] iPhone (iOS 17+)
- [ ] iPad (iOS 17+)
- [ ] Simulator (any)

---

## ✅ Pass Criteria

All 5 smoke tests must pass with no red flags.

---

## 📝 Report Template

**Tester**: [Your Name]
**Date**: [Date]
**Device**: [Device Model + iOS Version]
**Result**: ✅ Pass / ❌ Fail
**Issues**: [List any issues found]

---

**Estimated Time**: 5-10 minutes per device
