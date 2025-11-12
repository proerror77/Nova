use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// 邊的類型
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum EdgeType {
    Follow,
    Mute,
    Block,
}

impl EdgeType {
    pub fn as_str(&self) -> &'static str {
        match self {
            EdgeType::Follow => "FOLLOWS",
            EdgeType::Mute => "MUTES",
            EdgeType::Block => "BLOCKS",
        }
    }
}

/// 關係邊（有向邊）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Edge {
    pub from_user_id: Uuid,
    pub to_user_id: Uuid,
    pub edge_type: EdgeType,
    pub created_at: DateTime<Utc>,
}

impl Edge {
    pub fn new_follow(follower_id: Uuid, followee_id: Uuid) -> Self {
        Self {
            from_user_id: follower_id,
            to_user_id: followee_id,
            edge_type: EdgeType::Follow,
            created_at: Utc::now(),
        }
    }

    pub fn new_mute(muter_id: Uuid, mutee_id: Uuid) -> Self {
        Self {
            from_user_id: muter_id,
            to_user_id: mutee_id,
            edge_type: EdgeType::Mute,
            created_at: Utc::now(),
        }
    }

    pub fn new_block(blocker_id: Uuid, blocked_id: Uuid) -> Self {
        Self {
            from_user_id: blocker_id,
            to_user_id: blocked_id,
            edge_type: EdgeType::Block,
            created_at: Utc::now(),
        }
    }
}

/// 關係圖統計
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GraphStats {
    pub user_id: Uuid,
    pub followers_count: i64,
    pub following_count: i64,
    pub muted_count: i64,
    pub blocked_count: i64,
}

impl Default for GraphStats {
    fn default() -> Self {
        Self {
            user_id: Uuid::nil(),
            followers_count: 0,
            following_count: 0,
            muted_count: 0,
            blocked_count: 0,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_edge_type_as_str() {
        assert_eq!(EdgeType::Follow.as_str(), "FOLLOWS");
        assert_eq!(EdgeType::Mute.as_str(), "MUTES");
        assert_eq!(EdgeType::Block.as_str(), "BLOCKS");
    }

    #[test]
    fn test_create_follow_edge() {
        let follower = Uuid::new_v4();
        let followee = Uuid::new_v4();

        let edge = Edge::new_follow(follower, followee);

        assert_eq!(edge.from_user_id, follower);
        assert_eq!(edge.to_user_id, followee);
        assert_eq!(edge.edge_type, EdgeType::Follow);
    }
}
