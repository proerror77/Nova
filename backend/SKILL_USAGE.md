# Issue Fix Workflow Skill 使用指南

## 🎯 快速開始

這個 skill 已經安裝在你的 Claude 配置中，可以自動化處理 GitHub Issue 的完整生命週期。

## 📝 基本用法

### 語法
```
使用 issue-fix-workflow skill 處理 issue #<number>
```

或者更具體：
```
使用 issue-fix-workflow skill 修復 issue #67
使用 issue-fix-workflow skill 處理 issue #68 的 Redis 部分
使用 issue-fix-workflow skill 修復 user-service 的所有 P2 unwraps
```

## 🚀 實際示例

### 示例 1: 修復完整的 P0 Issue

**命令**:
```
使用 issue-fix-workflow skill 修復 issue #67
```

**執行內容**:
1. ✅ 查詢 issue #67 詳情
2. ✅ 掃描所有 main.rs 和 lib.rs 文件
3. ✅ 修復 25 個 unwraps
4. ✅ 運行測試驗證
5. ✅ 提交代碼
6. ✅ 更新並關閉 issue

**預期輸出**:
```
✅ Issue #67 已完成！

統計：
- 修復了 25 個 unwraps
- 修改了 6 個文件
- 提交: fix(startup): remove unwrap() calls from service entry points
- Issue 已關閉

下一步: 可以處理 issue #68 了！
```

### 示例 2: 部分修復大型 Issue

**命令**:
```
使用 issue-fix-workflow skill 處理 issue #68 的 Redis 部分
```

**執行內容**:
1. ✅ 查詢 issue #68
2. ✅ 只掃描 Redis 相關文件
3. ✅ 修復 Redis 的 unwraps
4. ✅ 測試 Redis 連接處理
5. ✅ 提交代碼
6. ✅ 評論進度（不關閉 issue）

**預期輸出**:
```
✅ Redis 部分已完成！

統計：
- 修復了 12 個 Redis unwraps
- 修改了 4 個文件
- 提交: fix(redis): add proper error handling for Redis operations
- Issue #68 更新（還有 86 個 unwraps 待處理）

下一步: 繼續處理 PostgreSQL 部分
```

### 示例 3: 修復單個服務

**命令**:
```
使用 issue-fix-workflow skill 修復 user-service 的所有 unwraps
```

**執行內容**:
1. ✅ 掃描 user-service 目錄
2. ✅ 修復該服務的所有 unwraps
3. ✅ 運行 user-service 測試
4. ✅ 提交
5. ✅ 評論關聯的 issues

## 🎨 Skill 會做什麼

### 自動化步驟

1. **Issue 分析**
   ```
   📋 正在查詢 issue #67...

   Issue 詳情:
   - 標題: P0 Critical: Remove unwrap() from main.rs/lib.rs
   - 優先級: P0
   - 目標: 25 個 unwraps
   - 範圍: 服務入口點
   ```

2. **代碼掃描**
   ```
   🔍 掃描需要修復的文件...

   找到 6 個文件:
   ✓ backend/user-service/src/main.rs (5 unwraps)
   ✓ backend/feed-service/src/main.rs (4 unwraps)
   ✓ backend/messaging-service/src/main.rs (6 unwraps)
   ...
   ```

3. **智能修復**
   ```
   🔧 修復 user-service/src/main.rs...

   應用模式:
   - env::var().unwrap() → env::var().context("...")?
   - grpc_client().unwrap() → grpc_client().map_err(...)?

   完成! 5/5 unwraps 已修復 ✅
   ```

4. **測試驗證**
   ```
   🧪 運行測試...

   ✓ cargo test         (32 tests passed)
   ✓ cargo clippy       (no warnings)
   ✓ cargo fmt --check  (formatted)

   所有檢查通過 ✅
   ```

5. **Git 提交**
   ```
   📝 準備提交...

   提交信息:
   fix(startup): remove unwrap() calls from service entry points

   - Replaced 25 unwrap() with proper error handling
   - Used .context() for meaningful error messages
   - Added error propagation with ? operator

   Fixes #67

   ✓ 提交成功: d4f6a89
   ```

6. **Issue 更新**
   ```
   📨 更新 GitHub issue...

   ✓ 添加完成評論
   ✓ 關閉 issue #67

   Issue 狀態: ✅ Closed
   ```

## 🎯 使用場景

### 場景 1: 每週 Sprint 開始
```bash
# 週一早上，從 P0 開始
使用 issue-fix-workflow skill 修復 issue #67

# P0 完成後，開始 P1
使用 issue-fix-workflow skill 修復 issue #68
```

### 場景 2: 團隊分工
```bash
# Alice 負責 Redis
使用 issue-fix-workflow skill 處理 issue #68 的 Redis 部分

# Bob 負責 PostgreSQL
使用 issue-fix-workflow skill 處理 issue #68 的 PostgreSQL 部分
```

### 場景 3: 按服務修復
```bash
# 先修復 user-service
使用 issue-fix-workflow skill 修復 user-service 的所有 unwraps

# 再修復 feed-service
使用 issue-fix-workflow skill 修復 feed-service 的所有 unwraps
```

## 💡 進階用法

### 組合命令

**一次處理多個 issues**:
```
使用 issue-fix-workflow skill 按順序處理 issues #67, #68, #69
```

**指定修復策略**:
```
使用 issue-fix-workflow skill 修復 issue #68，每批處理 10 個 unwraps
```

**只掃描不修復**:
```
使用 issue-fix-workflow skill 分析 issue #69 的修復範圍
```

### 錯誤恢復

如果修復過程中出錯：
```
使用 issue-fix-workflow skill 繼續 issue #67 的修復（從中斷的地方開始）
```

## 🔧 配置選項

Skill 會遵循以下配置：

### 默認行為
- ✅ 自動掃描和修復
- ✅ 自動運行測試
- ✅ 自動提交（經過測試）
- ❌ 不自動推送（需要確認）
- ❌ 不自動關閉 issue（部分完成時）

### 可調整參數
```bash
# 在命令中指定
使用 issue-fix-workflow skill 修復 issue #67，批量大小為 5
使用 issue-fix-workflow skill 修復 issue #68，完成後自動關閉
```

## 📊 輸出報告

每次執行完成後，你會收到詳細報告：

```markdown
## 修復完成報告

**Issue**: #67 - P0 Critical
**狀態**: ✅ 完成
**耗時**: 45 分鐘

### 統計
- 掃描文件: 8
- 修改文件: 6
- 移除 unwraps: 25
- 測試修改: 3
- 提交數: 1

### 修改文件
1. user-service/src/main.rs (5 unwraps)
2. feed-service/src/main.rs (4 unwraps)
3. messaging-service/src/main.rs (6 unwraps)
...

### 測試結果
✅ 單元測試: 32/32 通過
✅ 集成測試: 5/5 通過
✅ Clippy: 無警告
✅ 格式: 正確

### Git
- Commit: d4f6a89
- Message: fix(startup): remove unwrap() calls

### GitHub
- Issue #67: ✅ 已關閉
- 評論: 已添加完成摘要

### 下一步
→ 可以開始 issue #68
→ 運行 ./scripts/unwrap-progress.sh 查看進度
```

## 🚨 常見問題

### Q: Skill 會自動推送嗎？
**A**: 不會。Skill 只會本地提交，推送需要手動確認：
```bash
git push origin <branch-name>
```

### Q: 如果測試失敗會怎樣？
**A**: Skill 會：
1. 停止修復
2. 報告失敗的測試
3. 提供恢復選項
4. 等待你的決定

### Q: 可以修復部分 issue 嗎？
**A**: 可以！只需指定範圍：
```
使用 issue-fix-workflow skill 處理 issue #68 的前 20 個 unwraps
```

### Q: 如何撤銷修復？
**A**: 如果還沒推送：
```bash
git reset --hard HEAD^
```

### Q: Skill 會修改哪些文件？
**A**: 只會修改包含 unwrap() 的 Rust 源文件（.rs），不會修改：
- 測試文件（除非明確要求）
- 配置文件
- 文檔
- 其他服務的文件

## 🎓 學習資源

在使用 skill 的過程中，你會學到：

1. **錯誤處理模式**
   - 觀察 skill 如何應用不同模式
   - 學習何時使用 `.context()` vs `.map_err()`
   - 理解錯誤傳播

2. **測試策略**
   - 看到哪些測試被運行
   - 學習如何驗證錯誤處理
   - 理解測試覆蓋的重要性

3. **Git 工作流**
   - 學習好的提交信息格式
   - 理解何時提交、何時分批
   - 掌握分支策略

## 🎉 成功案例

### 案例 1: 快速完成 P0
```
時間: 週一上午 10:00
命令: 使用 issue-fix-workflow skill 修復 issue #67
結果: 45 分鐘內完成所有 25 個 P0 unwraps
影響: 所有服務現在有優雅的啟動錯誤處理
```

### 案例 2: 團隊協作
```
場景: 3 人團隊並行處理 P1
Alice: Redis 部分 (12 unwraps) - 30 分鐘
Bob: PostgreSQL 部分 (18 unwraps) - 45 分鐘
Carol: Auth 部分 (15 unwraps) - 40 分鐘
結果: 2 小時內完成 45/98 P1 unwraps
```

### 案例 3: 漸進式改進
```
週一: issue #67 (P0) - 完成 ✅
週二: issue #68 Redis - 部分完成
週三: issue #68 PostgreSQL - 部分完成
週四: issue #68 Auth - 完成並關閉 ✅
週五: 回顧和文檔更新
```

## 📞 獲取幫助

如果遇到問題：

1. **查看文檔**
   - `backend/QUALITY_ASSURANCE.md` - 錯誤處理模式
   - `backend/UNWRAP_REMOVAL_PLAN.md` - 完整計劃
   - `~/.claude/skills/issue-fix-workflow.md` - Skill 完整文檔

2. **GitHub Issues**
   - 在相關 issue 下評論
   - 標記 `@backend-leads`

3. **Slack**
   - #backend-quality 頻道
   - 分享你的經驗

---

**Skill 位置**: `~/.claude/skills/issue-fix-workflow.md`
**創建日期**: 2025-11-11
**下次更新**: 根據使用反饋調整

**開始使用**:
```
使用 issue-fix-workflow skill 修復 issue #67
```

🚀 Let's make production code rock-solid!
