# Nova Backend (user-service retired)

本目錄原先的 `user-service` 已退役，相關組件與職責已分流至：
- 認證／身份：`identity-service`
- 內容與媒體：`content-service`、`media-service`
- 社交／互動：`social-service`、`realtime-chat-service`

部署與運維層面的 `user-service` 配置（docker-compose、Kubernetes、Nginx、ConfigMap、生成腳本等）已清除；最新入口與端點請參考各服務自帶的 README 或網關配置。
