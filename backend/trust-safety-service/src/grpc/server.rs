use crate::config::Config;
use crate::db::{BansDb, ModerationDb, ReportsDb, WarningsDb};
use crate::models::enforcement::{CreateBanInput, CreateReportInput, CreateWarningInput};
use crate::models::{AppealStatus, ContentType, RiskScore};
use crate::services::{AppealService, NsfwDetector, SpamContext, SpamDetector, TextModerator};
use std::sync::Arc;
use tonic::{Request, Response, Status};
use uuid::Uuid;

// Include generated proto code
pub mod trust_safety {
    tonic::include_proto!("nova.trust_safety.v2");
}

use trust_safety::trust_safety_service_server::TrustSafetyService;
use trust_safety::*;

/// gRPC service implementation
pub struct TrustSafetyServiceImpl {
    config: Arc<Config>,
    nsfw_detector: Option<Arc<NsfwDetector>>,
    text_moderator: Arc<TextModerator>,
    spam_detector: Arc<SpamDetector>,
    appeal_service: Arc<AppealService>,
    moderation_db: Arc<ModerationDb>,
    // P0: Enforcement DBs
    reports_db: Arc<ReportsDb>,
    warnings_db: Arc<WarningsDb>,
    bans_db: Arc<BansDb>,
}

impl TrustSafetyServiceImpl {
    pub fn new(
        config: Arc<Config>,
        nsfw_detector: Option<Arc<NsfwDetector>>,
        text_moderator: Arc<TextModerator>,
        spam_detector: Arc<SpamDetector>,
        appeal_service: Arc<AppealService>,
        moderation_db: Arc<ModerationDb>,
        reports_db: Arc<ReportsDb>,
        warnings_db: Arc<WarningsDb>,
        bans_db: Arc<BansDb>,
    ) -> Self {
        Self {
            config,
            nsfw_detector,
            text_moderator,
            spam_detector,
            appeal_service,
            moderation_db,
            reports_db,
            warnings_db,
            bans_db,
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

        if let Some(detector) = &self.nsfw_detector {
            for image_url in &req.image_urls {
                match detector.detect(image_url).await {
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
        if let Some(detector) = &self.nsfw_detector {
            for image_url in &req.image_urls {
                if let Ok(score) = detector.detect(image_url).await {
                    nsfw_score = nsfw_score.max(score);
                }
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

    // ==================== P0: User Reports ====================

    async fn submit_report(
        &self,
        request: Request<SubmitReportRequest>,
    ) -> Result<Response<SubmitReportResponse>, Status> {
        let req = request.into_inner();

        let reporter_id = Uuid::parse_str(&req.reporter_user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid reporter_user_id: {}", e)))?;

        let reported_user_id = if !req.reported_user_id.is_empty() {
            Some(Uuid::parse_str(&req.reported_user_id).map_err(|e| {
                Status::invalid_argument(format!("Invalid reported_user_id: {}", e))
            })?)
        } else {
            None
        };

        let input = CreateReportInput {
            reporter_user_id: reporter_id,
            reported_user_id,
            reported_content_id: if req.reported_content_id.is_empty() {
                None
            } else {
                Some(req.reported_content_id.clone())
            },
            reported_content_type: if req.reported_content_type.is_empty() {
                None
            } else {
                Some(req.reported_content_type.clone())
            },
            report_type: report_type_to_string(req.report_type),
            description: if req.description.is_empty() {
                None
            } else {
                Some(req.description.clone())
            },
        };

        let report = self
            .reports_db
            .create_report(input)
            .await
            .map_err(|e| Status::internal(format!("Failed to create report: {}", e)))?;

        Ok(Response::new(SubmitReportResponse {
            report_id: report.id.to_string(),
            status: ReportStatus::ReportPending as i32,
            created_at: report.created_at.to_rfc3339(),
        }))
    }

    async fn get_user_reports(
        &self,
        request: Request<GetUserReportsRequest>,
    ) -> Result<Response<GetUserReportsResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let limit = if req.limit > 0 { req.limit as i64 } else { 50 };
        let offset = req.offset as i64;
        let status_filter = if req.status != 0 {
            Some(report_status_to_string(req.status))
        } else {
            None
        };

        let reports = self
            .reports_db
            .get_reports_by_reporter(user_id, status_filter.as_deref(), limit, offset)
            .await
            .map_err(|e| Status::internal(format!("Failed to get reports: {}", e)))?;

        let total_count = self
            .reports_db
            .count_reports_by_reporter(user_id, status_filter.as_deref())
            .await
            .map_err(|e| Status::internal(format!("Failed to count reports: {}", e)))?;

        let proto_reports: Vec<trust_safety::UserReport> = reports
            .into_iter()
            .map(|r| trust_safety::UserReport {
                id: r.id.to_string(),
                reporter_user_id: r.reporter_user_id.to_string(),
                reported_user_id: r.reported_user_id.map(|id| id.to_string()).unwrap_or_default(),
                reported_content_id: r.reported_content_id.unwrap_or_default(),
                reported_content_type: r.reported_content_type.unwrap_or_default(),
                report_type: string_to_report_type(&r.report_type),
                description: r.description.unwrap_or_default(),
                status: string_to_report_status(&r.status),
                resolution: r.resolution.unwrap_or_default(),
                created_at: r.created_at.to_rfc3339(),
                reviewed_at: r.reviewed_at.map(|dt| dt.to_rfc3339()).unwrap_or_default(),
            })
            .collect();

        Ok(Response::new(GetUserReportsResponse {
            reports: proto_reports,
            total_count: total_count as i32,
        }))
    }

    async fn review_report(
        &self,
        request: Request<ReviewReportRequest>,
    ) -> Result<Response<ReviewReportResponse>, Status> {
        let req = request.into_inner();

        let report_id = Uuid::parse_str(&req.report_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid report_id: {}", e)))?;

        let admin_id = Uuid::parse_str(&req.admin_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid admin_id: {}", e)))?;

        let resolution = resolution_to_string(req.resolution);
        let status = match req.resolution {
            x if x == ReportResolution::NoAction as i32 => "dismissed",
            _ => "actioned",
        };

        let report = self
            .reports_db
            .review_report(report_id, admin_id, &resolution, status)
            .await
            .map_err(|e| Status::internal(format!("Failed to review report: {}", e)))?;

        Ok(Response::new(ReviewReportResponse {
            report_id: report.id.to_string(),
            status: string_to_report_status(&report.status),
            reviewed_at: report
                .reviewed_at
                .map(|dt| dt.to_rfc3339())
                .unwrap_or_default(),
        }))
    }

    // ==================== P0: User Warnings ====================

    async fn issue_warning(
        &self,
        request: Request<IssueWarningRequest>,
    ) -> Result<Response<IssueWarningResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let issued_by = Uuid::parse_str(&req.issued_by)
            .map_err(|e| Status::invalid_argument(format!("Invalid issued_by: {}", e)))?;

        let moderation_log_id = if !req.moderation_log_id.is_empty() {
            Some(Uuid::parse_str(&req.moderation_log_id).map_err(|e| {
                Status::invalid_argument(format!("Invalid moderation_log_id: {}", e))
            })?)
        } else {
            None
        };

        let report_id = if !req.report_id.is_empty() {
            Some(Uuid::parse_str(&req.report_id).map_err(|e| {
                Status::invalid_argument(format!("Invalid report_id: {}", e))
            })?)
        } else {
            None
        };

        let input = CreateWarningInput {
            user_id,
            warning_type: warning_type_to_string(req.warning_type),
            severity: severity_to_string(req.severity),
            strike_points: req.strike_points,
            reason: req.reason.clone(),
            moderation_log_id,
            report_id,
            issued_by,
            expires_in_days: if req.expires_in_days > 0 {
                Some(req.expires_in_days)
            } else {
                None
            },
        };

        let warning = self
            .warnings_db
            .create_warning(input)
            .await
            .map_err(|e| Status::internal(format!("Failed to create warning: {}", e)))?;

        let total_strike_points = self
            .warnings_db
            .get_total_strike_points(user_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to get strike points: {}", e)))?;

        // Check if auto-ban should be triggered (threshold: 10 points)
        let auto_ban_triggered = self
            .warnings_db
            .should_auto_ban(user_id, 10)
            .await
            .map_err(|e| Status::internal(format!("Failed to check auto-ban: {}", e)))?;

        Ok(Response::new(IssueWarningResponse {
            warning_id: warning.id.to_string(),
            total_strike_points,
            auto_ban_triggered,
        }))
    }

    async fn get_user_warnings(
        &self,
        request: Request<GetUserWarningsRequest>,
    ) -> Result<Response<GetUserWarningsResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let limit = if req.limit > 0 { req.limit as i64 } else { 50 };
        let offset = req.offset as i64;

        let warnings = self
            .warnings_db
            .get_user_warnings(user_id, req.active_only, limit, offset)
            .await
            .map_err(|e| Status::internal(format!("Failed to get warnings: {}", e)))?;

        let total_strike_points = self
            .warnings_db
            .get_total_strike_points(user_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to get strike points: {}", e)))?;

        let total_count = self
            .warnings_db
            .count_user_warnings(user_id, req.active_only)
            .await
            .map_err(|e| Status::internal(format!("Failed to count warnings: {}", e)))?;

        let proto_warnings: Vec<trust_safety::UserWarning> = warnings
            .into_iter()
            .map(|w| trust_safety::UserWarning {
                id: w.id.to_string(),
                user_id: w.user_id.to_string(),
                warning_type: string_to_warning_type(&w.warning_type),
                severity: string_to_severity(&w.severity),
                strike_points: w.strike_points,
                reason: w.reason,
                acknowledged: w.acknowledged,
                expires_at: w.expires_at.map(|dt| dt.to_rfc3339()).unwrap_or_default(),
                created_at: w.created_at.to_rfc3339(),
            })
            .collect();

        Ok(Response::new(GetUserWarningsResponse {
            warnings: proto_warnings,
            total_strike_points,
            total_count: total_count as i32,
        }))
    }

    async fn acknowledge_warning(
        &self,
        request: Request<AcknowledgeWarningRequest>,
    ) -> Result<Response<AcknowledgeWarningResponse>, Status> {
        let req = request.into_inner();

        let warning_id = Uuid::parse_str(&req.warning_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid warning_id: {}", e)))?;

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let success = self
            .warnings_db
            .acknowledge_warning(warning_id, user_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to acknowledge warning: {}", e)))?;

        Ok(Response::new(AcknowledgeWarningResponse { success }))
    }

    // ==================== P0: User Bans ====================

    async fn ban_user(
        &self,
        request: Request<BanUserRequest>,
    ) -> Result<Response<BanUserResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let banned_by = Uuid::parse_str(&req.banned_by)
            .map_err(|e| Status::invalid_argument(format!("Invalid banned_by: {}", e)))?;

        let warning_id = if !req.warning_id.is_empty() {
            Some(Uuid::parse_str(&req.warning_id).map_err(|e| {
                Status::invalid_argument(format!("Invalid warning_id: {}", e))
            })?)
        } else {
            None
        };

        let report_id = if !req.report_id.is_empty() {
            Some(Uuid::parse_str(&req.report_id).map_err(|e| {
                Status::invalid_argument(format!("Invalid report_id: {}", e))
            })?)
        } else {
            None
        };

        let input = CreateBanInput {
            user_id,
            ban_type: ban_type_to_string(req.ban_type),
            reason: req.reason.clone(),
            banned_by,
            warning_id,
            report_id,
            duration_hours: if req.duration_hours > 0 {
                Some(req.duration_hours)
            } else {
                None
            },
        };

        let ban = self
            .bans_db
            .create_ban(input)
            .await
            .map_err(|e| Status::internal(format!("Failed to create ban: {}", e)))?;

        Ok(Response::new(BanUserResponse {
            ban_id: ban.id.to_string(),
            ends_at: ban.ends_at.map(|dt| dt.to_rfc3339()).unwrap_or_default(),
            success: true,
        }))
    }

    async fn lift_ban(
        &self,
        request: Request<LiftBanRequest>,
    ) -> Result<Response<LiftBanResponse>, Status> {
        let req = request.into_inner();

        let ban_id = Uuid::parse_str(&req.ban_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid ban_id: {}", e)))?;

        let lifted_by = Uuid::parse_str(&req.lifted_by)
            .map_err(|e| Status::invalid_argument(format!("Invalid lifted_by: {}", e)))?;

        self.bans_db
            .lift_ban(ban_id, lifted_by, &req.lift_reason)
            .await
            .map_err(|e| Status::internal(format!("Failed to lift ban: {}", e)))?;

        Ok(Response::new(LiftBanResponse { success: true }))
    }

    async fn check_user_ban(
        &self,
        request: Request<CheckUserBanRequest>,
    ) -> Result<Response<CheckUserBanResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let is_banned = self
            .bans_db
            .is_user_banned(user_id)
            .await
            .map_err(|e| Status::internal(format!("Failed to check ban status: {}", e)))?;

        let active_ban = if is_banned {
            self.bans_db
                .get_active_ban(user_id)
                .await
                .map_err(|e| Status::internal(format!("Failed to get active ban: {}", e)))?
                .map(|b| trust_safety::UserBan {
                    id: b.id.to_string(),
                    user_id: b.user_id.to_string(),
                    ban_type: string_to_ban_type(&b.ban_type),
                    reason: b.reason,
                    banned_by: b.banned_by.to_string(),
                    starts_at: b.starts_at.to_rfc3339(),
                    ends_at: b.ends_at.map(|dt| dt.to_rfc3339()).unwrap_or_default(),
                    lifted_at: b.lifted_at.map(|dt| dt.to_rfc3339()).unwrap_or_default(),
                    lift_reason: b.lift_reason.unwrap_or_default(),
                    created_at: b.created_at.to_rfc3339(),
                })
        } else {
            None
        };

        Ok(Response::new(CheckUserBanResponse {
            is_banned,
            active_ban,
        }))
    }

    async fn get_user_bans(
        &self,
        request: Request<GetUserBansRequest>,
    ) -> Result<Response<GetUserBansResponse>, Status> {
        let req = request.into_inner();

        let user_id = Uuid::parse_str(&req.user_id)
            .map_err(|e| Status::invalid_argument(format!("Invalid user_id: {}", e)))?;

        let limit = if req.limit > 0 { req.limit as i64 } else { 50 };
        let offset = req.offset as i64;

        let bans = self
            .bans_db
            .get_user_bans(user_id, req.active_only, limit, offset)
            .await
            .map_err(|e| Status::internal(format!("Failed to get bans: {}", e)))?;

        let total_count = self
            .bans_db
            .count_user_bans(user_id, req.active_only)
            .await
            .map_err(|e| Status::internal(format!("Failed to count bans: {}", e)))?;

        let proto_bans: Vec<trust_safety::UserBan> = bans
            .into_iter()
            .map(|b| trust_safety::UserBan {
                id: b.id.to_string(),
                user_id: b.user_id.to_string(),
                ban_type: string_to_ban_type(&b.ban_type),
                reason: b.reason,
                banned_by: b.banned_by.to_string(),
                starts_at: b.starts_at.to_rfc3339(),
                ends_at: b.ends_at.map(|dt| dt.to_rfc3339()).unwrap_or_default(),
                lifted_at: b.lifted_at.map(|dt| dt.to_rfc3339()).unwrap_or_default(),
                lift_reason: b.lift_reason.unwrap_or_default(),
                created_at: b.created_at.to_rfc3339(),
            })
            .collect();

        Ok(Response::new(GetUserBansResponse {
            bans: proto_bans,
            total_count: total_count as i32,
        }))
    }
}

// ==================== Helper Functions ====================

fn report_type_to_string(t: i32) -> String {
    match ReportType::try_from(t) {
        Ok(ReportType::Spam) => "spam",
        Ok(ReportType::Harassment) => "harassment",
        Ok(ReportType::HateSpeech) => "hate_speech",
        Ok(ReportType::NsfwContent) => "nsfw",
        Ok(ReportType::Impersonation) => "impersonation",
        Ok(ReportType::Violence) => "violence",
        Ok(ReportType::Misinformation) => "misinformation",
        Ok(ReportType::Other) | _ => "other",
    }
    .to_string()
}

fn string_to_report_type(s: &str) -> i32 {
    match s {
        "spam" => ReportType::Spam as i32,
        "harassment" => ReportType::Harassment as i32,
        "hate_speech" => ReportType::HateSpeech as i32,
        "nsfw" => ReportType::NsfwContent as i32,
        "impersonation" => ReportType::Impersonation as i32,
        "violence" => ReportType::Violence as i32,
        "misinformation" => ReportType::Misinformation as i32,
        _ => ReportType::Other as i32,
    }
}

fn report_status_to_string(s: i32) -> String {
    match ReportStatus::try_from(s) {
        Ok(ReportStatus::ReportPending) => "pending",
        Ok(ReportStatus::ReportReviewed) => "reviewed",
        Ok(ReportStatus::ReportActioned) => "actioned",
        Ok(ReportStatus::ReportDismissed) => "dismissed",
        _ => "pending",
    }
    .to_string()
}

fn string_to_report_status(s: &str) -> i32 {
    match s {
        "pending" => ReportStatus::ReportPending as i32,
        "reviewed" => ReportStatus::ReportReviewed as i32,
        "actioned" => ReportStatus::ReportActioned as i32,
        "dismissed" => ReportStatus::ReportDismissed as i32,
        _ => ReportStatus::ReportPending as i32,
    }
}

fn resolution_to_string(r: i32) -> String {
    match ReportResolution::try_from(r) {
        Ok(ReportResolution::WarningIssued) => "warning_issued",
        Ok(ReportResolution::ContentRemoved) => "content_removed",
        Ok(ReportResolution::UserBanned) => "user_banned",
        Ok(ReportResolution::NoAction) => "no_action",
        _ => "unspecified",
    }
    .to_string()
}

fn warning_type_to_string(t: i32) -> String {
    match WarningType::try_from(t) {
        Ok(WarningType::ContentViolation) => "content_violation",
        Ok(WarningType::SpamViolation) => "spam",
        Ok(WarningType::HarassmentViolation) => "harassment",
        Ok(WarningType::TosViolation) => "tos_violation",
        Ok(WarningType::CommunityGuidelines) => "community_guidelines",
        _ => "content_violation",
    }
    .to_string()
}

fn string_to_warning_type(s: &str) -> i32 {
    match s {
        "content_violation" => WarningType::ContentViolation as i32,
        "spam" => WarningType::SpamViolation as i32,
        "harassment" => WarningType::HarassmentViolation as i32,
        "tos_violation" => WarningType::TosViolation as i32,
        "community_guidelines" => WarningType::CommunityGuidelines as i32,
        _ => WarningType::ContentViolation as i32,
    }
}

fn severity_to_string(s: i32) -> String {
    match WarningSeverity::try_from(s) {
        Ok(WarningSeverity::Mild) => "mild",
        Ok(WarningSeverity::Moderate) => "moderate",
        Ok(WarningSeverity::Severe) => "severe",
        _ => "mild",
    }
    .to_string()
}

fn string_to_severity(s: &str) -> i32 {
    match s {
        "mild" => WarningSeverity::Mild as i32,
        "moderate" => WarningSeverity::Moderate as i32,
        "severe" => WarningSeverity::Severe as i32,
        _ => WarningSeverity::Mild as i32,
    }
}

fn ban_type_to_string(t: i32) -> String {
    match BanType::try_from(t) {
        Ok(BanType::Temporary) => "temporary",
        Ok(BanType::Permanent) => "permanent",
        Ok(BanType::Shadow) => "shadow",
        _ => "temporary",
    }
    .to_string()
}

fn string_to_ban_type(s: &str) -> i32 {
    match s {
        "temporary" => BanType::Temporary as i32,
        "permanent" => BanType::Permanent as i32,
        "shadow" => BanType::Shadow as i32,
        _ => BanType::Temporary as i32,
    }
}
