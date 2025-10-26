use std::sync::{Arc, Mutex};

use apns2::{ApnsSync, NotificationBuilder, Priority};
use tokio::task;

use crate::{config::ApnsConfig, error::AppError};

#[derive(Clone)]
pub struct ApnsPush {
    inner: Arc<Mutex<ApnsSync>>,
    topic: String,
}

impl ApnsPush {
    pub fn new(cfg: &ApnsConfig) -> Result<Self, AppError> {
        let mut client = ApnsSync::with_certificate(
            &cfg.certificate_path,
            cfg.certificate_passphrase.clone(),
        )
        .map_err(|e| AppError::StartServer(format!("failed to initialize APNs client: {e}")))?;

        client.set_production(cfg.is_production);

        Ok(Self {
            inner: Arc::new(Mutex::new(client)),
            topic: cfg.bundle_id.clone(),
        })
    }

    pub async fn send_alert(
        &self,
        device_token: String,
        title: String,
        body: String,
        badge: Option<u32>,
    ) -> Result<(), AppError> {
        let topic = self.topic.clone();
        let client = self.inner.clone();

        task::spawn_blocking(move || {
            let mut builder = NotificationBuilder::new(topic, device_token);
            builder = builder.title(title).body(body).sound("default");
            if let Some(badge) = badge {
                builder = builder.badge(badge);
            }
            builder = builder.priority(Priority::High);

            let notification = builder.build();

            let guard = client.lock().map_err(|_| AppError::Internal)?;

            guard
                .send(notification)
                .map_err(|e| AppError::Config(format!("apns send failed: {e}")))
                .map(|_| ())
        })
        .await
        .map_err(|_| AppError::Internal)?
    }
}
