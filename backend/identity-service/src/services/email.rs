/// Email service for sending verification and password reset emails
use crate::config::EmailSettings;
use crate::error::{IdentityError, Result};
use lettre::message::{header, Mailbox, Message};
use lettre::transport::smtp::authentication::Credentials;
use lettre::{AsyncSmtpTransport, AsyncTransport, Tokio1Executor};
use rand::{distributions::Alphanumeric, Rng};
use std::sync::Arc;
use tracing::{info, warn};

/// Async email transport wrapper (SMTP or no-op)
#[derive(Clone)]
pub struct EmailService {
    transport: Option<Arc<AsyncSmtpTransport<Tokio1Executor>>>,
    from: Mailbox,
    verification_base_url: Option<String>,
    password_reset_base_url: Option<String>,
}

impl EmailService {
    /// Build email service from configuration
    ///
    /// If SMTP host is empty, operates in no-op mode (logs only).
    /// Useful for development and testing without email infrastructure.
    pub fn new(config: &EmailSettings) -> Result<Self> {
        let from = config
            .smtp_from
            .parse::<Mailbox>()
            .map_err(|e| IdentityError::Internal(format!("Invalid SMTP_FROM address: {}", e)))?;

        let transport = if config.smtp_host.trim().is_empty() {
            warn!("SMTP host not configured; email service will operate in no-op mode");
            None
        } else {
            let builder = if config.use_starttls {
                AsyncSmtpTransport::<Tokio1Executor>::starttls_relay(&config.smtp_host)
            } else {
                AsyncSmtpTransport::<Tokio1Executor>::relay(&config.smtp_host)
            }
            .map_err(|e| {
                IdentityError::Internal(format!("Failed to configure SMTP transport: {}", e))
            })?
            .port(config.smtp_port);

            let builder = if let (Some(username), Some(password)) =
                (&config.smtp_username, &config.smtp_password)
            {
                builder.credentials(Credentials::new(username.to_string(), password.to_string()))
            } else {
                builder
            };

            let transport = builder.build();
            Some(Arc::new(transport))
        };

        Ok(Self {
            transport,
            from,
            verification_base_url: config.verification_base_url.clone(),
            password_reset_base_url: config.password_reset_base_url.clone(),
        })
    }

    /// Check if SMTP transport is enabled
    pub fn is_enabled(&self) -> bool {
        self.transport.is_some()
    }

    /// Send verification email with activation link
    ///
    /// ## Arguments
    ///
    /// * `recipient` - Email address
    /// * `token` - Verification token (opaque string)
    pub async fn send_verification_email(&self, recipient: &str, token: &str) -> Result<()> {
        let link = self.build_verification_link(token);
        let subject = "Verify your Nova account";
        let body = format!(
            "歡迎加入 Nova！\n\n請點擊以下連結完成 Email 驗證：\n{}\n\n若非本人操作，請忽略此郵件。",
            link
        );
        self.send_mail(recipient, subject, &body).await
    }

    /// Send password reset email with reset link
    ///
    /// ## Arguments
    ///
    /// * `recipient` - Email address
    /// * `token` - Password reset token (opaque string)
    pub async fn send_password_reset_email(&self, recipient: &str, token: &str) -> Result<()> {
        let web_link = self.build_password_reset_link(token);
        let ios_link = format!("nova://reset-password?token={}", token);
        let subject = "Nova 密碼重設通知";

        // HTML email with both web and iOS deep links
        let html_body = format!(
            r#"<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; padding: 20px; color: #333;">
    <h2>密碼重設申請</h2>
    <p>我們收到你的密碼重設申請。</p>
    <p>請點擊以下按鈕完成密碼重設：</p>
    <p style="margin: 30px 0;">
        <a href="{ios_link}" style="background-color: #000; color: #fff; padding: 14px 28px; text-decoration: none; border-radius: 25px; display: inline-block;">在 App 中重設密碼</a>
    </p>
    <p style="color: #666; font-size: 14px;">
        如果按鈕無法使用，請複製以下連結到瀏覽器：<br>
        <a href="{web_link}" style="color: #007AFF;">{web_link}</a>
    </p>
    <p style="color: #999; font-size: 12px; margin-top: 30px;">
        此連結將在 1 小時後失效。<br>
        若非本人操作，請立即忽略此郵件或聯絡客服協助。
    </p>
</body>
</html>"#,
            ios_link = ios_link,
            web_link = web_link
        );

        let text_body = format!(
            "我們收到你的密碼重設申請。\n\n\
            請點擊以下連結完成密碼重設：\n\
            iOS App: {}\n\
            網頁版: {}\n\n\
            此連結將在 1 小時後失效。\n\
            若非本人操作，請立即忽略此郵件或聯絡客服協助。",
            ios_link, web_link
        );

        self.send_html_email(recipient, subject, &html_body, &text_body)
            .await
    }

    /// Generate random backup verification code
    ///
    /// Returns 32-character alphanumeric code for manual verification flows.
    pub fn generate_backup_code(&self) -> String {
        rand::thread_rng()
            .sample_iter(&Alphanumeric)
            .take(32)
            .map(char::from)
            .collect()
    }

    fn build_verification_link(&self, token: &str) -> String {
        match &self.verification_base_url {
            Some(base) if !base.is_empty() => format!("{base}?token={token}"),
            _ => format!("https://app.nova.dev/verify-email?token={token}"),
        }
    }

    fn build_password_reset_link(&self, token: &str) -> String {
        match &self.password_reset_base_url {
            Some(base) if !base.is_empty() => format!("{base}?token={token}"),
            _ => format!("https://app.nova.dev/reset-password?token={token}"),
        }
    }

    async fn send_mail(&self, recipient: &str, subject: &str, body: &str) -> Result<()> {
        if let Some(transport) = &self.transport {
            let to = recipient.parse::<Mailbox>().map_err(|e| {
                IdentityError::Internal(format!("Invalid recipient email address: {}", e))
            })?;

            let email = Message::builder()
                .from(self.from.clone())
                .to(to)
                .subject(subject)
                .header(header::ContentType::TEXT_PLAIN)
                .body(body.to_string())
                .map_err(|e| {
                    IdentityError::Internal(format!("Failed to build email message: {}", e))
                })?;

            transport
                .send(email)
                .await
                .map_err(|e| IdentityError::Internal(format!("Failed to send email: {}", e)))?;
            info!(subject, "email sent successfully");
        } else {
            info!(
                subject,
                recipient, "Email service running in no-op mode; skipping actual send"
            );
        }
        Ok(())
    }

    /// Send HTML email with plain text fallback
    ///
    /// ## Arguments
    ///
    /// * `recipient` - Email address
    /// * `subject` - Email subject
    /// * `html_body` - HTML body content
    /// * `text_body` - Plain text fallback content
    pub async fn send_html_email(
        &self,
        recipient: &str,
        subject: &str,
        html_body: &str,
        text_body: &str,
    ) -> Result<()> {
        use lettre::message::MultiPart;

        if let Some(transport) = &self.transport {
            let to = recipient.parse::<Mailbox>().map_err(|e| {
                IdentityError::Internal(format!("Invalid recipient email address: {}", e))
            })?;

            let email = Message::builder()
                .from(self.from.clone())
                .to(to)
                .subject(subject)
                .multipart(
                    MultiPart::alternative()
                        .singlepart(
                            lettre::message::SinglePart::builder()
                                .header(header::ContentType::TEXT_PLAIN)
                                .body(text_body.to_string()),
                        )
                        .singlepart(
                            lettre::message::SinglePart::builder()
                                .header(header::ContentType::TEXT_HTML)
                                .body(html_body.to_string()),
                        ),
                )
                .map_err(|e| {
                    IdentityError::Internal(format!("Failed to build HTML email message: {}", e))
                })?;

            transport.send(email).await.map_err(|e| {
                IdentityError::Internal(format!("Failed to send HTML email: {}", e))
            })?;
            info!(subject, "HTML email sent successfully");
        } else {
            info!(
                subject,
                recipient, "Email service running in no-op mode; skipping actual send"
            );
        }
        Ok(())
    }
}
