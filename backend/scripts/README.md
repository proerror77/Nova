# Backend Quality Assurance Scripts

這個目錄包含用於維護代碼質量、追蹤進度和防止常見錯誤的腳本工具。

## 📚 腳本概覽

### 1. `unwrap-progress.sh` - 追蹤 unwrap() 移除進度
**用途**: 每週追蹤 unwrap() 移除的進度

```bash
./scripts/unwrap-progress.sh
```

**輸出**:
- 總計 unwrap() 數量
- 按優先級分類 (P0/P1/P2+P3)
- 按服務分類
- 每週目標追蹤
- 最近修改的文件
- 下一步行動建議
- 歷史趨勢 (保存到 `unwrap-progress.csv`)

**使用時機**:
- 每週一檢查進度
- Sprint 計劃會議前
- 生成進度報告時

---

### 2. `unwrap-report.sh` - 生成詳細分析報告
**用途**: 生成按優先級分類的詳細 unwrap() 分析

```bash
./scripts/unwrap-report.sh
```

**輸出**: 創建 `unwrap-analysis.md` 包含:
- P0 (Critical): 主要入口點和關鍵路徑
- P1 (High): 網絡、I/O、認證操作
- P2 (Medium): 業務邏輯處理器
- P3 (Low): 工具函數和輔助方法
- 推薦的修復計劃
- 常見模式和修復示例

**使用時機**:
- 項目開始時建立基線
- 計劃下一個 sprint 的工作
- 向團隊展示優先級

---

### 3. `fix-unwrap-helper.sh` - 交互式修復助手
**用途**: 逐個檢查文件中的 unwrap() 並提供修復建議

```bash
./scripts/fix-unwrap-helper.sh src/main.rs
```

**功能**:
- 顯示每個 unwrap() 的上下文
- 根據模式提供修復建議
- 交互式逐個查看
- 總結和下一步指導

**使用時機**:
- 開始修復特定文件時
- 學習正確的錯誤處理模式
- 代碼審查準備

---

### 4. `create-github-issues.sh` - 生成 GitHub Issues
**用途**: 掃描代碼庫並為所有質量問題創建 GitHub issues

```bash
./scripts/create-github-issues.sh
```

**掃描內容**:
- TODO 註釋
- unwrap() 調用
- expect() 調用
- 硬編碼值
- 潛在的安全問題 (硬編碼密鑰等)

**輸出**:
- `github_issues.md` - 所有待創建的 issues
- 可選: 直接使用 GitHub CLI 創建 issues

**配置 GitHub CLI**:
```bash
# 1. 安裝 GitHub CLI
brew install gh  # macOS
# 或參考: https://cli.github.com/

# 2. 認證
gh auth login

# 3. 編輯腳本中的 REPO 變量
# 4. 取消註釋 create_issue 函數中的 gh 命令
```

**使用時機**:
- Sprint 計劃階段
- 創建技術債務 backlog
- 追蹤修復進度

---

### 5. `pre-commit.sh` - Git Pre-commit Hook
**用途**: 在提交前自動檢查代碼質量

**安裝**:
```bash
ln -sf ../../backend/scripts/pre-commit.sh .git/hooks/pre-commit
```

**檢查項目**:
- ❌ 阻塞: unwrap() 調用
- ❌ 阻塞: println!() 調試語句
- ❌ 阻塞: panic!() 調用
- ❌ 阻塞: 硬編碼密鑰
- ✅ 檢查: 代碼格式 (rustfmt)
- ✅ 檢查: Clippy lints

**繞過檢查** (僅緊急情況):
```bash
git commit --no-verify
```

**使用時機**:
- 安裝一次,自動運行
- 每次 `git commit` 時觸發

---

## 🎯 典型工作流程

### 新項目/服務開始
```bash
# 1. 生成基線報告
./scripts/unwrap-report.sh

# 2. 審查報告
cat unwrap-analysis.md

# 3. 創建 GitHub issues
./scripts/create-github-issues.sh
cat github_issues.md

# 4. 安裝 pre-commit hook
ln -sf ../../backend/scripts/pre-commit.sh .git/hooks/pre-commit
```

### 每週進度檢查
```bash
# 週一早上
./scripts/unwrap-progress.sh

# 檢查趨勢
cat unwrap-progress.csv

# 如果落後,重新生成優先級報告
./scripts/unwrap-report.sh
```

### 修復 unwrap()
```bash
# 1. 找到要修復的文件
./scripts/unwrap-progress.sh

# 2. 使用助手查看建議
./scripts/fix-unwrap-helper.sh path/to/file.rs

# 3. 編輯文件
vim path/to/file.rs

# 4. 測試
cargo test

# 5. 提交 (pre-commit hook 會自動檢查)
git add path/to/file.rs
git commit -m "fix: remove unwrap() calls in file.rs"
```

### Sprint 計劃
```bash
# 1. 生成最新報告
./scripts/unwrap-report.sh

# 2. 檢查進度
./scripts/unwrap-progress.sh

# 3. 創建下個 sprint 的 issues
./scripts/create-github-issues.sh

# 4. 在 sprint 計劃會議中審查 github_issues.md
```

---

## 📊 輸出文件

腳本會生成以下文件:

| 文件 | 生成者 | 用途 |
|------|--------|------|
| `unwrap-analysis.md` | unwrap-report.sh | 詳細的優先級分析 |
| `unwrap-progress.csv` | unwrap-progress.sh | 歷史趨勢追蹤 |
| `github_issues.md` | create-github-issues.sh | GitHub issues 預覽 |

這些文件應該被 git 忽略 (已添加到 .gitignore)。

---

## 🔧 自定義腳本

### 添加新的檢查模式

編輯 `pre-commit.sh`:
```bash
# 添加新檢查
echo "Checking for custom pattern..."
CUSTOM=$(echo "$STAGED_FILES" | xargs grep -n "YOUR_PATTERN" || true)

if [ -n "$CUSTOM" ]; then
    echo "Found custom pattern!"
    exit 1
fi
```

### 調整優先級閾值

編輯 `unwrap-progress.sh`:
```bash
# 修改警告閾值
if [ "$p1" -lt 10 ]; then  # 改為你的目標數字
    echo "✅ P1 (High): $p1 unwraps"
fi
```

---

## 🆘 故障排除

### Pre-commit Hook 不運行

```bash
# 檢查 hook 是否存在
ls -la .git/hooks/pre-commit

# 檢查權限
chmod +x .git/hooks/pre-commit

# 測試 hook
./backend/scripts/pre-commit.sh
```

### 腳本報告錯誤數字

```bash
# 清理 target 目錄
cargo clean

# 重新運行
./scripts/unwrap-progress.sh
```

### GitHub CLI 創建 issues 失敗

```bash
# 檢查認證
gh auth status

# 重新登錄
gh auth login

# 檢查倉庫訪問權限
gh repo view OWNER/REPO
```

---

## 📚 相關文檔

- [QUALITY_ASSURANCE.md](../QUALITY_ASSURANCE.md) - 完整的質量保證指南
- [UNWRAP_REMOVAL_PLAN.md](../UNWRAP_REMOVAL_PLAN.md) - 6週移除計劃
- [CLAUDE.md](../../CLAUDE.md) - 代碼審查標準

---

## 🎓 學習資源

### 錯誤處理最佳實踐
- [Rust Error Handling Book](https://doc.rust-lang.org/book/ch09-00-error-handling.html)
- [anyhow crate](https://docs.rs/anyhow/)
- [thiserror crate](https://docs.rs/thiserror/)

### Clippy Lints
- [Clippy Lint List](https://rust-lang.github.io/rust-clippy/)
- [unwrap_used lint](https://rust-lang.github.io/rust-clippy/master/index.html#unwrap_used)

---

## 💡 提示和技巧

### 快速找到最糟糕的文件
```bash
# 按 unwrap 數量排序文件
grep -r "\.unwrap()" --include="*.rs" backend | \
  cut -d: -f1 | sort | uniq -c | sort -rn | head -10
```

### 檢查特定服務
```bash
# 只檢查一個服務
cd messaging-service
grep -rn "\.unwrap()" src/ | grep -v test | wc -l
```

### 生成 PR 描述
```bash
# 修復前
before=$(grep -r "\.unwrap()" --include="*.rs" . | grep -v test | wc -l)

# ... 修復代碼 ...

# 修復後
after=$(grep -r "\.unwrap()" --include="*.rs" . | grep -v test | wc -l)

echo "Removed $((before - after)) unwrap() calls"
```

---

## 🤝 貢獻

改進這些腳本？

1. 測試你的改動
2. 更新此 README
3. 創建 PR 並標記 `tooling`
4. 在 PR 描述中包含使用示例

---

## 📞 獲取幫助

問題或建議？

- 在 #backend-quality Slack 頻道提問
- 創建 GitHub issue 標記 `tooling`
- 查看 [QUALITY_ASSURANCE.md](../QUALITY_ASSURANCE.md)
- 聯繫 @backend-leads