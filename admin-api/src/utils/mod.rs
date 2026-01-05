// Utility functions for admin API

use chrono::{DateTime, Utc};

/// Format datetime for API responses
pub fn format_datetime(dt: DateTime<Utc>) -> String {
    dt.format("%Y-%m-%dT%H:%M:%SZ").to_string()
}

/// Mask sensitive data like phone numbers
pub fn mask_phone(phone: &str) -> String {
    if phone.len() < 7 {
        return phone.to_string();
    }

    let visible_start = 3;
    let visible_end = 4;
    let masked_len = phone.len() - visible_start - visible_end;

    format!(
        "{}{}{}",
        &phone[..visible_start],
        "*".repeat(masked_len),
        &phone[phone.len() - visible_end..]
    )
}

/// Mask email address
pub fn mask_email(email: &str) -> String {
    if let Some(at_pos) = email.find('@') {
        let local = &email[..at_pos];
        let domain = &email[at_pos..];

        if local.len() <= 2 {
            return email.to_string();
        }

        format!("{}***{}", &local[..2], domain)
    } else {
        email.to_string()
    }
}
