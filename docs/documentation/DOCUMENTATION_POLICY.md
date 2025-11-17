# Nova 文檔政策 / Documentation Policy

## 📋 根目錄文件政策 / Root Directory Policy

### ✅ 允許的根目錄文件 / Allowed Root Files

根目錄**只能**包含以下 GitHub 標準文件：

- `README.md` - 項目主文檔
- `LICENSE.md` - 許可證文件
- `CONTRIBUTING.md` - 貢獻指南
- `CODE_OF_CONDUCT.md` - 行為準則
- `SECURITY.md` - 安全政策
- `CHANGELOG.md` - 變更日誌

### ❌ 禁止的根目錄文件 / Prohibited Root Files

**嚴格禁止**在根目錄生成以下類型的文件：

- ❌ 臨時報告文件（`*_REPORT.md`, `*_SUMMARY.md`）
- ❌ 執行總結文件（`EXECUTION_*.md`, `IMPLEMENTATION_*.md`）
- ❌ 階段文檔（`PHASE_*.md`, `P0_*.md`, `P1_*.md`）
- ❌ 審計報告（`*_AUDIT_*.md`, `*_REVIEW_*.md`）
- ❌ 優化報告（`OPTIMIZATION_*.md`, `PERFORMANCE_*.md`）
- ❌ 部署指南（`DEPLOYMENT_*.md`, `QUICKSTART.md`）
- ❌ 開發指南（`SETUP.md`, `*_GUIDE.md`）
- ❌ 任何其他臨時或項目特定的 markdown 文件

---

## 📁 正確的文檔組織結構 / Proper Documentation Structure

所有項目文檔應該放在 `docs/` 目錄下：

```
docs/
├── deployment/          # 部署相關文檔
│   ├── QUICKSTART.md
│   ├── DEPLOYMENT.md
│   ├── AWS-SECRETS-SETUP.md
│   └── CI_CD_QUICK_REFERENCE.md
│
├── development/         # 開發相關文檔
│   ├── SETUP.md
│   ├── CODE_REVIEW_CHECKLIST.md
│   └── TESTING_GUIDE.md
│
├── architecture/        # 架構文檔
│   ├── MICROSERVICES.md
│   ├── DATABASE.md
│   └── API_DESIGN.md
│
├── guides/             # 各類指南
│   ├── CONTRIBUTING_GUIDE.md
│   ├── SECURITY_GUIDE.md
│   └── MONITORING_GUIDE.md
│
├── reports/            # 臨時報告（定期清理）
│   ├── 2025-11/
│   │   ├── security_audit_2025_11_10.md
│   │   └── performance_review_2025_11_15.md
│   └── README.md       # 說明這些是臨時報告
│
└── START_HERE.md       # 文檔索引頁
```

---

## 🤖 AI 助手指南 / AI Assistant Guidelines

### 給 Claude Code 和其他 AI 工具的指示：

**CRITICAL RULE**:

1. **永遠不要在根目錄（`/`）創建 markdown 文件**
   - 除非是更新 `README.md` 或創建 GitHub 標準文件

2. **所有文檔必須放在 `docs/` 目錄下**
   - 部署文檔 → `docs/deployment/`
   - 開發文檔 → `docs/development/`
   - 架構文檔 → `docs/architecture/`
   - 臨時報告 → `docs/reports/YYYY-MM/`

3. **臨時報告必須包含日期**
   - 格式：`docs/reports/YYYY-MM/report_name_YYYY_MM_DD.md`
   - 定期清理（每季度一次）

4. **創建文檔前先檢查**
   ```bash
   # 確認當前目錄
   pwd
   # 如果在根目錄，切換到 docs/
   cd docs/
   ```

---

## 🔒 .gitignore 配置 / .gitignore Configuration

根目錄的 `.gitignore` 已配置為：

```gitignore
# Markdown files in root directory (除了 GitHub 必需的文件)
/*.md
!README.md
!LICENSE.md
!CONTRIBUTING.md
!CODE_OF_CONDUCT.md
!SECURITY.md
!CHANGELOG.md
```

這確保了即使誤生成文件也不會被提交到 git。

---

## 📝 文檔命名規範 / Documentation Naming Convention

### 永久文檔（Permanent Docs）
- 使用大寫蛇形命名：`DEPLOYMENT_GUIDE.md`
- 放在相應的 `docs/` 子目錄

### 臨時報告（Temporary Reports）
- 包含日期：`security_audit_2025_11_10.md`
- 放在 `docs/reports/YYYY-MM/`
- 每季度審查並歸檔或刪除

### 索引文檔（Index Docs）
- 每個子目錄應有 `README.md` 作為索引
- 列出該目錄的所有文檔及其用途

---

## 🧹 定期清理 / Regular Cleanup

### 每月清理任務
- [ ] 檢查 `docs/reports/` 下的臨時報告
- [ ] 刪除或歸檔 3 個月前的報告
- [ ] 更新各目錄的 `README.md` 索引

### 每季度清理任務
- [ ] 審查所有文檔的相關性
- [ ] 合併重複或過時的文檔
- [ ] 更新 `docs/START_HERE.md` 索引

---

## 🚨 違規處理 / Violation Handling

如果發現根目錄出現未授權的 markdown 文件：

1. **立即移動到正確位置**
   ```bash
   mv /path/to/root/UNAUTHORIZED.md docs/appropriate-subdirectory/
   ```

2. **更新相關引用**
   - 檢查是否有其他文檔引用了該文件
   - 更新所有引用路徑

3. **檢查 .gitignore**
   - 確認 .gitignore 配置正確
   - 該文件不應被提交

---

## 📞 聯繫方式 / Contact

如有疑問或建議，請：
- 創建 GitHub Issue
- 標記為 `documentation` label
- 或聯繫項目維護者

---

**最後更新**: 2025-11-11
**維護者**: Nova Team
**版本**: 1.0.0
