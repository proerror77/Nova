# Graph Service Migrations

## PostgreSQL → Neo4j Migration

### Prerequisites

1. **PostgreSQL** with `follows` table:
   ```sql
   CREATE TABLE follows (
     follower_id UUID NOT NULL,
     following_id UUID NOT NULL,
     created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
     PRIMARY KEY (follower_id, following_id)
   );
   ```

2. **Neo4j** running (version 5.x recommended):
   ```bash
   docker run -p 7687:7687 -e NEO4J_AUTH=neo4j/password neo4j:5
   ```

### Migration Steps

#### Step 1: Dry Run (Validation Only)
```bash
# Set environment variables
export DATABASE_URL="postgresql://user:password@localhost:5432/dbname"
export NEO4J_URI="bolt://localhost:7687"
export NEO4J_USER="neo4j"
export NEO4J_PASSWORD="password"
export DRY_RUN="true"
export BATCH_SIZE="1000"

# Run migration in dry-run mode
cargo run --bin migrate_follows_to_neo4j
```

**Expected Output**:
```
INFO Starting PostgreSQL → Neo4j migration
INFO Total follows in PostgreSQL: 50000
INFO DRY RUN - No data was actually written to Neo4j
INFO Migration completed!
INFO Successfully migrated: 50000
```

#### Step 2: Production Migration
```bash
# Remove DRY_RUN flag
unset DRY_RUN

# Run actual migration
cargo run --bin migrate_follows_to_neo4j
```

**Expected Output**:
```
INFO Starting PostgreSQL → Neo4j migration
INFO Total follows in PostgreSQL: 50000
INFO Existing FOLLOWS edges in Neo4j: 0
INFO Processing 1000 follows in this batch
INFO Progress: 10000/50000 migrated
INFO Progress: 20000/50000 migrated
...
INFO Migration completed!
INFO Successfully migrated: 50000
INFO Final FOLLOWS edges in Neo4j: 50000
INFO ✅ Verification passed: Neo4j count matches expected
```

### Performance

- **Batch Size**: Default 1000, adjust with `BATCH_SIZE` env var
- **Throughput**: ~500-1000 follows/second (single-threaded)
- **Estimate**: 100K follows = 2-3 minutes

### Verification Queries

#### PostgreSQL - Count follows
```sql
SELECT COUNT(*) FROM follows;
```

#### Neo4j - Count FOLLOWS edges
```cypher
MATCH ()-[r:FOLLOWS]->()
RETURN count(r) AS total_follows;
```

#### Neo4j - Sample data
```cypher
MATCH (a:User)-[r:FOLLOWS]->(b:User)
RETURN a.id AS follower, b.id AS followee, r.created_at
LIMIT 10;
```

### Rollback Plan

If migration fails or needs to be restarted:

```cypher
// Delete all FOLLOWS edges in Neo4j
MATCH ()-[r:FOLLOWS]->()
DELETE r;

// Optionally, delete all User nodes (if no other data)
MATCH (u:User)
DELETE u;
```

Then re-run the migration script.

### Troubleshooting

#### Issue: "Neo4j connection failed"
**Solution**: Verify Neo4j is running and credentials are correct:
```bash
docker ps | grep neo4j
# Access Neo4j browser: http://localhost:7474
```

#### Issue: "Database count mismatch"
**Solution**: Run verification queries in both databases:
```sql
-- PostgreSQL
SELECT COUNT(*) FROM follows;
```
```cypher
-- Neo4j
MATCH ()-[r:FOLLOWS]->() RETURN count(r);
```

If counts don't match, check migration logs for errors.

#### Issue: "Out of memory"
**Solution**: Reduce `BATCH_SIZE`:
```bash
export BATCH_SIZE="500"
cargo run --bin migrate_follows_to_neo4j
```

### Post-Migration Tasks

1. **Index Creation** (for query performance):
   ```cypher
   // Create index on User.id
   CREATE INDEX user_id_index FOR (u:User) ON (u.id);

   // Verify index
   SHOW INDEXES;
   ```

2. **Update user-service**:
   - Stop writing to PostgreSQL `follows` table
   - Redirect all follow/unfollow operations to graph-service gRPC

3. **Update feed-service**:
   - Replace Neo4j direct calls with graph-service gRPC client
   - Delete `feed-service/src/services/graph/` directory

4. **Monitor Performance**:
   ```cypher
   // Query performance test
   PROFILE MATCH (a:User {id: $user_id})-[:FOLLOWS]->(b:User)
   RETURN b.id
   LIMIT 1000;
   ```

### Continuous Sync (Optional)

If you need to keep PostgreSQL and Neo4j in sync during a transition period:

1. **Enable Transactional Outbox** in user-service for follow events
2. **Create event consumer** that writes to Neo4j in real-time
3. **Gradually shift read traffic** from PostgreSQL to Neo4j

**Not recommended** - better to do a one-time migration with downtime window.

---

## Additional Migrations

### MUTES and BLOCKS (Future)

Similar scripts can be created for mute and block relationships if they exist in PostgreSQL:

```bash
cargo run --bin migrate_mutes_to_neo4j
cargo run --bin migrate_blocks_to_neo4j
```

These follow the same pattern as `migrate_follows_to_neo4j.rs`.
