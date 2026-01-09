/// Email service for sending verification and password reset emails
use crate::config::EmailSettings;
use crate::error::{IdentityError, Result};
use lettre::message::{header, Mailbox, Message};
use lettre::transport::smtp::authentication::Credentials;
use lettre::{AsyncSmtpTransport, AsyncTransport, Tokio1Executor};
use rand::{distr::Alphanumeric, Rng};
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
        let subject = "Verify your Icered account";
        let body = format!(
            "Welcome to Icered!\n\nPlease click the following link to complete your email verification:\n{}\n\nIf you did not request this, please ignore this email.",
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
        let subject = "Icered Password Reset";

        // HTML email with both web and iOS deep links
        let html_body = format!(
            r#"<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; padding: 20px; color: #333;">
    <h2>Password Reset Request</h2>
    <p>We received your password reset request.</p>
    <p>Please click the button below to reset your password:</p>
    <p style="margin: 30px 0;">
        <a href="{ios_link}" style="background-color: #000; color: #fff; padding: 14px 28px; text-decoration: none; border-radius: 25px; display: inline-block;">Reset Password in App</a>
    </p>
    <p style="color: #666; font-size: 14px;">
        If the button doesn't work, please copy the following link to your browser:<br>
        <a href="{web_link}" style="color: #007AFF;">{web_link}</a>
    </p>
    <p style="color: #999; font-size: 12px; margin-top: 30px;">
        This link will expire in 1 hour.<br>
        If you did not request this, please ignore this email or contact support immediately.
    </p>
</body>
</html>"#,
            ios_link = ios_link,
            web_link = web_link
        );

        let text_body = format!(
            "We received your password reset request.\n\n\
            Please click the following link to reset your password:\n\
            iOS App: {}\n\
            Web: {}\n\n\
            This link will expire in 1 hour.\n\
            If you did not request this, please ignore this email or contact support immediately.",
            ios_link, web_link
        );

        self.send_html_email(recipient, subject, &html_body, &text_body)
            .await
    }

    /// Generate random backup verification code
    ///
    /// Returns 32-character alphanumeric code for manual verification flows.
    pub fn generate_backup_code(&self) -> String {
        rand::rng()
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
