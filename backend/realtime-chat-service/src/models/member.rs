//! Member role and related data structures
//!
//! This module defines the role hierarchy for conversation members.
//! Roles have a natural ordering: Member < Moderator < Admin < Owner

use serde::{Deserialize, Serialize};
use std::fmt;

/// Member role in a conversation with natural hierarchy
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum MemberRole {
    /// Regular member - can send messages
    Member = 0,
    /// Moderator - can delete others' messages
    Moderator = 1,
    /// Admin - can manage members (add, remove, change roles except owner)
    Admin = 2,
    /// Owner - full control (can remove admins, transfer ownership)
    Owner = 3,
}

impl MemberRole {
    /// Parse role from database string
    /// This handles the existing "admin" and "member" values in DB
    pub fn from_db(s: &str) -> Option<Self> {
        match s {
            "member" => Some(Self::Member),
            "moderator" => Some(Self::Moderator),
            "admin" => Some(Self::Admin),
            "owner" => Some(Self::Owner),
            _ => None,
        }
    }

    /// Convert role to database string
    pub fn to_db(&self) -> &'static str {
        match self {
            Self::Member => "member",
            Self::Moderator => "moderator",
            Self::Admin => "admin",
            Self::Owner => "owner",
        }
    }

    /// Check if this role can manage another role
    /// Rule: You can only manage roles strictly below yours
    pub fn can_manage(&self, target: MemberRole) -> bool {
        *self > target
    }

    /// Check if this role can perform admin actions
    pub fn is_privileged(&self) -> bool {
        *self >= MemberRole::Admin
    }
}

impl fmt::Display for MemberRole {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.to_db())
    }
}

/// Parse from string (for API requests)
impl std::str::FromStr for MemberRole {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Self::from_db(s).ok_or_else(|| format!("Invalid role: {}", s))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_role_ordering() {
        assert!(MemberRole::Member < MemberRole::Moderator);
        assert!(MemberRole::Moderator < MemberRole::Admin);
        assert!(MemberRole::Admin < MemberRole::Owner);
    }

    #[test]
    fn test_can_manage() {
        let owner = MemberRole::Owner;
        let admin = MemberRole::Admin;
        let moderator = MemberRole::Moderator;
        let member = MemberRole::Member;

        // Owner can manage everyone below
        assert!(owner.can_manage(admin));
        assert!(owner.can_manage(moderator));
        assert!(owner.can_manage(member));

        // Admin can manage moderator and member
        assert!(admin.can_manage(moderator));
        assert!(admin.can_manage(member));
        assert!(!admin.can_manage(admin)); // Cannot manage same level
        assert!(!admin.can_manage(owner)); // Cannot manage higher

        // Moderator can only manage member
        assert!(moderator.can_manage(member));
        assert!(!moderator.can_manage(moderator));
        assert!(!moderator.can_manage(admin));

        // Member cannot manage anyone
        assert!(!member.can_manage(member));
    }

    #[test]
    fn test_is_privileged() {
        assert!(!MemberRole::Member.is_privileged());
        assert!(!MemberRole::Moderator.is_privileged());
        assert!(MemberRole::Admin.is_privileged());
        assert!(MemberRole::Owner.is_privileged());
    }

    #[test]
    fn test_from_db() {
        assert_eq!(MemberRole::from_db("member"), Some(MemberRole::Member));
        assert_eq!(
            MemberRole::from_db("moderator"),
            Some(MemberRole::Moderator)
        );
        assert_eq!(MemberRole::from_db("admin"), Some(MemberRole::Admin));
        assert_eq!(MemberRole::from_db("owner"), Some(MemberRole::Owner));
        assert_eq!(MemberRole::from_db("invalid"), None);
    }

    #[test]
    fn test_to_db() {
        assert_eq!(MemberRole::Member.to_db(), "member");
        assert_eq!(MemberRole::Moderator.to_db(), "moderator");
        assert_eq!(MemberRole::Admin.to_db(), "admin");
        assert_eq!(MemberRole::Owner.to_db(), "owner");
    }
}
