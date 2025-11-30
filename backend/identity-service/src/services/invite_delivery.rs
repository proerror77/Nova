/// Invite delivery service for sending invitations via SMS, Email, or Link
///
/// Supports:
/// - SMS via AWS SNS
/// - Email via existing EmailService
/// - Link generation with Firebase Dynamic Links
use crate::db::invitations::{self, InviteCode};
use crate::error::{IdentityError, Result};
use crate::services::EmailService;
use aws_sdk_sns::Client as SnsClient;
use sqlx::PgPool;

/// Configuration for invite delivery
#[derive(Debug, Clone)]
pub struct InviteDeliveryConfig {
    /// Firebase Dynamic Links domain (e.g., "nova.page.link")
    pub firebase_domain: String,
    /// iOS bundle ID
    pub ios_bundle_id: String,
    /// Android package name
    pub android_package_name: String,
    /// Fallback URL for web browsers
    pub fallback_url: String,
    /// Firebase API key for Dynamic Links
    pub firebase_api_key: String,
    /// App name for share messages
    pub app_name: String,
}

impl Default for InviteDeliveryConfig {
    fn default() -> Self {
        Self {
            firebase_domain: std::env::var("FIREBASE_DYNAMIC_LINKS_DOMAIN")
                .unwrap_or_else(|_| "nova.page.link".to_string()),
            ios_bundle_id: std::env::var("IOS_BUNDLE_ID")
                .unwrap_or_else(|_| "social.nova.app".to_string()),
            android_package_name: std::env::var("ANDROID_PACKAGE_NAME")
                .unwrap_or_else(|_| "social.nova.app".to_string()),
            fallback_url: std::env::var("INVITE_FALLBACK_URL")
                .unwrap_or_else(|_| "https://nova.social/invite".to_string()),
            firebase_api_key: std::env::var("FIREBASE_API_KEY").unwrap_or_default(),
            app_name: "Nova".to_string(),
        }
    }
}

/// Invite delivery service
pub struct InviteDeliveryService {
    db: PgPool,
    sns_client: Option<SnsClient>,
    email_service: EmailService,
    config: InviteDeliveryConfig,
}

/// Result of sending an invite
#[derive(Debug, Clone)]
pub struct SendInviteResult {
    pub success: bool,
    pub invite_code: String,
    pub invite_url: String,
    pub share_text: String,
    pub delivery_id: Option<String>,
    pub error: Option<String>,
}

impl InviteDeliveryService {
    pub fn new(
        db: PgPool,
        sns_client: Option<SnsClient>,
        email_service: EmailService,
        config: InviteDeliveryConfig,
    ) -> Self {
        Self {
            db,
            sns_client,
            email_service,
            config,
        }
    }

    /// Generate Firebase Dynamic Link for an invite code
    pub fn generate_invite_url(&self, code: &str) -> String {
        // Short link format: https://nova.page.link/invite?code=XXXXX
        // This will redirect to app with deep link or fallback to web
        let deep_link = format!("{}?code={}", self.config.fallback_url, code);

        // For production, you'd use Firebase Dynamic Links REST API to create short links
        // For now, use manual URL construction
        let encoded_link = urlencoding::encode(&deep_link);
        format!(
            "https://{}/invite?link={}&apn={}&ibi={}",
            self.config.firebase_domain,
            encoded_link,
            self.config.android_package_name,
            self.config.ios_bundle_id
        )
    }

    /// Generate share text for the invite
    pub fn generate_share_text(&self, code: &str, inviter_name: Option<&str>) -> String {
        let url = self.generate_invite_url(code);
        match inviter_name {
            Some(name) => format!(
                "{} invited you to join {}! Use code {} or click: {}",
                name, self.config.app_name, code, url
            ),
            None => format!(
                "You've been invited to join {}! Use code {} or click: {}",
                self.config.app_name, code, url
            ),
        }
    }

    /// Send invite via the specified channel
    pub async fn send_invite(
        &self,
        invite: &InviteCode,
        channel: &str,
        recipient: Option<&str>,
        inviter_name: Option<&str>,
        custom_message: Option<&str>,
    ) -> Result<SendInviteResult> {
        let invite_url = self.generate_invite_url(&invite.code);
        let share_text = custom_message
            .map(|m| format!("{}\n\n{}", m, invite_url))
            .unwrap_or_else(|| self.generate_share_text(&invite.code, inviter_name));

        match channel {
            "sms" => self.send_sms(invite, recipient, &share_text).await,
            "email" => {
                self.send_email(invite, recipient, inviter_name, &invite_url)
                    .await
            }
            "link" => {
                // Just generate link, record delivery
                let delivery = invitations::record_invite_delivery(
                    &self.db,
                    invite.id,
                    "link",
                    None,
                    None,
                )
                .await?;

                Ok(SendInviteResult {
                    success: true,
                    invite_code: invite.code.clone(),
                    invite_url,
                    share_text,
                    delivery_id: Some(delivery.id.to_string()),
                    error: None,
                })
            }
            _ => Err(IdentityError::Validation(format!(
                "Unknown channel: {}. Use 'sms', 'email', or 'link'",
                channel
            ))),
        }
    }

    /// Send invite via SMS using AWS SNS
    async fn send_sms(
        &self,
        invite: &InviteCode,
        recipient: Option<&str>,
        message: &str,
    ) -> Result<SendInviteResult> {
        let phone = recipient.ok_or_else(|| {
            IdentityError::Validation("Phone number required for SMS".into())
        })?;

        // Validate phone format (basic check)
        if !phone.starts_with('+') || phone.len() < 10 {
            return Err(IdentityError::Validation(
                "Phone number must be in E.164 format (e.g., +14155551234)".into(),
            ));
        }

        let sns = self.sns_client.as_ref().ok_or_else(|| {
            IdentityError::Internal("SMS service not configured".into())
        })?;

        // Send SMS via AWS SNS
        let result = sns
            .publish()
            .phone_number(phone)
            .message(message)
            .message_attributes(
                "AWS.SNS.SMS.SMSType",
                aws_sdk_sns::types::MessageAttributeValue::builder()
                    .data_type("String")
                    .string_value("Transactional")
                    .build()
                    .map_err(|e| IdentityError::Internal(e.to_string()))?,
            )
            .send()
            .await;

        match result {
            Ok(output) => {
                let message_id = output.message_id().unwrap_or_default().to_string();

                // Record delivery
                let delivery = invitations::record_invite_delivery(
                    &self.db,
                    invite.id,
                    "sms",
                    Some(phone),
                    Some(&message_id),
                )
                .await?;

                Ok(SendInviteResult {
                    success: true,
                    invite_code: invite.code.clone(),
                    invite_url: self.generate_invite_url(&invite.code),
                    share_text: message.to_string(),
                    delivery_id: Some(delivery.id.to_string()),
                    error: None,
                })
            }
            Err(e) => {
                // Record failed delivery
                let delivery = invitations::record_invite_delivery(
                    &self.db,
                    invite.id,
                    "sms",
                    Some(phone),
                    None,
                )
                .await?;

                invitations::update_delivery_status(
                    &self.db,
                    delivery.id,
                    "failed",
                    Some(&e.to_string()),
                )
                .await?;

                Ok(SendInviteResult {
                    success: false,
                    invite_code: invite.code.clone(),
                    invite_url: self.generate_invite_url(&invite.code),
                    share_text: message.to_string(),
                    delivery_id: Some(delivery.id.to_string()),
                    error: Some(format!("SMS delivery failed: {}", e)),
                })
            }
        }
    }

    /// Send invite via Email
    async fn send_email(
        &self,
        invite: &InviteCode,
        recipient: Option<&str>,
        inviter_name: Option<&str>,
        invite_url: &str,
    ) -> Result<SendInviteResult> {
        let email = recipient.ok_or_else(|| {
            IdentityError::Validation("Email address required".into())
        })?;

        let subject = match inviter_name {
            Some(name) => format!("{} invited you to join Nova!", name),
            None => "You've been invited to join Nova!".to_string(),
        };

        let html_body = self.generate_email_html(invite, inviter_name, invite_url);
        let text_body = self.generate_share_text(&invite.code, inviter_name);

        // Send via email service
        let send_result = self
            .email_service
            .send_html_email(email, &subject, &html_body, &text_body)
            .await;

        match send_result {
            Ok(_) => {
                let delivery = invitations::record_invite_delivery(
                    &self.db,
                    invite.id,
                    "email",
                    Some(email),
                    None,
                )
                .await?;

                Ok(SendInviteResult {
                    success: true,
                    invite_code: invite.code.clone(),
                    invite_url: invite_url.to_string(),
                    share_text: text_body,
                    delivery_id: Some(delivery.id.to_string()),
                    error: None,
                })
            }
            Err(e) => {
                let delivery = invitations::record_invite_delivery(
                    &self.db,
                    invite.id,
                    "email",
                    Some(email),
                    None,
                )
                .await?;

                invitations::update_delivery_status(
                    &self.db,
                    delivery.id,
                    "failed",
                    Some(&e.to_string()),
                )
                .await?;

                Ok(SendInviteResult {
                    success: false,
                    invite_code: invite.code.clone(),
                    invite_url: invite_url.to_string(),
                    share_text: text_body,
                    delivery_id: Some(delivery.id.to_string()),
                    error: Some(format!("Email delivery failed: {}", e)),
                })
            }
        }
    }

    /// Generate HTML email body for invite
    fn generate_email_html(
        &self,
        invite: &InviteCode,
        inviter_name: Option<&str>,
        invite_url: &str,
    ) -> String {
        let header = match inviter_name {
            Some(name) => format!("{} invited you to join Nova!", name),
            None => "You've been invited to join Nova!".to_string(),
        };

        format!(
            r#"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Join Nova</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #f5f5f5; margin: 0; padding: 20px;">
    <div style="max-width: 600px; margin: 0 auto; background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1);">
        <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 40px 20px; text-align: center;">
            <h1 style="color: white; margin: 0; font-size: 28px;">{}</h1>
        </div>
        <div style="padding: 40px 30px; text-align: center;">
            <p style="font-size: 16px; color: #333; line-height: 1.6;">
                Nova is an exclusive social platform where creative minds connect.
                You've received a special invitation to join our community.
            </p>
            <div style="background: #f8f9fa; border-radius: 8px; padding: 20px; margin: 30px 0;">
                <p style="font-size: 14px; color: #666; margin: 0 0 10px 0;">Your invite code:</p>
                <p style="font-size: 32px; font-weight: bold; color: #667eea; margin: 0; letter-spacing: 4px;">{}</p>
            </div>
            <a href="{}" style="display: inline-block; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; text-decoration: none; padding: 16px 40px; border-radius: 30px; font-size: 16px; font-weight: 600;">
                Join Nova Now
            </a>
            <p style="font-size: 12px; color: #999; margin-top: 30px;">
                This invitation expires in 30 days. Share responsibly - you have limited invites!
            </p>
        </div>
    </div>
</body>
</html>
"#,
            header, invite.code, invite_url
        )
    }
}
