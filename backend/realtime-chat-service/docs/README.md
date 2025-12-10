# Nova Realtime Chat Service 文檔

## 目錄結構

```
docs/
├── api/                    # 前端團隊 API 文檔
│   └── API.md              # 完整 REST/WebSocket API 參考
│
├── internal/               # 內部技術文檔
│   ├── E2EE_HANDLERS_IMPLEMENTATION.md    # E2EE API handler 實作細節
│   ├── E2EE_VODOZEMAC_IMPLEMENTATION.md   # vodozemac 加密實作
│   ├── MATRIX_SUMMARY.md                  # Matrix 整合摘要
│   ├── MATRIX_VOIP_DESIGN.md              # Matrix VoIP 設計規格
│   ├── MATRIX_SDK_UPGRADE_PLAN.md         # SDK 升級計劃
│   └── CALL_SERVICE_MATRIX_INTEGRATION.md # 通話服務整合計劃
│
└── dev/                    # 開發/測試文檔
    ├── ICE_SERVERS_API_TEST.md            # ICE API 測試指南
    └── SESSION_SUMMARY_*.md               # 開發進度記錄
```

## 快速導覽

### 前端團隊

- **[API.md](api/API.md)** - 完整的 REST API 和 WebSocket 文檔，包含：
  - 認證方式 (JWT)
  - WebSocket 即時通訊
  - 所有 REST 端點 (對話、訊息、群組、通話、位置、E2EE)
  - 資料模型 (TypeScript/Swift)
  - SDK 範例程式碼

### 後端開發

- **E2EE 加密** - `internal/E2EE_*.md`
- **Matrix 整合** - `internal/MATRIX_*.md`
- **通話服務** - `internal/CALL_SERVICE_*.md`

### 測試與開發

- **測試指南** - `dev/ICE_SERVERS_API_TEST.md`
- **開發日誌** - `dev/SESSION_SUMMARY_*.md`

---

**Last Updated**: 2025-12-11
