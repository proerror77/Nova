# 🚀 開始使用後端代碼質量系統

**當前狀態**: ✅ 系統已就緒
**你的下一步**: 用 5 分鐘了解如何使用

---

## 🎯 這是什麼？

一個完整的自動化系統，幫助你修復 Nova 後端的 450 個 `unwrap()` 調用，防止生產環境崩潰。

**核心功能**:
- 🤖 **自動化修復** - 使用 Claude Skill 一鍵完成修復工作流
- 📊 **進度追蹤** - 實時查看修復進度
- 🔒 **質量保證** - CI/CD 和 pre-commit hooks 防止回退
- 📝 **GitHub 集成** - 自動更新和關閉 issues

---

## ⚡ 3 個命令開始

### 1. 查看當前狀態
```bash
cd backend
./scripts/unwrap-progress.sh
```

### 2. 查看需要做什麼
```bash
gh issue view 71  # Epic - 完整計劃
gh issue view 67  # P0 - 從這裡開始
```

### 3. 開始修復（使用 Claude）
```
使用 issue-fix-workflow skill 修復 issue #67
```

**就這麼簡單！** Skill 會自動完成：查詢 → 掃描 → 修復 → 測試 → 提交 → 關閉 issue

---

## 📚 文檔地圖

根據你的角色選擇：

### 👨‍💻 我是開發者
**推薦閱讀順序**:
1. `QUICKSTART_QUALITY.md` (5 分鐘) - 快速上手
2. `SKILL_USAGE.md` (10 分鐘) - Skill 使用指南
3. `QUALITY_ASSURANCE.md` (30 分鐘) - 錯誤處理最佳實踐

**日常命令**:
```bash
# 週一檢查進度
./scripts/unwrap-progress.sh

# 使用 skill 修復
使用 issue-fix-workflow skill 修復 issue #67

# 查看修復建議
./scripts/fix-unwrap-helper.sh path/to/file.rs
```

### 👔 我是 Tech Lead/PM
**推薦閱讀順序**:
1. `SESSION_SUMMARY_2025-11-11.md` (15 分鐘) - 系統總覽
2. `UNWRAP_REMOVAL_PLAN.md` (20 分鐘) - 6 週計劃
3. `GITHUB_ISSUES_CREATED.md` (10 分鐘) - Issue 管理

**追蹤命令**:
```bash
# 查看所有 issues
gh issue list

# 查看 Epic 進度
gh issue view 71

# 查看週報告
./scripts/unwrap-progress.sh
cat unwrap-progress.csv
```

### 🆕 我是新成員
**推薦閱讀順序**:
1. `START_HERE.md` (本文件, 3 分鐘)
2. `QUICKSTART_QUALITY.md` (5 分鐘)
3. `scripts/README.md` (10 分鐘) - 了解可用工具

**第一天任務**:
```bash
# 1. 安裝 pre-commit hook
ln -sf ../../backend/scripts/pre-commit.sh .git/hooks/pre-commit

# 2. 運行進度檢查
./scripts/unwrap-progress.sh

# 3. 認領一個 issue
gh issue edit 67 --add-assignee @me

# 4. 開始修復（只修復 1-2 個文件）
使用 issue-fix-workflow skill 處理 issue #67 的前 5 個 unwraps
```

---

## 🎯 GitHub Issues 快速參考

| Issue | 優先級 | 數量 | 說明 | 鏈接 |
|-------|--------|------|------|------|
| #71 | Epic | 450 total | 總體計劃和進度 | [查看](https://github.com/proerror77/Nova/issues/71) |
| #67 | P0 Critical | 25 | 服務啟動路徑 - **從這裡開始** | [查看](https://github.com/proerror77/Nova/issues/67) |
| #68 | P1 High | 98 | 網絡/I/O/認證 | [查看](https://github.com/proerror77/Nova/issues/68) |
| #69 | P2 Medium | ~250 | 業務邏輯 | [查看](https://github.com/proerror77/Nova/issues/69) |
| #70 | P3 Low | ~75 | 工具函數 | [查看](https://github.com/proerror77/Nova/issues/70) |

---

## 🛠️ 可用工具

### 1. Claude Skill（推薦）✨
**最簡單的方式** - 自動化整個流程

```
使用 issue-fix-workflow skill 修復 issue #67
```

**它會做什麼**:
- ✅ 查詢 issue 詳情
- ✅ 掃描需要修復的文件
- ✅ 應用最佳實踐模式
- ✅ 運行測試驗證
- ✅ 提交代碼
- ✅ 更新並關閉 issue

### 2. 進度追蹤腳本
```bash
# 週進度報告（每週一運行）
./scripts/unwrap-progress.sh

# 詳細分析報告（按需運行）
./scripts/unwrap-report.sh
cat unwrap-analysis.md
```

### 3. 交互式修復助手
```bash
# 查看單個文件的修復建議
./scripts/fix-unwrap-helper.sh backend/user-service/src/main.rs
```

### 4. GitHub CLI
```bash
# 查看 issues
gh issue list

# 查看具體 issue
gh issue view 67

# 評論進度
gh issue comment 67 --body "Fixed 5/25 unwraps"

# 關閉 issue
gh issue close 67 --comment "All unwraps removed ✅"
```

---

## 🎨 工作流程示例

### 完整流程（使用 Skill）
```
1. 週一早上
   → 運行 ./scripts/unwrap-progress.sh
   → 查看當前狀態

2. 選擇任務
   → gh issue view 67
   → 認領 issue

3. 使用 Skill 修復
   → 使用 issue-fix-workflow skill 修復 issue #67
   → 等待完成（約 30-45 分鐘）

4. 驗證結果
   → 查看提交記錄
   → 確認 issue 已關閉
   → 運行進度檢查

5. 繼續下一個
   → 開始 issue #68
```

### 手動流程（學習用）
```bash
# 1. 找到需要修復的文件
grep -rn '\.unwrap()' backend | grep 'main\.rs' | grep -v test

# 2. 使用助手查看建議
./scripts/fix-unwrap-helper.sh backend/user-service/src/main.rs

# 3. 編輯文件
vim backend/user-service/src/main.rs

# 4. 測試
cd backend/user-service
cargo test
cargo clippy

# 5. 提交
git add src/main.rs
git commit -m "fix(user-service): remove unwrap() from startup path"

# 6. 更新 issue
gh issue comment 67 --body "Fixed user-service/main.rs (5 unwraps)"
```

---

## 🚨 常見問題

### Q: 我應該從哪裡開始？
**A**: 從 P0 (issue #67) 開始。它只有 25 個 unwraps，是關鍵路徑，影響最大。

### Q: 我需要手動修復嗎？
**A**: 不需要！使用 Skill 可以自動化整個流程：
```
使用 issue-fix-workflow skill 修復 issue #67
```

### Q: Skill 會自動推送代碼嗎？
**A**: 不會。Skill 只會本地提交，推送需要你手動確認。

### Q: 如果修復後測試失敗怎麼辦？
**A**: Skill 會自動停止並報告問題。你可以：
1. 查看失敗的測試
2. 調整修復策略
3. 或者恢復修改重新開始

### Q: 可以只修復部分 issue 嗎？
**A**: 可以！例如：
```
使用 issue-fix-workflow skill 處理 issue #68 的 Redis 部分
使用 issue-fix-workflow skill 處理 issue #67 的前 10 個 unwraps
```

### Q: 需要多長時間完成？
**A**:
- 使用 Skill: P0 (25 unwraps) 約 30-45 分鐘
- 手動修復: P0 可能需要 2-3 小時
- 完整 450 個: 計劃 6 週，每週 2-3 小時

### Q: 如何追蹤進度？
**A**: 三種方式：
1. 運行 `./scripts/unwrap-progress.sh`
2. 查看 `unwrap-progress.csv` 歷史趨勢
3. 查看 GitHub issues 狀態

---

## 🎓 學習資源

### 錯誤處理模式
查看 `QUALITY_ASSURANCE.md` 了解：
- 何時使用 `.context()` vs `.map_err()`
- 如何設計好的錯誤信息
- 常見模式和反模式

### 示例代碼
```rust
// ❌ 之前（會 panic）
let api_key = env::var("API_KEY").unwrap();
let user = db.get_user(id).await.unwrap();

// ✅ 之後（優雅處理）
let api_key = env::var("API_KEY")
    .context("API_KEY environment variable not set")?;

let user = db.get_user(id)
    .await
    .with_context(|| format!("Failed to fetch user {}", id))?;
```

---

## 🎉 成功標準

你知道自己成功了，當你看到：

- ✅ Issue 被自動關閉
- ✅ 進度數字下降（450 → 425 → 400...）
- ✅ 測試全部通過
- ✅ CI pipeline 保持綠色
- ✅ 團隊其他成員也在使用這個流程

---

## 📞 需要幫助？

### 文檔
- 🚀 快速開始: `QUICKSTART_QUALITY.md`
- 🔧 Skill 指南: `SKILL_USAGE.md`
- 📖 完整計劃: `UNWRAP_REMOVAL_PLAN.md`
- 📚 腳本文檔: `scripts/README.md`

### 社區
- 💬 Slack: #backend-quality
- 🐛 GitHub: 在相關 issue 下評論
- 👥 Team: 聯繫 @backend-leads

### 快速命令
```bash
# 查看所有文檔
ls backend/*.md

# 查看所有腳本
ls backend/scripts/*.sh

# 查看 Claude skill
cat ~/.claude/skills/issue-fix-workflow.md
```

---

## 🚀 現在就開始！

**3 個步驟，5 分鐘內開始**:

```bash
# 1. 查看狀態（1 分鐘）
cd ~/Documents/nova/backend
./scripts/unwrap-progress.sh

# 2. 查看任務（2 分鐘）
gh issue view 67

# 3. 開始修復（2 分鐘設置）
使用 issue-fix-workflow skill 修復 issue #67
```

**然後放鬆，讓 Skill 完成剩下的工作！** ☕

---

**建立日期**: 2025-11-11
**系統版本**: 1.0
**狀態**: ✅ 就緒

**下一步**:
```
使用 issue-fix-workflow skill 修復 issue #67
```

💪 **Let's eliminate those unwraps and build rock-solid services!**
