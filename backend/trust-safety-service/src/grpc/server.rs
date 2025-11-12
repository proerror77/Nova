use crate::config::Config;
use crate::db::ModerationDb;
use crate::models::{AppealStatus, ContentType, RiskScore};
use crate::services::{AppealService, NsfwDetector, SpamContext, SpamDetector, TextModerator};
use std::sync::Arc;
use tonic::{Request, Response, Status};
use uuid::Uuid;

// Include generated proto code
pub mod trust_safety {
    tonic::include_proto!("nova.trust_safety.v1");
}

use trust_safety::trust_safety_service_server::TrustSafetyService;
use trust_safety::*;

/// gRPC service implementation
pub struct TrustSafetyServiceImpl {
    config: Arc<Config>,
    nsfw_detector: Arc<NsfwDetector>,
    text_moderator: Arc<TextModerator>,
    spam_detector: Arc<SpamDetector>,
    appeal_service: Arc<AppealService>,
    moderation_db: Arc<ModerationDb>,
}

impl TrustSafetyServiceImpl {
    pub fn new(
        config: Arc<Config>,
        nsfw_detector: Arc<NsfwDetector>,
        text_moderator: Arc<TextModerator>,
        spam_detector: Arc<SpamDetector>,
        appeal_service: Arc<AppealService>,
        moderation_db: Arc<ModerationDb>,
    ) -> Self {
        Self {
            config,
            nsfw_detector,
            text_moderator,
            spam_detector,
            appeal_service,
            moderation_db,
        }
    }
}

#[tonic::async_trait]
impl TrustSafetyService for TrustSafetyServiceImpl {
    async fn moderate_content(
        &self,
        request: Request<ModerateContentRequest>,
    ) -> Result<Response<ModerateContentResponse>, Status> {
        let req = request.into_inner();

        tracing::info!(
            content_id = %req.content_id,
            content_type = %req.content_type,
            user_id = %req.user_id,
            "Moderating content"
        );

        // 1. Text moderation
        let text_result = self.text_moderator.check(&req.text);
        let toxicity_score = self.text_moderator.calculate_toxicity_score(&req.text);

        // 2. NSFW detection (if images present)
        let mut nsfw_score = 0.0f32;
        let mut nsfw_categories = Vec::new();

        for image_url in &req.image_urls {
            match self.nsfw_detector.detect(image_url).await {
                Ok(score) => {
                    if score > nsfw_score {
                        nsfw_score = score;
                    }
                    if score > self.config.nsfw_threshold {
                        nsfw_categories.push(format!("nsfw_image:{}", image_url));
                    }
                }
                Err(e) => {
                    tracing::warn!("NSFW detection failed for {}: {}", image_url, e);
                    // Continue with other checks
                }
            }
        }

        // 3. Spam detection
        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        // Get user stats from DB
        let (recent_post_count, seconds_since_last) = self
            .moderation_db
            .get_user_post_stats(user_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to get user stats: {}", e)))?;

        // Get recent content for duplicate check
        let recent_content = self
            .moderation_db
            .get_recent_user_content(user_id, 10)
            .await
            .map_err(|e| Status::internal(format!("Failed to get recent content: {}", e)))?;

        let has_repeated_content = self.spam_detector.is_duplicate(&req.text, &recent_content);

        let spam_context = SpamContext {
            has_repeated_content,
            seconds_since_last_post: seconds_since_last.unwrap_or(3600) as u64,
            recent_post_count: recent_post_count as u32,
            account_age_days: req
                .context
                .as_ref()
                .map(|c| c.account_age_days as u64)
                .unwrap_or(365),
            is_verified: req.context.as_ref().map(|c| c.is_verified).unwrap_or(false),
            link_count: 0, // Will be counted by detector
        };

        let spam_score = self.spam_detector.detect(&spam_context, &req.text);

        // 4. Calculate overall risk
        let risk_score = RiskScore::new(nsfw_score, toxicity_score, spam_score);

        // 5. Decision: Auto-approve if below threshold
        let approved = risk_score.overall_score < self.config.overall_threshold;

        // Collect all violations
        let mut violations = Vec::new();
        violations.extend(text_result.violations.clone());
        violations.extend(nsfw_categories.clone());
        if spam_score > self.config.spam_threshold {
            violations.push("spam_detected".to_string());
        }

        // 6. Save moderation log
        let content_type_str = ContentType::from(req.content_type).as_str();
        let moderation_id = self
            .moderation_db
            .save_moderation_log(
                &req.content_id,
                content_type_str,
                user_id,
                nsfw_score,
                toxicity_score,
                spam_score,
                risk_score.overall_score,
                approved,
                violations.clone(),
            )
            .await
            .map_err(|e| Status::internal(format!("Failed to save moderation log: {}", e)))?;

        // 7. Build response
        let rejection_reason = if !approved {
            Some(format!(
                "Content flagged: {} violations detected (overall risk: {:.2})",
                violations.len(),
                risk_score.overall_score
            ))
        } else {
            None
        };

        let response = ModerateContentResponse {
            approved,
            risk_score: Some(trust_safety::RiskScore {
                nsfw_score: nsfw_score as f64,
                toxicity_score: toxicity_score as f64,
                spam_score: spam_score as f64,
                overall_score: risk_score.overall_score as f64,
                nsfw_categories: nsfw_categories.clone(),
                toxic_keywords: text_result.violations,
                spam_indicators: if spam_score > 0.5 {
                    vec!["spam_detected".to_string()]
                } else {
                    Vec::new()
                },
            }),
            violations,
            moderation_id: moderation_id.to_string(),
            rejection_reason: rejection_reason.unwrap_or_default(),
        };

        tracing::info!(
            moderation_id = %moderation_id,
            approved = %approved,
            overall_score = %risk_score.overall_score,
            "Content moderation complete"
        );

        Ok(Response::new(response))
    }

    async fn check_content(
        &self,
        request: Request<CheckContentRequest>,
    ) -> Result<Response<CheckContentResponse>, Status> {
        let req = request.into_inner();

        // Quick checks without saving to DB
        let _text_result = self.text_moderator.check(&req.text);
        let toxicity_score = self.text_moderator.calculate_toxicity_score(&req.text);

        let mut nsfw_score = 0.0f32;
        for image_url in &req.image_urls {
            if let Ok(score) = self.nsfw_detector.detect(image_url).await {
                nsfw_score = nsfw_score.max(score);
            }
        }

        let overall_score = (nsfw_score + toxicity_score) / 2.0;
        let is_safe = overall_score < self.config.overall_threshold;

        let mut flags = Vec::new();
        if nsfw_score > self.config.nsfw_threshold {
            flags.push("nsfw".to_string());
        }
        if toxicity_score > self.config.toxicity_threshold {
            flags.push("toxic".to_string());
        }

        Ok(Response::new(CheckContentResponse {
            is_safe,
            overall_score: overall_score as f64,
            flags,
        }))
    }

    async fn submit_appeal(
        &self,
        request: Request<SubmitAppealRequest>,
    ) -> Result<Response<SubmitAppealResponse>, Status> {
        let req = request.into_inner();

        let moderation_id = Uuid::parse_str(&req.moderation_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid moderation_id: {}", e)))?;

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let appeal = self
            .appeal_service
            .submit_appeal(moderation_id, user_id, &req.reason)
            .await
            .map_err(Status::from)?;

        Ok(Response::new(SubmitAppealResponse {
            appeal_id: appeal.id.to_string(),
            status: AppealStatus::Pending as i32,
            created_at: appeal.created_at.to_rfc3339(),
        }))
    }

    async fn review_appeal(
        &self,
        request: Request<ReviewAppealRequest>,
    ) -> Result<Response<ReviewAppealResponse>, Status> {
        let req = request.into_inner();

        let appeal_id = Uuid::parse_str(&req.appeal_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid appeal_id: {}", e)))?;

        let admin_id = Uuid::parse_str(&req.admin_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid admin_id: {}", e)))?;

        // Convert proto enum to domain enum
        let decision = match AppealDecision::try_from(req.decision) {
            Ok(AppealDecision::Approve) => AppealStatus::Approved,
            Ok(AppealDecision::Reject) => AppealStatus::Rejected,
            _ => {
                return Err(Status::invalid_argument("Invalid appeal decision"));
            }
        };

        let admin_note = if req.admin_note.is_empty() {
            None
        } else {
            Some(req.admin_note.as_str())
        };

        let appeal = self
            .appeal_service
            .review_appeal(appeal_id, admin_id, decision, admin_note)
            .await
            .map_err(Status::from)?;

        Ok(Response::new(ReviewAppealResponse {
            appeal_id: appeal.id.to_string(),
            status: decision as i32,
            reviewed_at: appeal
                .reviewed_at
                .map(|dt| dt.to_rfc3339())
                .unwrap_or_default(),
        }))
    }

    async fn get_moderation_history(
        &self,
        request: Request<GetModerationHistoryRequest>,
    ) -> Result<Response<GetModerationHistoryResponse>, Status> {
        let req = request.into_inner();

        let limit = if req.limit > 0 { req.limit } else { 50 };
        let offset = if req.offset >= 0 { req.offset } else { 0 };

        let logs = if !req.user_id.is_empty() {
            let user_id = Uuid::parse_str(&req.user_id)
                .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

            self.moderation_db
                .get_user_moderation_history(user_id, limit as i64, offset as i64)
                .await
                .map_err(|e| Status::internal(format!("Failed to get history: {}", e)))?
        } else if !req.content_id.is_empty() {
            self.moderation_db
                .get_content_moderation_history(&req.content_id, limit as i64, offset as i64)
                .await
                .map_err(|e| Status::internal(format!("Failed to get history: {}", e)))?
        } else {
            return Err(Status::invalid_argument(
                "Either user_id or content_id must be provided",
            ));
        };

        let user_id =
            if !req.user_id.is_empty() {
                Some(Uuid::parse_str(&req.user_id).map_err(|e| {
                    Status::invalid_argument(format!("Invalid user_id UUID: {}", e))
                })?)
            } else {
                None
            };

        let total_count = self
            .moderation_db
            .count_moderation_logs(
                user_id,
                if !req.content_id.is_empty() {
                    Some(&req.content_id)
                } else {
                    None
                },
            )
            .await
            .map_err(|e| Status::internal(format!("Failed to count logs: {}", e)))?;

        let moderation_logs = logs
            .into_iter()
            .map(|log| ModerationLog {
                id: log.id.to_string(),
                content_id: log.content_id,
                content_type: log.content_type,
                user_id: log.user_id.to_string(),
                risk_score: Some(trust_safety::RiskScore {
                    nsfw_score: log.nsfw_score as f64,
                    toxicity_score: log.toxicity_score as f64,
                    spam_score: log.spam_score as f64,
                    overall_score: log.overall_score as f64,
                    nsfw_categories: Vec::new(),
                    toxic_keywords: Vec::new(),
                    spam_indicators: Vec::new(),
                }),
                approved: log.approved,
                rejection_reason: if log.approved {
                    String::new()
                } else {
                    format!("Risk score: {:.2}", log.overall_score)
                },
                created_at: log.created_at.to_rfc3339(),
            })
            .collect();

        Ok(Response::new(GetModerationHistoryResponse {
            logs: moderation_logs,
            total_count: total_count as i32,
        }))
    }
}
