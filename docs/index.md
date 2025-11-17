# Nova Documentation Hub

Nova 的文檔依照主題拆分在多個子資料夾，這份索引提供常用入口：

## 快速入口
- [Start Here](START_HERE.md) – 新手導覽與部署快速路徑
- [Architecture Overview](architecture/ANALYSIS_README.md) – 微服務整體架構與審查索引
- [Development Guides](development/) – 分支策略、技術債、P0/P1 指南
- [Testing Playbooks](testing/) – 測試策略、TDD、E2E 指南

## 主題地圖
- **Architecture (`architecture/`)** – 架構決策、服務邊界、GRPC/GraphQL 指南
- **Services (`services/`)** – 服務解耦、整併計畫、Messaging/Kafka 專題
- **Deployment (`deployment/`)** – 雲端部署、CI/CD 範本、Secrets 與 EKS 升級流程
- **Observability (`observability/`)** – Structured Logging、Tracing、Gateway 覆盤
- **Database (`db/`)** – ERD、資料庫升級、行動手冊
- **Testing (`testing/`)** – 測試評估、測試策略索引、TDD 文件
- **Development (`development/`)** – 代碼實況、技術債盤點、專案完成度與 Blockers
- **Documentation (`documentation/`)** – 文檔政策、清理紀錄與 API 審核
- **iOS (`ios/`)** – iOS 後端整合、Roadmap 與行動指南
- **Operations (`operations/`)** – Runbook、Chaos Engineering、K8s 相關作業

每個資料夾都包含其專屬 `README` 或索引（若缺少可依政策補上）。若需要歷史報告，可在 `docs/archive/` 重新建立日期式結構後再提交。

> 📌 GitHub Pages 仍透過 `.github/workflows/pages.yml` 生成文件。搬移檔案後，請更新相對應的連結以確保頁面可正確載入。
