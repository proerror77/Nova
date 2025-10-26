use serde::{Deserialize, Serialize};
use sqlx::{Pool, Postgres, Row};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchSuggestion {
    pub suggestion_text: String,
    pub suggestion_type: String, // 'trending', 'recent', 'personalized'
    pub query_type: String,      // 'user', 'post', 'hashtag', 'video', 'stream'
    pub relevance_score: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SuggestionResponse {
    pub suggestions: Vec<SearchSuggestion>,
    pub total: usize,
}

pub struct SearchSuggestionsService;

impl SearchSuggestionsService {
    /// Get search suggestions for autocomplete
    /// Combines trending searches + user's recent searches + personalized suggestions
    pub async fn get_suggestions(
        db: &Pool<Postgres>,
        user_id: Option<Uuid>,
        query_type: &str,
        prefix: &str,
        limit: i64,
    ) -> Result<SuggestionResponse, String> {
        let limit = limit.min(20); // Cap at 20 suggestions

        // First, try to get cached suggestions
        let suggestions = sqlx::query(
            r#"
            SELECT suggestion_text, suggestion_type, query_type, relevance_score
            FROM search_suggestions
            WHERE query_type = $1
              AND (user_id = $2 OR user_id IS NULL)
              AND suggestion_text ILIKE $3
              AND expires_at > NOW()
            ORDER BY
              CASE WHEN user_id = $2 THEN 0 ELSE 1 END,
              relevance_score DESC,
              suggestion_text ASC
            LIMIT $4
            "#,
        )
        .bind(query_type)
        .bind(user_id)
        .bind(format!("{}%", prefix))
        .bind(limit)
        .fetch_all(db)
        .await
        .map_err(|e| format!("Failed to fetch suggestions: {}", e))?;

        let result: Vec<SearchSuggestion> = suggestions
            .iter()
            .map(|row| SearchSuggestion {
                suggestion_text: row.get("suggestion_text"),
                suggestion_type: row.get("suggestion_type"),
                query_type: row.get("query_type"),
                relevance_score: row.get("relevance_score"),
            })
            .collect();

        let total = result.len();

        // If we have fewer than 5 suggestions, also get trending searches
        if result.len() < 5 {
            let trending = sqlx::query(
                r#"
                SELECT query_text, query_type, trending_score
                FROM trending_searches
                WHERE query_type = $1
                  AND query_text ILIKE $2
                ORDER BY trending_score DESC
                LIMIT $3
                "#,
            )
            .bind(query_type)
            .bind(format!("{}%", prefix))
            .bind((limit - result.len() as i64).max(1))
            .fetch_all(db)
            .await
            .map_err(|e| format!("Failed to fetch trending: {}", e))?;

            let mut all_suggestions = result;
            for row in trending {
                if all_suggestions.len() >= limit as usize {
                    break;
                }
                all_suggestions.push(SearchSuggestion {
                    suggestion_text: row.get("query_text"),
                    suggestion_type: "trending".to_string(),
                    query_type: row.get("query_type"),
                    relevance_score: row.get::<f64, _>("trending_score"),
                });
            }

            Ok(SuggestionResponse {
                suggestions: all_suggestions,
                total,
            })
        } else {
            Ok(SuggestionResponse {
                suggestions: result,
                total,
            })
        }
    }

    /// Record a search query for history and trending calculation
    pub async fn record_search(
        db: &Pool<Postgres>,
        user_id: Uuid,
        query_type: &str,
        query_text: &str,
        result_count: i32,
    ) -> Result<(), String> {
        sqlx::query(
            r#"
            INSERT INTO search_history (user_id, query_type, query_text, result_count)
            VALUES ($1, $2, $3, $4)
            "#,
        )
        .bind(user_id)
        .bind(query_type)
        .bind(query_text)
        .bind(result_count)
        .execute(db)
        .await
        .map_err(|e| format!("Failed to record search: {}", e))?;

        Ok(())
    }

    /// Record when user clicks on a search result
    pub async fn record_click(
        db: &Pool<Postgres>,
        user_id: Uuid,
        query_type: &str,
        query_text: &str,
        result_id: Uuid,
    ) -> Result<(), String> {
        // Update search_history with click info
        sqlx::query(
            r#"
            UPDATE search_history
            SET clicked_result_id = $1, clicked_at = NOW()
            WHERE user_id = $2
              AND query_type = $3
              AND query_text = $4
              AND clicked_at IS NULL
            ORDER BY searched_at DESC
            LIMIT 1
            "#,
        )
        .bind(result_id)
        .bind(user_id)
        .bind(query_type)
        .bind(query_text)
        .execute(db)
        .await
        .map_err(|e| format!("Failed to record click: {}", e))?;

        // Update popular_search_results for ranking
        let query_hash = format!("{:x}", md5::compute(query_text.as_bytes()));
        sqlx::query(
            r#"
            INSERT INTO popular_search_results (query_type, query_hash, result_id, click_count)
            VALUES ($1, $2, $3, 1)
            ON CONFLICT (query_hash, result_id) DO UPDATE
            SET click_count = click_count + 1,
                last_clicked_at = NOW(),
                last_updated_at = NOW()
            "#,
        )
        .bind(query_type)
        .bind(query_hash)
        .bind(result_id)
        .execute(db)
        .await
        .map_err(|e| format!("Failed to update popular results: {}", e))?;

        Ok(())
    }

    /// Get user's recent searches
    pub async fn get_recent_searches(
        db: &Pool<Postgres>,
        user_id: Uuid,
        query_type: &str,
        limit: i64,
    ) -> Result<Vec<String>, String> {
        let limit = limit.min(20);

        let results = sqlx::query(
            r#"
            SELECT DISTINCT query_text
            FROM search_history
            WHERE user_id = $1
              AND query_type = $2
            ORDER BY searched_at DESC
            LIMIT $3
            "#,
        )
        .bind(user_id)
        .bind(query_type)
        .bind(limit)
        .fetch_all(db)
        .await
        .map_err(|e| format!("Failed to fetch recent searches: {}", e))?;

        Ok(results.iter().map(|r| r.get("query_text")).collect())
    }

    /// Get trending searches globally
    pub async fn get_trending_searches(
        db: &Pool<Postgres>,
        query_type: &str,
        limit: i64,
    ) -> Result<Vec<String>, String> {
        let limit = limit.min(50);

        let results = sqlx::query(
            r#"
            SELECT query_text
            FROM trending_searches
            WHERE query_type = $1
            ORDER BY trending_score DESC, last_updated_at DESC
            LIMIT $2
            "#,
        )
        .bind(query_type)
        .bind(limit)
        .fetch_all(db)
        .await
        .map_err(|e| format!("Failed to fetch trending: {}", e))?;

        Ok(results.iter().map(|r| r.get("query_text")).collect())
    }

    /// Clear old search history (called by maintenance job)
    pub async fn cleanup_old_history(db: &Pool<Postgres>) -> Result<u64, String> {
        let result = sqlx::query(
            "DELETE FROM search_history WHERE searched_at < NOW() - INTERVAL '90 days'",
        )
        .execute(db)
        .await
        .map_err(|e| format!("Failed to cleanup history: {}", e))?;

        Ok(result.rows_affected())
    }
}
