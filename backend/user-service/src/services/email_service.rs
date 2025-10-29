/// Email service for sending verification and password reset emails
/// Uses lettre for SMTP email delivery
use anyhow::{anyhow, Result};
use lettre::message::header::ContentType;
use lettre::transport::smtp::SmtpTransport;
use lettre::{Message, Transport};
use std::sync::Arc;

/// Configuration for SMTP email service
#[derive(Debug, Clone)]
pub struct EmailConfig {
    /// SMTP server host (e.g., smtp.gmail.com, smtp.sendgrid.net)
    pub smtp_host: String,
    /// SMTP server port (usually 587 for TLS, 465 for SSL)
    pub smtp_port: u16,
    /// SMTP username/sender email
    pub smtp_username: String,
    /// SMTP password
    pub smtp_password: String,
    /// Sender email address
    pub from_email: String,
    /// Sender display name
    pub from_name: String,
    /// Frontend URL for email links (e.g., https://app.nova.dev)
    pub frontend_url: String,
}

impl EmailConfig {
    /// Create new email config from environment variables
    pub fn from_env() -> Result<Self> {
        Ok(EmailConfig {
            smtp_host: std::env::var("SMTP_HOST")
                .unwrap_or_else(|_| "localhost".to_string()),
            smtp_port: std::env::var("SMTP_PORT")
                .unwrap_or_else(|_| "587".to_string())
                .parse()
                .unwrap_or(587),
            smtp_username: std::env::var("SMTP_USERNAME")
                .unwrap_or_default(),
            smtp_password: std::env::var("SMTP_PASSWORD")
                .unwrap_or_default(),
            from_email: std::env::var("FROM_EMAIL")
                .unwrap_or_else(|_| "noreply@nova.dev".to_string()),
            from_name: std::env::var("FROM_NAME")
                .unwrap_or_else(|_| "Nova Team".to_string()),
            frontend_url: std::env::var("FRONTEND_URL")
                .unwrap_or_else(|_| "https://app.nova.dev".to_string()),
        })
    }
}

/// Email service for sending verification and password reset emails
pub struct EmailService {
    config: Arc<EmailConfig>,
}

impl EmailService {
    /// Create new email service
    pub fn new(config: EmailConfig) -> Self {
        EmailService {
            config: Arc::new(config),
        }
    }

    /// Create SMTP transport
    fn create_transport(&self) -> Result<SmtpTransport> {
        let creds = lettre::transport::smtp::authentication::Credentials::new(
            self.config.smtp_username.clone().into(),
            self.config.smtp_password.clone().into(),
        );

        let mailer = SmtpTransport::builder_dangerous(&self.config.smtp_host)
            .port(self.config.smtp_port)
            .credentials(creds)
            .build()
            .map_err(|e| anyhow!("Failed to build SMTP transport: {}", e))?;

        Ok(mailer)
    }

    /// Send email verification email
    pub async fn send_verification_email(
        &self,
        to_email: &str,
        to_name: &str,
        username: &str,
        token: &str,
    ) -> Result<()> {
        let verification_url = format!(
            "{}/auth/verify-email?token={}",
            self.config.frontend_url, token
        );

        let html_body = format!(
            r#"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background-color: #007bff; color: white; padding: 20px; text-align: center; border-radius: 5px 5px 0 0; }}
        .content {{ background-color: #f9f9f9; padding: 20px; border-radius: 0 0 5px 5px; }}
        .button {{ display: inline-block; background-color: #007bff; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px; margin: 20px 0; }}
        .footer {{ margin-top: 20px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 12px; color: #666; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Welcome to Nova!</h1>
        </div>
        <div class="content">
            <p>Hi <strong>{}</strong>,</p>

            <p>Thank you for signing up! To verify your email address and complete your registration, please click the button below:</p>

            <p style="text-align: center;">
                <a href="{}" class="button">Verify Email Address</a>
            </p>

            <p>Or copy and paste this link in your browser:</p>
            <p style="word-break: break-all; background-color: #eee; padding: 10px; border-radius: 4px;">
                {}
            </p>

            <p style="color: #666; font-size: 14px;">
                <strong>Security Note:</strong> This link will expire in 1 hour for security reasons.
                If you didn't create this account, you can safely ignore this email.
            </p>

            <div class="footer">
                <p>© 2024 Nova Social. All rights reserved.</p>
                <p>Nova Team &lt;support@nova.dev&gt;</p>
            </div>
        </div>
    </div>
</body>
</html>
            "#,
            to_name, verification_url, verification_url
        );

        let text_body = format!(
            r#"Welcome to Nova!

Hi {},

Thank you for signing up! To verify your email address, please visit the following link:

{}

This link will expire in 1 hour.

If you didn't create this account, you can safely ignore this email.

---
© 2024 Nova Social. All rights reserved.
Nova Team <support@nova.dev>
            "#,
            to_name, verification_url
        );

        self.send_email(
            to_email,
            "Verify Your Nova Email Address",
            &text_body,
            &html_body,
        )
        .await
    }

    /// Send password reset email
    pub async fn send_password_reset_email(
        &self,
        to_email: &str,
        to_name: &str,
        token: &str,
        expires_at: &str,
    ) -> Result<()> {
        let reset_url = format!(
            "{}/auth/reset-password?token={}",
            self.config.frontend_url, token
        );

        let html_body = format!(
            r#"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body {{ font-family: Arial, sans-serif; line-height: 1.6; color: #333; }}
        .container {{ max-width: 600px; margin: 0 auto; padding: 20px; }}
        .header {{ background-color: #dc3545; color: white; padding: 20px; text-align: center; border-radius: 5px 5px 0 0; }}
        .content {{ background-color: #f9f9f9; padding: 20px; border-radius: 0 0 5px 5px; }}
        .button {{ display: inline-block; background-color: #dc3545; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px; margin: 20px 0; }}
        .warning {{ background-color: #fff3cd; border: 1px solid #ffc107; color: #856404; padding: 10px; border-radius: 4px; margin: 15px 0; }}
        .footer {{ margin-top: 20px; padding-top: 20px; border-top: 1px solid #ddd; font-size: 12px; color: #666; }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Password Reset Request</h1>
        </div>
        <div class="content">
            <p>Hi <strong>{}</strong>,</p>

            <p>We received a request to reset the password for your Nova account. Click the button below to create a new password:</p>

            <p style="text-align: center;">
                <a href="{}" class="button">Reset Your Password</a>
            </p>

            <p>Or copy and paste this link in your browser:</p>
            <p style="word-break: break-all; background-color: #eee; padding: 10px; border-radius: 4px;">
                {}
            </p>

            <div class="warning">
                <strong>⚠️ Security Warning:</strong><br>
                This link will expire on {}.<br>
                If you didn't request a password reset, you can safely ignore this email.
                Your account is secure and no changes have been made.
            </div>

            <p style="color: #666; font-size: 14px;">
                For security reasons, we never send passwords via email. Always verify you're on nova.dev before entering your password.
            </p>

            <div class="footer">
                <p>© 2024 Nova Social. All rights reserved.</p>
                <p>Nova Team &lt;support@nova.dev&gt;</p>
            </div>
        </div>
    </div>
</body>
</html>
            "#,
            to_name, reset_url, reset_url, expires_at
        );

        let text_body = format!(
            r#"Password Reset Request

Hi {},

We received a request to reset the password for your Nova account. To create a new password, please visit:

{}

This link will expire on {}.

If you didn't request a password reset, you can safely ignore this email.
Your account is secure and no changes have been made.

---
© 2024 Nova Social. All rights reserved.
Nova Team <support@nova.dev>
            "#,
            to_name, reset_url, expires_at
        );

        self.send_email(
            to_email,
            "Reset Your Nova Password",
            &text_body,
            &html_body,
        )
        .await
    }

    /// Generic email sending method
    async fn send_email(&self, to_email: &str, subject: &str, text_body: &str, html_body: &str) -> Result<()> {
        // Validate email addresses
        if to_email.is_empty() {
            return Err(anyhow!("Recipient email cannot be empty"));
        }

        let from = format!("{} <{}>", self.config.from_name, self.config.from_email)
            .parse()
            .map_err(|e| anyhow!("Invalid from email address: {}", e))?;

        let to = to_email
            .parse()
            .map_err(|e| anyhow!("Invalid to email address: {}", e))?;

        // Build message with both text and HTML alternatives
        let message = Message::builder()
            .from(from)
            .to(to)
            .subject(subject)
            .multipart(
                lettre::message::MultiPart::alternative()
                    .singlepart(
                        lettre::message::SinglePart::builder()
                            .header(ContentType::TEXT_PLAIN)
                            .body(text_body.to_string())
                    )
                    .singlepart(
                        lettre::message::SinglePart::builder()
                            .header(ContentType::TEXT_HTML)
                            .body(html_body.to_string())
                    )
            )
            .map_err(|e| anyhow!("Failed to build email message: {}", e))?;

        // Create SMTP transport
        let mailer = self.create_transport()?;

        // Send email
        mailer
            .send(&message)
            .map_err(|e| anyhow!("Failed to send email: {}", e))?;

        Ok(())
    }

    /// Check if email service is properly configured
    pub fn is_configured(&self) -> bool {
        !self.config.smtp_username.is_empty()
            && !self.config.smtp_password.is_empty()
            && !self.config.smtp_host.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_email_config_from_env() {
        let config = EmailConfig::from_env();
        assert!(config.is_ok());
    }

    #[tokio::test]
    async fn test_email_service_creation() {
        let config = EmailConfig {
            smtp_host: "localhost".to_string(),
            smtp_port: 1025,
            smtp_username: "test".to_string(),
            smtp_password: "test".to_string(),
            from_email: "test@nova.dev".to_string(),
            from_name: "Test".to_string(),
            frontend_url: "http://localhost:3000".to_string(),
        };

        let service = EmailService::new(config);
        assert!(!service.is_configured()); // localhost not configured
    }
}
