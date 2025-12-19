# Git Sync Script

Git 工作流自动化脚本，一键完成 commit → update → push → PR 流程。

## 快速开始

```bash
# 一键上传（暂存所有 + 提交 + 推送 + 创建PR）
upload "feat: your commit message"

# 或使用完整脚本
./scripts/git-sync.sh -a -m "feat: your message" -p
```

## upload 命令

```bash
upload "commit message"   # 完整流程
upload                    # 使用默认消息
```

## git-sync.sh 选项

| 选项 | 说明 |
|------|------|
| `-m, --message` | 提交消息 |
| `-a, --all` | 暂存所有更改 |
| `-r, --rebase` | 使用 rebase 更新 |
| `-b, --branch` | 目标分支（默认 main） |
| `-p, --pr` | 创建 PR |
| `--draft` | 创建草稿 PR |
| `-f, --force` | 强制推送 |
| `-h, --help` | 显示帮助 |

## 示例

```bash
# 基本提交和推送
./scripts/git-sync.sh -a -m "fix: bug fix"

# 使用 rebase 并创建 PR
./scripts/git-sync.sh -a -m "feat: new feature" -r -p

# 创建草稿 PR
./scripts/git-sync.sh -a -m "wip: work in progress" -p --draft
```
