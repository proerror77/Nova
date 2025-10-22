// Simple RBAC: roles are strings like "admin" or "member".
// Rules:
// - admin implies member
// - required "admin" => must have "admin"
// - required "member" => has "member" or "admin"
pub fn authorize(required_role: &str, user_roles: &[String]) -> bool {
    let has_admin = user_roles.iter().any(|r| r == "admin");
    let has_member = has_admin || user_roles.iter().any(|r| r == "member");
    match required_role {
        "admin" => has_admin,
        "member" => has_member,
        other => user_roles.iter().any(|r| r == other),
    }
}
