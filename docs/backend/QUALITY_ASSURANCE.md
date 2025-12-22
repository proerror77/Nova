# Code Quality Assurance

本文檔說明如何使用自動化工具來維護代碼質量和防止常見錯誤。

## 🎯 目標

1. **零生產環境崩潰** - 消除所有 `unwrap()` 和 `panic!()`
2. **清晰的錯誤處理** - 使用 `context()` 提供有意義的錯誤信息
3. **安全第一** - 防止硬編碼機密信息
4. **可追蹤性** - 將所有 TODO 轉換為 GitHub issues

## 🚀 快速開始

### 1. 安裝 Pre-commit Hook

在項目根目錄執行：

```bash
# 安裝 pre-commit hook
ln -sf ../../backend/scripts/pre-commit.sh .git/hooks/pre-commit

# 測試 hook
./backend/scripts/pre-commit.sh
```

### 2. 生成 GitHub Issues

掃描代碼庫並生成 GitHub issues：

```bash
cd backend
./scripts/create_github_issues.sh

# 查看生成的 issues
cat github_issues.md
```

配置 GitHub CLI 後可以自動創建 issues：

```bash
# 安裝 GitHub CLI
brew install gh  # macOS
# 或參考: https://cli.github.com/

# 認證
gh auth login

# 修改腳本中的 REPO 變量
# 然後取消註釋 create_issue 函數中的 gh 命令
```

## 📋 CI/CD 檢查

所有 PR 都會自動運行以下檢查：

### 阻塞性檢查（必須通過）

1. **unwrap() 檢查** - 生產代碼中不允許 `unwrap()`
2. **hardcoded secrets** - 不允許硬編碼機密信息
3. **panic!() 檢查** - 不允許使用 `panic!()`
4. **Clippy 檢查** - 所有 lints 必須通過

### 警告性檢查（不阻塞）

1. **TODO 檢查** - 顯示 TODO 數量
2. **expect() 檢查** - 提醒使用更好的錯誤消息
3. **println!() 檢查** - 建議使用 tracing 宏

## 🛠️ 本地開發工具

### Rust Clippy 配置

在 `Cargo.toml` 或命令行使用：

```bash
cargo clippy -- \
  -W clippy::unwrap_used \
  -W clippy::expect_used \
  -W clippy::panic \
  -W clippy::todo \
  -D warnings
```

### 自動修復

```bash
# 自動格式化
cargo fmt

# 自動修復 Clippy 建議
cargo clippy --fix

# 修復所有服務
./scripts/fix-all-services.sh
```

## 🔍 錯誤處理最佳實踐

### ❌ 不好的做法

```rust
// 會導致 panic
let config = load_config().unwrap();

// 錯誤信息不明確
let user = db.get_user(id).expect("failed");

// 硬編碼機密
let api_key = "sk-1234567890";
```

### ✅ 好的做法

```rust
// 使用 context 提供清晰的錯誤
use anyhow::Context;

let config = load_config()
    .context("Failed to load config from /etc/app/config.toml")?;

// 返回錯誤而不是 panic
let user = db.get_user(id)
    .await
    .with_context(|| format!("Failed to fetch user {}", id))?;

// 使用環境變量
let api_key = env::var("API_KEY")
    .context("API_KEY environment variable not set")?;
```

### 錯誤類型選擇

```rust
// 1. 庫代碼 - 使用自定義錯誤類型
pub enum ServiceError {
    NotFound(UserId),
    InvalidInput(String),
    DatabaseError(String),
}

// 2. 應用代碼 - 使用 anyhow
use anyhow::{Result, Context};

pub async fn create_user(data: UserData) -> Result<User> {
    validate_email(&data.email)
        .context("Email validation failed")?;

    db.insert_user(data)
        .await
        .context("Failed to insert user into database")?
}

// 3. 測試代碼 - 可以使用 unwrap()
#[cfg(test)]
mod tests {
    #[test]
    fn test_something() {
        let result = function_under_test().unwrap();  // OK in tests
        assert_eq!(result, expected);
    }
}
```

## 📊 測試覆蓋率

運行測試並檢查覆蓋率：

```bash
# 運行所有測試
cargo test

# 帶覆蓋率報告 (需要 tarpaulin)
cargo install cargo-tarpaulin
cargo tarpaulin --out Html

# 查看報告
open tarpaulin-report.html
```

## 🔐 安全檢查

### 機密管理

所有機密信息必須通過以下方式管理：

1. **環境變量** - 用於本地開發
   ```bash
   export DATABASE_URL="postgresql://..."
   export JWT_PRIVATE_KEY="$(cat private.pem)"
   ```

2. **Kubernetes Secrets** - 用於生產環境
   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: app-secrets
   data:
     database-url: <base64-encoded>
     jwt-private-key: <base64-encoded>
   ```

3. **Secret Manager** - 用於敏感機密（推薦）
   - AWS Secrets Manager
   - Google Secret Manager
   - HashiCorp Vault

### 配置優先級

1. 環境變量（最高優先級）
2. 配置文件 (`config.{env}.toml`)
3. 默認值（在代碼中）

## 📝 TODO 管理

### 不要在代碼中留下 TODO

```rust
// ❌ 不好
fn process() {
    // TODO: implement this
    todo!()
}

// ✅ 好 - 創建 GitHub issue
fn process() -> Result<()> {
    // 參考: Issue #123
    bail!("Not implemented yet")
}
```

### TODO 轉換流程

1. 運行掃描腳本
   ```bash
   ./scripts/create_github_issues.sh
   ```

2. 審查 `github_issues.md`

3. 創建 GitHub issues
   ```bash
   # 配置後自動創建
   gh issue create --title "..." --body "..." --label "todo"
   ```

4. 在代碼中引用 issue
   ```rust
   // TODO(#123): Implement rate limiting
   ```

5. 完成後關閉 issue

## 🔄 持續改進

### 每週檢查

```bash
# 1. 掃描新的 TODOs
./scripts/create_github_issues.sh

# 2. 檢查測試覆蓋率
cargo tarpaulin

# 3. 運行安全審計
cargo audit

# 4. 更新依賴
cargo update
```

### 月度審查

- 審查所有打開的 TODO issues
- 評估技術債務
- 更新此文檔
- 團隊代碼質量回顧

## 🎓 培訓資源

- [Rust Error Handling](https://doc.rust-lang.org/book/ch09-00-error-handling.html)
- [anyhow crate](https://docs.rs/anyhow/)
- [Clippy Lints](https://rust-lang.github.io/rust-clippy/)
- [OWASP Secure Coding](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/)

## 🆘 獲取幫助

遇到問題？

1. 查看 [CLAUDE.md](../CLAUDE.md) 獲取代碼審查標準
2. 在團隊頻道提問
3. 創建 GitHub issue 標記 `help-wanted`

## 📈 指標追蹤

追蹤以下指標來衡量代碼質量改進：

- unwrap() 數量（目標：0）
- TODO 數量（目標：<10）
- 測試覆蓋率（目標：>80%）
- Clippy warnings（目標：0）
- 平均 PR 審查時間
- 生產環境 panic 次數（目標：0）