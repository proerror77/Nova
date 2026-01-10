use matrix_sdk::ruma::OwnedUserId;
use uuid::Uuid;

/// Extract Nova user UUID from Matrix user_id (MXID).
///
/// Expected format: `@nova-<uuid>:<server_name>`.
pub fn extract_nova_user_id_from_matrix(matrix_user: &OwnedUserId) -> Option<Uuid> {
    extract_nova_user_id_from_mxid(matrix_user.as_str())
}

pub fn extract_nova_user_id_from_mxid(mxid: &str) -> Option<Uuid> {
    if !mxid.starts_with("@nova-") {
        return None;
    }

    let without_prefix = mxid.strip_prefix("@nova-")?;
    let uuid_part = without_prefix.split(':').next()?;
    Uuid::parse_str(uuid_part).ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use matrix_sdk::ruma::UserId;

    #[test]
    fn test_extract_nova_user_id_from_mxid() {
        assert_eq!(
            extract_nova_user_id_from_mxid(
                "@nova-550e8400-e29b-41d4-a716-446655440000:staging.nova.internal"
            ),
            Some(Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap())
        );
        assert_eq!(extract_nova_user_id_from_mxid("@user:staging.nova.internal"), None);
        assert_eq!(
            extract_nova_user_id_from_mxid("@nova-invalid-uuid:staging.nova.internal"),
            None
        );
    }

    #[test]
    fn test_extract_nova_user_id_from_matrix() {
        let user_id =
            UserId::parse("@nova-550e8400-e29b-41d4-a716-446655440000:staging.nova.internal").unwrap();
        assert_eq!(
            extract_nova_user_id_from_matrix(&user_id),
            Some(Uuid::parse_str("550e8400-e29b-41d4-a716-446655440000").unwrap())
        );
    }
}

