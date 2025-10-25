// Neo4j schema for Nova Social graph
// - Unique user id
// - Optional index on FOLLOWS created_at for sorting

CREATE CONSTRAINT user_id_unique IF NOT EXISTS
FOR (u:User)
REQUIRE u.id IS UNIQUE;

// Optional: index on relationship property for time-based queries
CREATE INDEX follows_created_at_idx IF NOT EXISTS
FOR ()-[r:FOLLOWS]-()
ON (r.created_at);

