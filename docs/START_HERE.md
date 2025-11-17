# Start Here

歡迎進入 Nova 文檔。以下提供兩種導覽方式：

## 1. 依主題導覽

| 領域 | 位置 | 包含內容 |
| --- | --- | --- |
| 架構 | `architecture/` | 架構審查、服務邊界、gRPC 指南、GraphQL/Federation 建議 |
| 服務整併 | `services/` | Service Refactor、Messaging/Kafka、Rate Limiting、Library/Integration 狀態 |
| 研發流程 | `development/` | 分支策略、技術債、P0/P1 Blockers、完成度報告 |
| 測試與 TDD | `testing/` | 測試策略、TDD 指南、Critical Test Playbook、E2E 說明 |
| 部署與營運 | `deployment/`、`operations/` | CI/CD、Secrets 管理、EKS 升級、Staging 指南、Chaos Engineering |
| 觀測性 | `observability/` | Structured Logging 套件、Tracing、Gateway 實例 |
| 資料庫 | `db/` | ERD、Migration 指南、Read Replica 策略、資料字典 |
| iOS 整合 | `ios/` | iOS ↔ Backend 審查、Roadmap、AWS 接入指南 |
| 文檔治理 | `documentation/` | 文檔政策、清理紀錄、API 審核報告 |

若需要舊版報告，請在 `docs/archive/YYYY-MM/` 新增資料夾再放入檔案（目前預設為空）。

## 2. 部署快速路線圖

1. **前置檢查** – `deployment/PRE_DEPLOYMENT_CHECKLIST.md`
2. **最短路徑部署** – `deployment/QUICKSTART.md`
3. **完整 Deployment Guide** – `deployment/DEPLOYMENT.md`
4. **CI/CD 與 Secrets** – `deployment/CI_CD_QUICK_REFERENCE.md`, `deployment/aws-secrets-manager-integration.md`, `deployment/secrets-rotation-guide.md`
5. **EKS / 環境維運** – `deployment/eks-upgrade-plan.md`, `deployment/STAGING_DEPLOYMENT_GUIDE.md`

將文檔移動或新增於子資料夾時，請同步更新此頁與 `docs/index.md` 的連結，確保 GitHub Pages 可正常索引用戶。
