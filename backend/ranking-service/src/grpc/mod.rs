use crate::models::{RankedPost, RecallStats};
use crate::services::coarse_ranking::{CoarseCandidate, CoarseRankingLayer, UserFeatures};
use crate::services::exploration::{NewContentPool, UCBExplorer};
use crate::services::profile_builder::{
    ClickHouseProfileDatabase, LlmProfileAnalyzer, ProfileDatabase, ProfileUpdater,
    ProfileUpdaterConfig,
};
use crate::services::realtime::SessionInterestManager;
use crate::services::{DiversityLayer, FeatureClient, RankingLayer, RecallLayer};
use std::collections::HashSet;
use std::sync::Arc;
use tokio::sync::RwLock;
use tonic::{Request, Response, Status};
use tracing::{error, info, warn};
use uuid::Uuid;

// Proto 生成的代碼
pub mod ranking_proto {
    tonic::include_proto!("ranking.v1");
}

use ranking_proto::{
    ranking_service_server::RankingService, Candidate, PostFeatures, RankFeedRequest,
    RankFeedResponse, RankedPost as ProtoRankedPost, RecallRequest, RecallResponse,
    RecallStats as ProtoRecallStats,
};

// Profile-related proto types
use ranking_proto::{
    BatchUpdateProfilesRequest, BatchUpdateProfilesResponse, BehaviorPattern as ProtoBehavior,
    ConsumptionPatterns as ProtoConsumption, ContentRecommendation as ProtoRecommendation,
    GetPersonalizedRecommendationsRequest, GetPersonalizedRecommendationsResponse,
    GetUserInterestsRequest, GetUserInterestsResponse, GetUserPersonaRequest,
    GetUserPersonaResponse, GetUserProfileRequest, GetUserProfileResponse,
    InterestTag as ProtoInterest, PredictedPreferences as ProtoPreferences,
    UpdateUserProfileRequest, UpdateUserProfileResponse, UserPersona as ProtoPersona,
    UserProfile as ProtoProfile,
};

/// 抖音风格 4 层 Ranking Pipeline 配置
#[derive(Debug, Clone)]
pub struct PipelineConfig {
    /// 召回层输出数量 (万级)
    pub recall_limit: i32,
    /// 粗排层输出数量 (千级)
    pub coarse_limit: usize,
    /// 精排层输出数量 (百级)
    pub fine_limit: usize,
    /// 探索内容注入比例 (0.0 - 1.0)
    pub exploration_ratio: f32,
    /// 是否启用实时会话个性化
    pub enable_session_personalization: bool,
}

impl Default for PipelineConfig {
    fn default() -> Self {
        Self {
            recall_limit: 10000,
            coarse_limit: 1000,
            fine_limit: 100,
            exploration_ratio: 0.1, // 10% 探索内容
            enable_session_personalization: true,
        }
    }
}

pub struct RankingServiceImpl {
    // 核心 4 层 Pipeline
    recall_layer: Arc<RecallLayer>,
    coarse_ranking_layer: Arc<CoarseRankingLayer>,
    ranking_layer: Arc<RankingLayer>,
    diversity_layer: Arc<DiversityLayer>,
    // 辅助服务
    feature_client: Arc<FeatureClient>,
    exploration_pool: Arc<NewContentPool>,
    ucb_explorer: Arc<UCBExplorer>,
    session_interests: Arc<SessionInterestManager>,
    // 用戶畫像服務
    profile_updater: Arc<RwLock<Option<ProfileUpdater<ClickHouseProfileDatabase>>>>,
    llm_analyzer: Arc<RwLock<Option<LlmProfileAnalyzer>>>,
    // 配置
    config: PipelineConfig,
}

impl RankingServiceImpl {
    /// 创建完整的 4 层 Pipeline
    pub fn new(
        recall_layer: RecallLayer,
        ranking_layer: RankingLayer,
        diversity_layer: DiversityLayer,
    ) -> Self {
        // 创建默认的 Redis 客户端 (实际使用时应从配置注入)
        let redis_client = redis::Client::open("redis://localhost:6379")
            .expect("Failed to create Redis client");

        Self {
            recall_layer: Arc::new(recall_layer),
            coarse_ranking_layer: Arc::new(CoarseRankingLayer::new(1000)),
            ranking_layer: Arc::new(ranking_layer),
            diversity_layer: Arc::new(diversity_layer),
            feature_client: Arc::new(FeatureClient::new(redis_client.clone())),
            exploration_pool: Arc::new(NewContentPool::new(redis_client.clone())),
            ucb_explorer: Arc::new(UCBExplorer::new()),
            session_interests: Arc::new(SessionInterestManager::new(redis_client)),
            profile_updater: Arc::new(RwLock::new(None)),
            llm_analyzer: Arc::new(RwLock::new(None)),
            config: PipelineConfig::default(),
        }
    }

    /// 完整构造器，支持依赖注入
    pub fn with_all_layers(
        recall_layer: RecallLayer,
        coarse_ranking_layer: CoarseRankingLayer,
        ranking_layer: RankingLayer,
        diversity_layer: DiversityLayer,
        feature_client: FeatureClient,
        exploration_pool: NewContentPool,
        session_interests: SessionInterestManager,
        config: PipelineConfig,
    ) -> Self {
        Self {
            recall_layer: Arc::new(recall_layer),
            coarse_ranking_layer: Arc::new(coarse_ranking_layer),
            ranking_layer: Arc::new(ranking_layer),
            diversity_layer: Arc::new(diversity_layer),
            feature_client: Arc::new(feature_client),
            exploration_pool: Arc::new(exploration_pool),
            ucb_explorer: Arc::new(UCBExplorer::new()),
            session_interests: Arc::new(session_interests),
            profile_updater: Arc::new(RwLock::new(None)),
            llm_analyzer: Arc::new(RwLock::new(None)),
            config,
        }
    }

    /// 設置用戶畫像服務
    pub async fn set_profile_updater(
        &self,
        updater: ProfileUpdater<ClickHouseProfileDatabase>,
    ) {
        let mut guard = self.profile_updater.write().await;
        *guard = Some(updater);
        info!("ProfileUpdater initialized");
    }

    /// 設置 LLM 分析器
    pub async fn set_llm_analyzer(&self, analyzer: LlmProfileAnalyzer) {
        let mut guard = self.llm_analyzer.write().await;
        *guard = Some(analyzer);
        info!("LlmProfileAnalyzer initialized");
    }

    /// 從配置初始化 Profile 服務
    pub async fn init_profile_services(
        &self,
        config: &crate::config::Config,
    ) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
        // 初始化 ClickHouse 數據庫
        let ch_db = Arc::new(ClickHouseProfileDatabase::from_config(&config.clickhouse));

        // 初始化 Redis 客戶端
        let redis_client = redis::Client::open(config.redis.url.as_str())?;

        // 創建 ProfileUpdater
        let profile_config = ProfileUpdaterConfig::default();
        let updater = ProfileUpdater::new(ch_db, redis_client, profile_config);

        self.set_profile_updater(updater).await;

        // 初始化 LLM 分析器（如果啟用）
        if config.llm.enabled {
            if let Some(analyzer) = LlmProfileAnalyzer::from_config(&config.llm) {
                self.set_llm_analyzer(analyzer).await;
            }
        }

        Ok(())
    }

    /// 获取用户特征用于粗排
    async fn get_user_features(&self, user_id: &str) -> UserFeatures {
        // TODO: 从用户画像服务获取完整特征
        // 目前返回默认值
        UserFeatures {
            interest_tags: vec![],
            content_type_preferences: vec!["video".to_string()],
            active_hours: vec![],
            avg_session_length: 300,
            followed_authors: HashSet::new(),
        }
    }

    /// 注入探索内容 (新内容发现)
    async fn inject_exploration_content(
        &self,
        ranked_posts: Vec<RankedPost>,
        exploration_count: usize,
    ) -> Vec<RankedPost> {
        if exploration_count == 0 {
            return ranked_posts;
        }

        // 从探索池采样新内容
        let exploration_ids = match self.exploration_pool.sample_by_ucb(exploration_count).await {
            Ok(ids) => ids,
            Err(e) => {
                warn!("Failed to sample exploration content: {}", e);
                return ranked_posts;
            }
        };

        if exploration_ids.is_empty() {
            return ranked_posts;
        }

        // 将探索内容插入到结果中 (每隔 N 个位置插入一个)
        let mut result = ranked_posts;
        let interval = result.len() / (exploration_count + 1).max(1);

        for (i, content_id) in exploration_ids.iter().enumerate() {
            let position = ((i + 1) * interval).min(result.len());
            result.insert(
                position,
                RankedPost {
                    post_id: content_id.to_string(),
                    score: 0.5, // 探索内容使用中等分数
                    recall_source: crate::models::RecallSource::Personalized,
                    features: crate::models::PostFeatures {
                        engagement_score: 0.5,
                        recency_score: 1.0, // 新内容
                        author_quality_score: 0.5,
                        content_quality_score: 0.5,
                        completion_rate_score: 0.5,
                        author_id: None,
                    },
                },
            );
        }

        result
    }

    /// 应用会话级个性化提升
    async fn apply_session_boost(
        &self,
        session_id: Option<&str>,
        mut ranked_posts: Vec<RankedPost>,
    ) -> Vec<RankedPost> {
        let session_id = match session_id {
            Some(id) if !id.is_empty() => id,
            _ => return ranked_posts,
        };

        // 获取会话兴趣并调整分数
        for post in &mut ranked_posts {
            // TODO: 从帖子获取标签，计算个性化提升
            // 目前跳过实现
        }

        ranked_posts
    }
}

#[tonic::async_trait]
impl RankingService for RankingServiceImpl {
    /// 抖音風格 4 層 Ranking Pipeline
    ///
    /// 1. Recall Layer (召回層): 從多個召回源獲取萬級候選集
    /// 2. Coarse Ranking Layer (粗排層): 使用輕量級規則過濾到千級
    /// 3. Fine Ranking Layer (精排層): 使用複雜特徵精確排序到百級
    /// 4. Diversity Layer (多樣性層): 重排確保內容多樣性
    /// + Exploration: 注入新內容探索
    /// + Session Personalization: 會話級實時個性化
    async fn rank_feed(
        &self,
        request: Request<RankFeedRequest>,
    ) -> Result<Response<RankFeedResponse>, Status> {
        let start_time = std::time::Instant::now();
        let req = request.into_inner();
        let user_id = req.user_id.clone();
        let limit = req.limit.max(1).min(100) as usize;
        let session_id = if req.session_id.is_empty() {
            None
        } else {
            Some(req.session_id.as_str())
        };
        let enable_exploration = req.enable_exploration;
        let exploration_ratio = if req.exploration_ratio > 0.0 {
            req.exploration_ratio
        } else {
            self.config.exploration_ratio
        };

        info!(
            "RankFeed 4-layer pipeline: user_id={}, limit={}, session={:?}",
            user_id, limit, session_id
        );

        // ============================================
        // Layer 1: Recall (召回層) - 萬級候選
        // ============================================
        let (candidates, recall_stats) = self
            .recall_layer
            .recall_candidates(&user_id, Some(self.config.recall_limit))
            .await
            .map_err(|e| Status::internal(format!("Recall failed: {}", e)))?;

        let recall_count = candidates.len();
        info!("Layer 1 (Recall): {} candidates", recall_count);

        if candidates.is_empty() {
            return Ok(Response::new(RankFeedResponse {
                posts: vec![],
                recall_stats: Some(to_proto_recall_stats(recall_stats)),
                pipeline_stats: Some(ranking_proto::PipelineStats {
                    recall_count: 0,
                    coarse_rank_count: 0,
                    fine_rank_count: 0,
                    exploration_count: 0,
                    final_count: 0,
                    coarse_rank_latency_ms: 0.0,
                    fine_rank_latency_ms: 0.0,
                    total_latency_ms: start_time.elapsed().as_secs_f32() * 1000.0,
                }),
            }));
        }

        // ============================================
        // Layer 2: Coarse Ranking (粗排層) - 千級候選
        // ============================================
        let coarse_start = std::time::Instant::now();
        let user_features = self.get_user_features(&user_id).await;

        // 轉換 Candidate -> CoarseCandidate (使用 From trait)
        let coarse_candidates: Vec<CoarseCandidate> = candidates
            .clone()
            .into_iter()
            .map(CoarseCandidate::from)
            .collect();

        let coarse_ranked = self
            .coarse_ranking_layer
            .rank(coarse_candidates, &user_features)
            .map_err(|e| Status::internal(format!("Coarse ranking failed: {}", e)))?;

        let coarse_rank_count = coarse_ranked.len();
        let coarse_latency = coarse_start.elapsed().as_secs_f32() * 1000.0;
        info!(
            "Layer 2 (Coarse): {} -> {} candidates, latency={:.2}ms",
            recall_count, coarse_rank_count, coarse_latency
        );

        // 將 CoarseCandidate 內的 Candidate 取出供精排使用
        let filtered_candidates: Vec<crate::models::Candidate> = coarse_ranked
            .into_iter()
            .map(|cc| cc.candidate)
            .collect();

        // ============================================
        // Layer 3: Fine Ranking (精排層) - 百級候選
        // ============================================
        let fine_start = std::time::Instant::now();
        let ranked_posts = self
            .ranking_layer
            .rank_candidates(filtered_candidates)
            .await
            .map_err(|e| Status::internal(format!("Fine ranking failed: {}", e)))?;

        // 只保留前 N 個
        let fine_ranked: Vec<RankedPost> = ranked_posts
            .into_iter()
            .take(self.config.fine_limit)
            .collect();

        let fine_rank_count = fine_ranked.len();
        let fine_latency = fine_start.elapsed().as_secs_f32() * 1000.0;
        info!(
            "Layer 3 (Fine): {} -> {} candidates, latency={:.2}ms",
            coarse_rank_count, fine_rank_count, fine_latency
        );

        // ============================================
        // Exploration Injection (探索內容注入)
        // ============================================
        let exploration_count = if enable_exploration {
            ((limit as f32) * exploration_ratio) as usize
        } else {
            0
        };

        let with_exploration = self
            .inject_exploration_content(fine_ranked, exploration_count)
            .await;

        let actual_exploration = with_exploration.len() - fine_rank_count;
        info!(
            "Exploration: injected {} new content items",
            actual_exploration
        );

        // ============================================
        // Session Personalization (會話級個性化)
        // ============================================
        let personalized = if self.config.enable_session_personalization {
            self.apply_session_boost(session_id, with_exploration)
                .await
        } else {
            with_exploration
        };

        // ============================================
        // Layer 4: Diversity Re-ranking (多樣性重排)
        // ============================================
        let final_posts = self.diversity_layer.rerank(personalized, limit);
        let final_count = final_posts.len();

        let total_latency = start_time.elapsed().as_secs_f32() * 1000.0;
        info!(
            "Layer 4 (Diversity): {} -> {} posts, total_latency={:.2}ms",
            fine_rank_count + actual_exploration,
            final_count,
            total_latency
        );

        let proto_posts: Vec<ProtoRankedPost> =
            final_posts.into_iter().map(to_proto_ranked_post).collect();

        Ok(Response::new(RankFeedResponse {
            posts: proto_posts,
            recall_stats: Some(to_proto_recall_stats(recall_stats)),
            pipeline_stats: Some(ranking_proto::PipelineStats {
                recall_count: recall_count as i32,
                coarse_rank_count: coarse_rank_count as i32,
                fine_rank_count: fine_rank_count as i32,
                exploration_count: actual_exploration as i32,
                final_count: final_count as i32,
                coarse_rank_latency_ms: coarse_latency,
                fine_rank_latency_ms: fine_latency,
                total_latency_ms: total_latency,
            }),
        }))
    }

    async fn recall_candidates(
        &self,
        request: Request<RecallRequest>,
    ) -> Result<Response<RecallResponse>, Status> {
        let req = request.into_inner();
        let user_id = req.user_id;

        info!("RecallCandidates request: user_id={}", user_id);

        let (candidates, stats) = self
            .recall_layer
            .recall_candidates(&user_id, None)
            .await
            .map_err(|e| Status::internal(format!("Recall failed: {}", e)))?;

        let proto_candidates: Vec<Candidate> = candidates
            .into_iter()
            .map(|c| Candidate {
                post_id: c.post_id,
                recall_source: c.recall_source.as_str().to_string(),
                recall_weight: c.recall_weight,
            })
            .collect();

        Ok(Response::new(RecallResponse {
            candidates: proto_candidates,
            stats: Some(to_proto_recall_stats(stats)),
        }))
    }

    // ============================================
    // User Profile APIs (用戶畫像 API)
    // ============================================

    async fn get_user_profile(
        &self,
        request: Request<GetUserProfileRequest>,
    ) -> Result<Response<GetUserProfileResponse>, Status> {
        let req = request.into_inner();
        info!("GetUserProfile request: user_id={}", req.user_id);

        // Parse user ID
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        // Get profile updater
        let updater_guard = self.profile_updater.read().await;
        let updater = updater_guard.as_ref().ok_or_else(|| {
            Status::unavailable("ProfileUpdater not initialized")
        })?;

        // Try to load from cache first
        match updater.load_profile_from_cache(user_id).await {
            Ok(Some(profile)) => {
                info!(user_id = %user_id, "Profile loaded from cache");
                Ok(Response::new(GetUserProfileResponse {
                    profile: Some(to_proto_profile(profile)),
                    from_cache: true,
                }))
            }
            Ok(None) => {
                // No cache, need to build profile
                warn!(user_id = %user_id, "Profile not in cache, building from scratch");

                // For now, return empty profile - the batch job will populate it
                // In production, you might want to trigger an async update
                Err(Status::not_found(format!(
                    "Profile not found for user {}. Run profile batch job to populate.",
                    user_id
                )))
            }
            Err(e) => {
                error!(user_id = %user_id, error = %e, "Failed to load profile");
                Err(Status::internal(format!("Failed to load profile: {}", e)))
            }
        }
    }

    async fn update_user_profile(
        &self,
        request: Request<UpdateUserProfileRequest>,
    ) -> Result<Response<UpdateUserProfileResponse>, Status> {
        let req = request.into_inner();
        info!(
            "UpdateUserProfile request: user_id={}, force_rebuild={}",
            req.user_id, req.force_rebuild
        );

        // Parse user ID
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        // Get profile updater
        let updater_guard = self.profile_updater.read().await;
        let updater = updater_guard.as_ref().ok_or_else(|| {
            Status::unavailable("ProfileUpdater not initialized")
        })?;

        // Update profile
        match updater.update_user_profile(user_id).await {
            Ok(profile) => {
                info!(user_id = %user_id, "Profile updated successfully");
                Ok(Response::new(UpdateUserProfileResponse {
                    success: true,
                    profile: Some(to_proto_profile(profile)),
                    error_message: String::new(),
                }))
            }
            Err(e) => {
                error!(user_id = %user_id, error = %e, "Failed to update profile");
                Ok(Response::new(UpdateUserProfileResponse {
                    success: false,
                    profile: None,
                    error_message: e.to_string(),
                }))
            }
        }
    }

    async fn get_user_persona(
        &self,
        request: Request<GetUserPersonaRequest>,
    ) -> Result<Response<GetUserPersonaResponse>, Status> {
        let req = request.into_inner();
        info!(
            "GetUserPersona request: user_id={}, regenerate={}",
            req.user_id, req.regenerate
        );

        // Parse user ID
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        // Get LLM analyzer
        let analyzer_guard = self.llm_analyzer.read().await;
        let analyzer = analyzer_guard.as_ref().ok_or_else(|| {
            Status::unavailable("LLM analyzer not initialized. Enable LLM in config to use personas.")
        })?;

        // Get profile updater to load profile data
        let updater_guard = self.profile_updater.read().await;
        let updater = updater_guard.as_ref().ok_or_else(|| {
            Status::unavailable("ProfileUpdater not initialized")
        })?;

        // If regenerate requested, invalidate cache
        if req.regenerate {
            analyzer.invalidate_cache(user_id).await;
        }

        // Load profile first (needed for persona generation)
        let profile = match updater.load_profile_from_cache(user_id).await {
            Ok(Some(profile)) => profile,
            Ok(None) => {
                return Err(Status::not_found(format!(
                    "Profile not found for user {}. Update profile first.",
                    user_id
                )));
            }
            Err(e) => {
                return Err(Status::internal(format!("Failed to load profile: {}", e)));
            }
        };

        // Generate persona using LLM
        match analyzer.analyze_profile(&profile).await {
            Ok(persona) => {
                info!(user_id = %user_id, "Persona generated successfully");
                Ok(Response::new(GetUserPersonaResponse {
                    persona: Some(to_proto_persona(persona)),
                    from_cache: !req.regenerate,
                }))
            }
            Err(e) => {
                error!(user_id = %user_id, error = %e, "Failed to generate persona");
                Err(Status::internal(format!("Failed to generate persona: {}", e)))
            }
        }
    }

    async fn batch_update_profiles(
        &self,
        request: Request<BatchUpdateProfilesRequest>,
    ) -> Result<Response<BatchUpdateProfilesResponse>, Status> {
        let req = request.into_inner();
        info!(
            "BatchUpdateProfiles request: user_count={}, batch_size={}",
            req.user_ids.len(),
            req.batch_size
        );

        // Get profile updater
        let updater_guard = self.profile_updater.read().await;
        let updater = updater_guard.as_ref().ok_or_else(|| {
            Status::unavailable("ProfileUpdater not initialized")
        })?;

        // Parse user IDs
        let user_ids: Vec<Uuid> = req
            .user_ids
            .iter()
            .filter_map(|id| Uuid::parse_str(id).ok())
            .collect();

        let total_count = user_ids.len();
        let mut success_count = 0;
        let mut failed_user_ids: Vec<String> = Vec::new();

        // Process in batches
        for user_id in user_ids {
            match updater.update_user_profile(user_id).await {
                Ok(_) => success_count += 1,
                Err(e) => {
                    warn!(user_id = %user_id, error = %e, "Failed to update profile in batch");
                    failed_user_ids.push(user_id.to_string());
                }
            }
        }

        let failure_count = (total_count - success_count) as i32;
        info!(
            success_count = success_count,
            failure_count = failure_count,
            "Batch update completed"
        );

        Ok(Response::new(BatchUpdateProfilesResponse {
            success_count: success_count as i32,
            failure_count,
            failed_user_ids,
        }))
    }

    async fn get_user_interests(
        &self,
        request: Request<GetUserInterestsRequest>,
    ) -> Result<Response<GetUserInterestsResponse>, Status> {
        let req = request.into_inner();
        let limit = if req.limit > 0 { req.limit as usize } else { 50 };
        let min_weight = if req.min_weight > 0.0 { req.min_weight } else { 0.0 };

        info!(
            "GetUserInterests request: user_id={}, limit={}, min_weight={}",
            req.user_id, limit, min_weight
        );

        // Parse user ID
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        // Get profile updater
        let updater_guard = self.profile_updater.read().await;
        let updater = updater_guard.as_ref().ok_or_else(|| {
            Status::unavailable("ProfileUpdater not initialized")
        })?;

        // Load profile
        match updater.load_profile_from_cache(user_id).await {
            Ok(Some(profile)) => {
                // Filter by min_weight and take limit
                let interests: Vec<ProtoInterest> = profile
                    .interests
                    .into_iter()
                    .filter(|i| i.weight >= min_weight as f64)
                    .take(limit)
                    .map(to_proto_interest)
                    .collect();

                let total_count = interests.len() as i32;
                info!(user_id = %user_id, count = total_count, "User interests retrieved");

                Ok(Response::new(GetUserInterestsResponse {
                    interests,
                    total_count,
                }))
            }
            Ok(None) => {
                Err(Status::not_found(format!(
                    "Profile not found for user {}",
                    user_id
                )))
            }
            Err(e) => {
                error!(user_id = %user_id, error = %e, "Failed to load interests");
                Err(Status::internal(format!("Failed to load interests: {}", e)))
            }
        }
    }

    async fn get_personalized_recommendations(
        &self,
        request: Request<GetPersonalizedRecommendationsRequest>,
    ) -> Result<Response<GetPersonalizedRecommendationsResponse>, Status> {
        let req = request.into_inner();
        let count = if req.count > 0 { req.count as usize } else { 10 };

        info!(
            "GetPersonalizedRecommendations request: user_id={}, topic_count={}, count={}",
            req.user_id,
            req.available_topics.len(),
            count
        );

        // Parse user ID
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        // Validate input
        if req.available_topics.is_empty() {
            return Err(Status::invalid_argument("available_topics cannot be empty"));
        }

        // Get LLM analyzer
        let analyzer_guard = self.llm_analyzer.read().await;
        let analyzer = analyzer_guard.as_ref().ok_or_else(|| {
            Status::unavailable("LLM analyzer not initialized. Enable LLM in config.")
        })?;

        // Get profile updater
        let updater_guard = self.profile_updater.read().await;
        let updater = updater_guard.as_ref().ok_or_else(|| {
            Status::unavailable("ProfileUpdater not initialized")
        })?;

        // Load profile
        let profile = match updater.load_profile_from_cache(user_id).await {
            Ok(Some(profile)) => profile,
            Ok(None) => {
                return Err(Status::not_found(format!(
                    "Profile not found for user {}. Update profile first.",
                    user_id
                )));
            }
            Err(e) => {
                return Err(Status::internal(format!("Failed to load profile: {}", e)));
            }
        };

        // Generate persona first (cached)
        let persona = analyzer.analyze_profile(&profile).await.map_err(|e| {
            Status::internal(format!("Failed to analyze profile: {}", e))
        })?;

        // Generate recommendations
        match analyzer
            .generate_recommendations(&persona, &req.available_topics, count)
            .await
        {
            Ok(recs) => {
                let recommendations: Vec<ProtoRecommendation> =
                    recs.into_iter().map(to_proto_recommendation).collect();

                info!(
                    user_id = %user_id,
                    count = recommendations.len(),
                    "Personalized recommendations generated"
                );

                Ok(Response::new(GetPersonalizedRecommendationsResponse {
                    recommendations,
                }))
            }
            Err(e) => {
                error!(user_id = %user_id, error = %e, "Failed to generate recommendations");
                Err(Status::internal(format!(
                    "Failed to generate recommendations: {}",
                    e
                )))
            }
        }
    }
}

// Helper: 轉換為 Proto 格式
fn to_proto_ranked_post(post: RankedPost) -> ProtoRankedPost {
    ProtoRankedPost {
        post_id: post.post_id,
        score: post.score,
        recall_source: post.recall_source.as_str().to_string(),
        features: Some(PostFeatures {
            engagement_score: post.features.engagement_score,
            recency_score: post.features.recency_score,
            author_quality_score: post.features.author_quality_score,
            content_quality_score: post.features.content_quality_score,
        }),
    }
}

fn to_proto_recall_stats(stats: RecallStats) -> ProtoRecallStats {
    ProtoRecallStats {
        graph_recall_count: stats.graph_recall_count,
        trending_recall_count: stats.trending_recall_count,
        personalized_recall_count: stats.personalized_recall_count,
        total_candidates: stats.total_candidates,
        final_count: stats.final_count,
    }
}

// ============================================
// Profile Conversion Helpers
// ============================================

use crate::services::profile_builder::{
    BehaviorPattern, ContentRecommendation, InterestTag, UserPersona, UserProfile,
};

/// Convert internal UserProfile to proto format
fn to_proto_profile(profile: UserProfile) -> ProtoProfile {
    ProtoProfile {
        user_id: profile.user_id.to_string(),
        interests: profile.interests.into_iter().map(to_proto_interest).collect(),
        behavior: Some(to_proto_behavior(profile.behavior)),
        created_at: profile.created_at.to_rfc3339(),
        updated_at: profile.updated_at.to_rfc3339(),
    }
}

/// Convert internal InterestTag to proto format
fn to_proto_interest(tag: InterestTag) -> ProtoInterest {
    ProtoInterest {
        tag: tag.tag,
        weight: tag.weight as f32,
        interaction_count: tag.interaction_count as i32,
        last_interaction: tag.last_interaction.to_rfc3339(),
    }
}

/// Convert internal BehaviorPattern to proto format
fn to_proto_behavior(behavior: BehaviorPattern) -> ProtoBehavior {
    ProtoBehavior {
        active_hours_bitmap: behavior.active_hours_bitmap,
        peak_hours: behavior.peak_hours.into_iter().map(|h| h as i32).collect(),
        avg_session_length_seconds: behavior.avg_session_length as f32,
        preferred_video_length: behavior.preferred_video_length.as_str().to_string(),
        engagement_rate: behavior.engagement_rate as f32,
    }
}

/// Convert internal UserPersona to proto format
fn to_proto_persona(persona: UserPersona) -> ProtoPersona {
    ProtoPersona {
        user_id: persona.user_id.to_string(),
        description: persona.description,
        primary_interests: persona.primary_interests,
        consumption_patterns: Some(ProtoConsumption {
            preferred_length: persona.consumption_patterns.preferred_length,
            activity_pattern: persona.consumption_patterns.activity_pattern,
            engagement_style: persona.consumption_patterns.engagement_style,
            discovery_preference: persona.consumption_patterns.discovery_preference,
        }),
        predicted_preferences: Some(ProtoPreferences {
            likely_interests: persona.predicted_preferences.likely_interests,
            disliked_topics: persona.predicted_preferences.disliked_topics,
            optimal_delivery_hours: persona
                .predicted_preferences
                .optimal_delivery_hours
                .into_iter()
                .map(|h| h as i32)
                .collect(),
            format_preferences: persona.predicted_preferences.format_preferences,
        }),
        segment: persona.segment.as_str().to_string(),
        confidence: persona.confidence,
        generated_at: persona.generated_at.to_rfc3339(),
        model_used: persona.model_used,
    }
}

/// Convert internal ContentRecommendation to proto format
fn to_proto_recommendation(rec: ContentRecommendation) -> ProtoRecommendation {
    ProtoRecommendation {
        topic: rec.topic,
        relevance_score: rec.relevance_score,
        reason: rec.reason,
    }
}

/// Extension trait for VideoLengthPreference
trait VideoLengthExt {
    fn as_str(&self) -> &'static str;
}

impl VideoLengthExt for crate::services::profile_builder::VideoLengthPreference {
    fn as_str(&self) -> &'static str {
        use crate::services::profile_builder::VideoLengthPreference;
        match self {
            VideoLengthPreference::VeryShort => "very_short",
            VideoLengthPreference::Short => "short",
            VideoLengthPreference::Medium => "medium",
            VideoLengthPreference::Long => "long",
            VideoLengthPreference::VeryLong => "very_long",
            VideoLengthPreference::Mixed => "mixed",
        }
    }
}
