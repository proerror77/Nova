---
description: Create and execute PostgreSQL migrations with zero-downtime strategies using sqlx-cli
---

## User Input

```text
$ARGUMENTS
```

Expected format: `<action> [service-name] [migration-description]`

Actions:
- `create` - Create new migration file
- `plan` - Show pending migrations
- `run` - Execute pending migrations
- `revert` - Rollback last migration
- `status` - Show migration status

Examples:
- `/db.migrate create user-service add-email-verification-column`
- `/db.migrate plan user-service`
- `/db.migrate run user-service`
- `/db.migrate revert user-service`

## Execution Flow

### 1. Parse Arguments

Extract:
- **Action**: create | plan | run | revert | status
- **Service name**: Target microservice (e.g., "user-service")
- **Description**: For create action only

### 2. Route to Action Handler

#### Action: create

Invoke **database-migration-expert** agent:

```
Task: Design safe database migration
Agent: database-migration-expert
Prompt: |
  Create a new migration for {service-name} with expand-contract pattern:

  Migration: {description}

  Requirements:
  1. Analyze existing schema in backend/{service-name}/migrations/
  2. Design migration following expand-contract pattern:
     - Phase 1 (Expand): Add new columns/tables without breaking existing code
     - Phase 2 (Migrate): Data backfill or transformation (if needed)
     - Phase 3 (Contract): Remove old columns/tables (separate migration)

  3. Generate migration file:
     - Path: backend/{service-name}/migrations/{NNN}_{description}.sql
     - Include UP migration (forward changes)
     - Include DOWN migration (rollback) in comments
     - Add safety checks (IF NOT EXISTS, IF EXISTS)

  4. Identify breaking changes and suggest deployment strategy

  5. Verify:
     - Foreign key constraints have explicit ON DELETE/ON UPDATE
     - Indexes added for new columns used in WHERE/JOIN
     - No ALTER TABLE that locks table for long duration
     - Data migrations are idempotent

  Use skill: database-optimization
```

Output migration file and deployment instructions.

#### Action: plan

Execute for specified service:

```bash
cd backend/{service-name}
sqlx migrate info --database-url $DATABASE_URL
```

Display:
- Pending migrations (not yet applied)
- Applied migrations with timestamps
- Current database version

#### Action: run

**Safety workflow:**

1. **Pre-flight checks** (invoke database-migration-expert):
   ```
   Task: Validate migration safety
   Agent: database-migration-expert
   Prompt: |
     Review pending migrations for {service-name}:

     Analyze:
     1. Check for blocking operations (ALTER TABLE, CREATE INDEX without CONCURRENTLY)
     2. Estimate migration duration and table lock time
     3. Identify potential data loss risks
     4. Verify rollback procedure exists

     Recommendation: SAFE_TO_RUN | REQUIRES_MAINTENANCE_WINDOW | BLOCKED
   ```

2. **If SAFE_TO_RUN**:
   ```bash
   cd backend/{service-name}
   sqlx migrate run --database-url $DATABASE_URL
   ```

3. **If REQUIRES_MAINTENANCE_WINDOW**:
   - Warn user about downtime requirements
   - Suggest scheduling maintenance window
   - Provide rollback command

4. **If BLOCKED**:
   - List blocking issues
   - Suggest migration redesign with expand-contract
   - Do NOT execute

5. **Post-migration verification**:
   ```sql
   -- Verify schema changes
   SELECT column_name, data_type, is_nullable
   FROM information_schema.columns
   WHERE table_name = '{table_name}';

   -- Check constraints
   SELECT constraint_name, constraint_type
   FROM information_schema.table_constraints
   WHERE table_name = '{table_name}';
   ```

#### Action: revert

**Revert workflow:**

1. **Confirm with user**:
   ```
   ⚠️  WARNING: Reverting migration may cause data loss

   Last applied migration: {migration_name}
   Database: {service-name}

   Are you sure you want to revert? (yes/no)
   ```

2. **If confirmed**:
   ```bash
   cd backend/{service-name}
   sqlx migrate revert --database-url $DATABASE_URL
   ```

3. **Verify rollback**:
   - Check schema matches expected state
   - Verify dependent services still functional
   - Test service restart

#### Action: status

Show comprehensive migration status:

```bash
# For each microservice with migrations
for service in user-service content-service feed-service media-service; do
  echo "=== $service ==="
  cd backend/$service
  sqlx migrate info --database-url $DATABASE_URL_${service^^}
  echo ""
done
```

Display:
- Service name
- Current database version
- Pending migrations count
- Last applied migration timestamp

### 3. Integration with Existing Code

After successful migration:

1. **Regenerate SQLx query metadata** (for compile-time verification):
   ```bash
   cd backend/{service-name}
   cargo sqlx prepare --database-url $DATABASE_URL
   ```

2. **Update data models** (if schema changed):
   - Regenerate struct fields to match new columns
   - Update queries in src/ files
   - Update integration tests

3. **Check for query compilation errors**:
   ```bash
   cargo check
   ```

### 4. Best Practices Enforcement

Automatically check migrations for common issues:

**Anti-patterns to detect:**
- ❌ `ALTER TABLE ... ADD COLUMN ... NOT NULL` without DEFAULT (blocks writes)
- ❌ `CREATE INDEX` without `CONCURRENTLY` keyword (locks table)
- ❌ `DROP COLUMN` without expand-contract period (breaks deployed code)
- ❌ `ALTER TABLE ... CHANGE COLUMN` type changes (data loss risk)
- ❌ Foreign keys without explicit `ON DELETE` strategy (CASCADE by default)

**Required patterns:**
- ✅ `CREATE INDEX CONCURRENTLY` for production tables
- ✅ `ALTER TABLE ... ADD COLUMN ... DEFAULT ... NOT NULL` (safe add)
- ✅ Separate migrations for expand and contract phases
- ✅ Data backfill in separate migration from schema changes
- ✅ Explicit foreign key constraints with ON DELETE RESTRICT/CASCADE

### 5. Output Summary

```markdown
## Migration {action} Complete

**Service**: {service-name}
**Action**: {action}
**Status**: ✅ SUCCESS | ⚠️  WARNING | ❌ ERROR

### Details
- Migration file: {migration-file}
- Database version: {version}
- Execution time: {duration}

### Next Steps
1. Regenerate SQLx metadata: `cargo sqlx prepare`
2. Update data models if schema changed
3. Run tests: `cargo test`
4. Deploy updated service to staging
5. Monitor for errors before production rollout

### Rollback Command
If issues occur:
```bash
cd backend/{service-name}
sqlx migrate revert --database-url $DATABASE_URL
```
```

## Error Handling

- **Missing DATABASE_URL**: Prompt user to set environment variable
- **Migration conflicts**: Suggest resolving conflicts in migration files
- **Connection errors**: Verify database is running and accessible
- **Lock timeout**: Suggest retry or maintenance window
- **Validation errors**: Display specific issues and recommended fixes

## Safety Features

1. **Dry-run mode**: Always show SQL before execution (for run/revert)
2. **Confirmation prompts**: For destructive operations (revert, contract phase)
3. **Automatic backups**: Suggest pg_dump before major migrations
4. **Rollback verification**: Ensure DOWN migration exists and is tested
5. **Canary deployment**: Suggest rolling deployment strategy for schema changes

## Integration with Skills

This command automatically leverages:
- **database-optimization**: Schema design and indexing strategies
- **rust-async-patterns**: SQLx connection pooling configuration
- **microservices-architecture**: Database-per-service pattern enforcement
