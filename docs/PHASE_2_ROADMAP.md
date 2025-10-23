# PHASE 2 路線圖 - 功能實現

**時間框架**: 2025-10-24 至 2025-10-26 (3 天)
**工作量**: 18-20 小時（1 人）
**優先級順序**: 按影響力排序

---

## 🔴 優先級 P1 - 立即開始（6-8 小時）

### P1.1: 搜索服務完成全文搜索 (2 小時)

**當前狀態**: Axum 框架就緒，搜索邏輯未實現

**實現清單**:

1. **搜索處理程序** `backend/search-service/src/main.rs`
```rust
// 需要實現的端點:
// POST /api/v1/search
// 參數: q (查詢), type (users|posts|hashtags), limit, offset
// 應該返回: SearchResults { items: Vec<SearchItem>, total: u32 }

async fn search_handler(
    State(db): State<PgPool>,
    Query(params): Query<SearchParams>,
) -> Result<Json<SearchResults>, AppError> {
    // 1. 驗證查詢字符串 (最少 2 個字符)
    if params.q.len() < 2 {
        return Err(AppError::BadRequest("Query too short".to_string()));
    }

    // 2. 構建動態查詢
    let query = format!("%{}%", params.q); // ILIKE 模式

    // 3. 多表搜索
    let results = match params.search_type.as_str() {
        "users" => search_users(&db, &query, params.limit).await?,
        "posts" => search_posts(&db, &query, params.limit).await?,
        "hashtags" => search_hashtags(&db, &query, params.limit).await?,
        _ => return Err(AppError::BadRequest("Invalid type".to_string())),
    };

    Ok(Json(SearchResults {
        items: results,
        total: results.len() as u32,
    }))
}

// 搜索用戶
async fn search_users(pool: &PgPool, query: &str, limit: i32) -> Result<Vec<SearchItem>> {
    sqlx::query_as::<_, SearchItem>(
        "SELECT id, username as title, bio as description, 'user' as type
         FROM users
         WHERE username ILIKE $1 OR bio ILIKE $1
         LIMIT $2"
    )
    .bind(query)
    .bind(limit)
    .fetch_all(pool)
    .await
    .map_err(|e| AppError::Database(e.to_string()))
}

// 搜索帖子
async fn search_posts(pool: &PgPool, query: &str, limit: i32) -> Result<Vec<SearchItem>> {
    sqlx::query_as::<_, SearchItem>(
        "SELECT id, title, content as description, 'post' as type
         FROM posts
         WHERE title ILIKE $1 OR content ILIKE $1
         LIMIT $2"
    )
    .bind(query)
    .bind(limit)
    .fetch_all(pool)
    .await
    .map_err(|e| AppError::Database(e.to_string()))
}

// 搜索主題標籤
async fn search_hashtags(pool: &PgPool, query: &str, limit: i32) -> Result<Vec<SearchItem>> {
    sqlx::query_as::<_, SearchItem>(
        "SELECT id, tag as title, CAST(post_count as VARCHAR) as description, 'hashtag' as type
         FROM hashtags
         WHERE tag ILIKE $1
         ORDER BY post_count DESC
         LIMIT $2"
    )
    .bind(query)
    .bind(limit)
    .fetch_all(pool)
    .await
    .map_err(|e| AppError::Database(e.to_string()))
}
```

2. **添加 Redis 緩存** (1 小時)
```rust
// 快速查詢檢查（簡單 Redis ILIKE 匹配）
async fn search_with_cache(
    redis: &mut redis::aio::Connection,
    db: &PgPool,
    query: &str,
    search_type: &str,
) -> Result<Vec<SearchItem>> {
    let cache_key = format!("search:{}:{}", search_type, query);

    // 嘗試從 Redis 取
    if let Ok(cached) = redis.get::<_, String>(&cache_key).await {
        return Ok(serde_json::from_str(&cached)?);
    }

    // 如果 cache miss，查詢數據庫
    let results = search_from_db(db, query, search_type).await?;

    // 設置 1 小時 TTL 的快取
    redis.set_ex(&cache_key, serde_json::to_string(&results)?, 3600).await?;

    Ok(results)
}
```

**驗證命令**:
```bash
curl -X POST http://localhost:3002/api/v1/search \
  -H "Content-Type: application/json" \
  -d '{"q": "test", "type": "users", "limit": 10}'
```

**Linus 品味檢查**:
- ✅ 消除特殊情況（統一的 ILIKE 搜索）
- ✅ 簡潔實現（3 個相似的搜索函數）
- ✅ 緩存策略清晰

---

### P1.2: Google OAuth 端點集成 (2 小時)

**當前狀態**: 驗證邏輯完成，端點未實現

**實現清單**:

1. **添加路由** `backend/user-service/src/main.rs`
```rust
// 在路由配置中添加:
.route("/api/v1/auth/google-verify", post(verify_google_oauth))
```

2. **實現驗證端點** `backend/user-service/src/handlers/oauth.rs`
```rust
#[derive(Deserialize)]
pub struct GoogleVerifyRequest {
    pub id_token: String,
}

#[derive(Serialize)]
pub struct AuthResponse {
    pub jwt_token: String,
    pub user_id: Uuid,
    pub is_new_user: bool,
}

pub async fn verify_google_oauth(
    State(google_provider): State<Arc<GoogleOAuthProvider>>,
    State(db): State<PgPool>,
    State(jwt_secret): State<String>,
    Json(req): Json<GoogleVerifyRequest>,
) -> Result<HttpResponse> {
    // 1. 驗證 Google ID token
    let google_user = google_provider
        .verify_google_token(&req.id_token)
        .await
        .map_err(|e| AppError::Authentication(format!("Invalid token: {}", e)))?;

    // 2. 從數據庫查找或創建用戶
    let user = sqlx::query_as::<_, User>(
        "SELECT * FROM users WHERE google_id = $1"
    )
    .bind(&google_user.sub)
    .fetch_optional(&db)
    .await?;

    let (user, is_new) = match user {
        Some(u) => (u, false),
        None => {
            // 創建新用戶
            let new_user = User {
                id: Uuid::new_v4(),
                email: google_user.email.clone(),
                username: generate_username_from_email(&google_user.email),
                google_id: Some(google_user.sub.clone()),
                created_at: Utc::now(),
                // ... 其他字段
            };

            sqlx::query(
                "INSERT INTO users (id, email, username, google_id, created_at)
                 VALUES ($1, $2, $3, $4, $5)"
            )
            .bind(&new_user.id)
            .bind(&new_user.email)
            .bind(&new_user.username)
            .bind(&new_user.google_id)
            .bind(&new_user.created_at)
            .execute(&db)
            .await?;

            (new_user, true)
        }
    };

    // 3. 生成 JWT token
    let jwt_token = generate_jwt(&user.id, &jwt_secret)?;

    Ok(HttpResponse::Ok().json(AuthResponse {
        jwt_token,
        user_id: user.id,
        is_new_user: is_new,
    }))
}

fn generate_username_from_email(email: &str) -> String {
    email.split('@').next().unwrap_or("user").to_string()
}
```

3. **中間件集成** (檢查 JWT 中是否有 `oauth_provider` 聲明)
```rust
// 在 JwtAuthMiddleware 中添加:
let oauth_provider = claims.get("oauth_provider").map(|v| v.to_string());
// 儲存在 request extensions 中
```

**驗證命令**:
```bash
# 首先從 Google 取得 id_token（需要 Google OAuth 設置）
curl -X POST http://localhost:3000/api/v1/auth/google-verify \
  -H "Content-Type: application/json" \
  -d '{"id_token": "eyJ..."}' \
  # 應該返回 JWT 和 user_id
```

**測試覆蓋**:
- [ ] 有效的 Google token → 創建用戶 + 返回 JWT
- [ ] 已有的 Google 用戶 → 返回現有用戶 + JWT
- [ ] 無效 token → 400 Bad Request

---

### P1.3: Apple OAuth 端點集成 (2 小時)

**實現清單** (類似 Google):

```rust
#[derive(Deserialize)]
pub struct AppleVerifyRequest {
    pub id_token: String,
    pub user: Option<AppleUser>,  // 首次登陸時提供名稱
}

#[derive(Deserialize)]
pub struct AppleUser {
    pub name: AppleUserName,
}

#[derive(Deserialize)]
pub struct AppleUserName {
    pub firstName: Option<String>,
    pub lastName: Option<String>,
}

pub async fn verify_apple_oauth(
    State(apple_provider): State<Arc<AppleOAuthProvider>>,
    State(db): State<PgPool>,
    Json(req): Json<AppleVerifyRequest>,
) -> Result<HttpResponse> {
    // 1. 驗證 Apple ID token (JWT 格式)
    let apple_user = apple_provider
        .verify_apple_token(&req.id_token)
        .await
        .map_err(|e| AppError::Authentication(format!("Invalid Apple token: {}", e)))?;

    // 2. 查找或創建用戶
    let user = sqlx::query_as::<_, User>(
        "SELECT * FROM users WHERE apple_id = $1"
    )
    .bind(&apple_user.sub)
    .fetch_optional(&db)
    .await?;

    let (user, is_new) = match user {
        Some(u) => (u, false),
        None => {
            // 從 AppleUser 提取名稱
            let full_name = match &req.user {
                Some(au) => {
                    let first = au.name.firstName.clone().unwrap_or_default();
                    let last = au.name.lastName.clone().unwrap_or_default();
                    format!("{} {}", first, last).trim().to_string()
                }
                None => "Apple User".to_string(),
            };

            let new_user = User {
                id: Uuid::new_v4(),
                email: apple_user.email.clone(),
                username: generate_username_from_email(&apple_user.email),
                apple_id: Some(apple_user.sub.clone()),
                full_name: Some(full_name),
                created_at: Utc::now(),
                // ...
            };

            // 插入新用戶...
            (new_user, true)
        }
    };

    // 3. 生成 JWT
    let jwt_token = generate_jwt(&user.id, &jwt_secret)?;

    Ok(HttpResponse::Ok().json(AuthResponse {
        jwt_token,
        user_id: user.id,
        is_new_user: is_new,
    }))
}
```

---

## 🟡 優先級 P2 - 第二天完成（4-6 小時）

### P2.1: Facebook OAuth 端點集成 (2 小時)

**類似於 Google 和 Apple，但驗證流程不同**:

```rust
pub async fn verify_facebook_oauth(
    State(facebook_provider): State<Arc<FacebookOAuthProvider>>,
    State(db): State<PgPool>,
    Json(req): Json<FacebookVerifyRequest>,
) -> Result<HttpResponse> {
    // 1. 驗證 Facebook access token
    let fb_user = facebook_provider
        .verify_facebook_token(&req.access_token)
        .await
        .map_err(|e| AppError::Authentication(format!("Invalid Facebook token: {}", e)))?;

    // 2. 查找或創建用戶（與 Google/Apple 相同）
    // ...
}
```

### P2.2: 視頻轉碼完整化 (4 小時)

**當前狀態**: 元數據提取完成，轉碼邏輯未完成

**實現清單**:

1. **FFmpeg 多品質轉碼**
```rust
pub async fn transcode_video(
    &self,
    input_path: &Path,
    output_dir: &Path,
    target_qualities: Vec<Quality>,
) -> Result<Vec<TranscodedOutput>> {
    let mut outputs = Vec::new();

    for quality in target_qualities {
        let output_file = output_dir.join(format!("output_{}.mp4", quality.resolution));

        let ffmpeg_cmd = format!(
            "ffmpeg -i {} -c:v libx264 -preset {} -crf {} -s {} -c:a aac -b:a {} -f mp4 {}",
            input_path.display(),
            quality.preset,  // ultrafast, fast, medium, slow
            quality.crf,     // 質量（0-51, 越低越好）
            quality.resolution,
            quality.bitrate,
            output_file.display()
        );

        Command::new("sh")
            .arg("-c")
            .arg(&ffmpeg_cmd)
            .output()
            .await
            .map_err(|e| AppError::Internal(format!("FFmpeg failed: {}", e)))?;

        outputs.push(TranscodedOutput {
            quality_name: quality.name,
            file_path: output_file,
            bitrate: quality.bitrate,
        });
    }

    Ok(outputs)
}

#[derive(Clone)]
pub struct Quality {
    pub name: String,
    pub resolution: String,  // e.g., "1920x1080", "1280x720"
    pub bitrate: String,     // e.g., "2500k", "1000k"
    pub preset: String,      // fast, medium, slow
    pub crf: u8,             // quality (18-28 recommended)
}
```

2. **HLS Manifest 生成**
```rust
pub async fn generate_hls_manifest(
    &self,
    segment_dir: &Path,
    qualities: Vec<Quality>,
) -> Result<String> {
    let mut playlist = String::from("#EXTM3U\n#EXT-X-VERSION:3\n");

    // 主播放列表（多品質）
    for quality in qualities {
        playlist.push_str(&format!(
            "#EXT-X-STREAM-INF:BANDWIDTH={}\n{}.m3u8\n",
            parse_bitrate_to_bandwidth(&quality.bitrate),
            quality.name
        ));
    }

    Ok(playlist)
}
```

---

## 🟢 優先級 P3 - 第三天（4-6 小時）

### P3.1: 推薦引擎實現 (6 小時)

**替換當前的空實現**:

```rust
pub async fn get_recommendations(
    &self,
    user_id: Uuid,
    limit: usize,
) -> Result<Vec<Uuid>> {
    // 1. 從協作過濾獲得候選集合
    let cf_candidates = self.cf_model
        .get_similar_users(user_id, 10)?  // 找 10 個相似用戶
        .into_iter()
        .flat_map(|uid| self.get_posts_from_user(uid))
        .collect::<Vec<_>>();

    // 2. 從內容基礎過濾獲得候選集合
    let cb_candidates = self.cb_model
        .get_similar_posts(user_id, limit)?;

    // 3. 混合排名
    let ranked = self.hybrid_ranker.rank(
        user_id,
        cf_candidates,
        cb_candidates,
        limit,
    ).await?;

    Ok(ranked)
}
```

---

## 📊 PHASE 2 完成檢查清單

- [ ] 搜索服務: POST /api/v1/search 工作正常
- [ ] Google OAuth: POST /api/v1/auth/google-verify 返回 JWT
- [ ] Apple OAuth: POST /api/v1/auth/apple-verify 返回 JWT
- [ ] Facebook OAuth: POST /api/v1/auth/facebook-verify 返回 JWT
- [ ] 視頻轉碼: FFmpeg 多品質轉碼完成
- [ ] HLS: 播放列表生成完成
- [ ] 推薦引擎: 返回非空的推薦列表
- [ ] 所有測試通過: `cargo test --all`
- [ ] 編譯無警告: `cargo clippy --all`

---

## 時間估計

| 任務 | 估計時間 | 累計 |
|------|---------|------|
| P1.1 搜索服務 | 2h | 2h |
| P1.2 Google OAuth | 2h | 4h |
| P1.3 Apple OAuth | 2h | 6h |
| P2.1 Facebook OAuth | 2h | 8h |
| P2.2 視頻轉碼 | 4h | 12h |
| P3.1 推薦引擎 | 6h | 18h |
| **測試 + 除錯** | **2-4h** | **20-22h** |

**預計完成**: 2025-10-26（3 天）

---

## Linus 風格監督點

1. ✅ 消除特殊情況 - 統一的搜索邏輯，而不是多個特定於類型的處理程序
2. ✅ 不要破壞向後兼容性 - 所有新端點都是附加的
3. ✅ 簡潔代碼 - 函數保持在 50 行以下
4. ✅ 類型安全 - 使用 Result<T, E>，無 unwrap()

---

**簽名**: Claude 代理
**日期**: 2025-10-23
**下次審查**: 2025-10-26
