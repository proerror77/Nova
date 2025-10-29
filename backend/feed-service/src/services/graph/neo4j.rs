use crate::config::GraphConfig;
use anyhow::{anyhow, Result};
use neo4rs::{query, Graph};
use uuid::Uuid;

#[derive(Clone)]
pub struct GraphService {
    graph: Option<Graph>,
    enabled: bool,
}

impl GraphService {
    pub async fn new(cfg: &GraphConfig) -> Result<Self> {
        if !cfg.enabled {
            return Ok(Self {
                graph: None,
                enabled: false,
            });
        }
        let graph = Graph::new(&cfg.neo4j_uri, &cfg.neo4j_user, &cfg.neo4j_password)
            .await
            .map_err(|e| anyhow!("Neo4j connection error: {}", e))?;
        let svc = Self {
            graph: Some(graph),
            enabled: true,
        };
        // Basic health check (ignore result)
        svc.health_check().await.ok();
        Ok(svc)
    }

    pub fn is_enabled(&self) -> bool {
        self.enabled
    }

    pub async fn health_check(&self) -> Result<bool> {
        if !self.enabled {
            return Ok(false);
        }
        let mut result = self
            .graph
            .as_ref()
            .unwrap()
            .execute(query("RETURN 1 AS ok"))
            .await?;
        let mut ok = false;
        while let Ok(Some(row)) = result.next().await {
            let v: i64 = row.get("ok").unwrap_or(0);
            if v == 1 {
                ok = true;
                break;
            }
        }
        Ok(ok)
    }

    /// Ensure user node exists
    async fn ensure_user_node(&self, user_id: Uuid) -> Result<()> {
        if !self.enabled {
            return Ok(());
        }
        let cypher = r#"
            MERGE (u:User {id: $id})
            ON CREATE SET u.created_at = timestamp()
        "#;
        let mut result = self
            .graph
            .as_ref()
            .unwrap()
            .execute(query(cypher).param("id", user_id.to_string()))
            .await?;
        // Drain stream to complete
        while let Ok(Some(_row)) = result.next().await {
            // drain
        }
        Ok(())
    }

    /// Create FOLLOWS relationship
    pub async fn follow(&self, follower: Uuid, followee: Uuid) -> Result<()> {
        if !self.enabled {
            return Ok(());
        }
        if follower == followee {
            return Ok(());
        }
        self.ensure_user_node(follower).await?;
        self.ensure_user_node(followee).await?;
        let cypher = r#"
            MATCH (a:User {id: $follower}), (b:User {id: $followee})
            MERGE (a)-[r:FOLLOWS]->(b)
            ON CREATE SET r.created_at = timestamp()
        "#;
        let mut result = self
            .graph
            .as_ref()
            .unwrap()
            .execute(
                query(cypher)
                    .param("follower", follower.to_string())
                    .param("followee", followee.to_string()),
            )
            .await?;
        while let Ok(Some(_row)) = result.next().await {
            // drain
        }
        Ok(())
    }

    /// Delete FOLLOWS relationship
    pub async fn unfollow(&self, follower: Uuid, followee: Uuid) -> Result<()> {
        if !self.enabled {
            return Ok(());
        }
        let cypher = r#"
            MATCH (a:User {id: $follower})-[r:FOLLOWS]->(b:User {id: $followee})
            DELETE r
        "#;
        let mut result = self
            .graph
            .as_ref()
            .unwrap()
            .execute(
                query(cypher)
                    .param("follower", follower.to_string())
                    .param("followee", followee.to_string()),
            )
            .await?;
        while let Ok(Some(_row)) = result.next().await {}
        Ok(())
    }

    /// Suggested friends via friends-of-friends, excluding already-followed
    pub async fn suggested_friends(&self, user_id: Uuid, limit: usize) -> Result<Vec<(Uuid, u64)>> {
        if !self.enabled {
            return Ok(vec![]);
        }
        let cypher = r#"
            MATCH (me:User {id: $uid})-[:FOLLOWS]->(:User)-[:FOLLOWS]->(c:User)
            WHERE c.id <> $uid AND NOT (me)-[:FOLLOWS]->(c)
            RETURN c.id AS candidate_id, count(*) AS mutuals
            ORDER BY mutuals DESC
            LIMIT $limit
        "#;
        let mut res = self
            .graph
            .as_ref()
            .unwrap()
            .execute(
                query(cypher)
                    .param("uid", user_id.to_string())
                    .param("limit", limit as i64),
            )
            .await?;
        let mut out = Vec::new();
        while let Ok(Some(row)) = res.next().await {
            let id_str: String = row.get("candidate_id").unwrap_or_default();
            if let Ok(cid) = Uuid::parse_str(&id_str) {
                let mutuals: i64 = row.get("mutuals").unwrap_or(0);
                out.push((cid, mutuals as u64));
            }
        }
        Ok(out)
    }

    /// Count mutual connections between two users
    pub async fn mutual_count(&self, a: Uuid, b: Uuid) -> Result<u64> {
        if !self.enabled {
            return Ok(0);
        }
        let cypher = r#"
            MATCH (a:User {id: $a})-[:FOLLOWS]->(x:User)<-[:FOLLOWS]-(b:User {id: $b})
            RETURN count(distinct x) AS mutuals
        "#;
        let mut res = self
            .graph
            .as_ref()
            .unwrap()
            .execute(
                query(cypher)
                    .param("a", a.to_string())
                    .param("b", b.to_string()),
            )
            .await?;
        while let Ok(Some(row)) = res.next().await {
            let mutuals: i64 = row.get("mutuals").unwrap_or(0);
            return Ok(mutuals as u64);
        }
        Ok(0)
    }
}
