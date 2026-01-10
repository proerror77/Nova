# Database Migration Best Practices

## Problem: "Migration was previously applied but is missing"

### Root Cause

This error occurs when a Docker image is built with **fewer migrations** than what exists in the database. This happens because:

1. SQLx's `sqlx::migrate!()` macro embeds migration files into the binary **at compile time**
2. If migrations are added to the database after an image is built, that old image will fail to start
3. The service detects a mismatch between embedded migrations and database state

### Example Timeline

```
2025-12-28: Image A built with migrations 1-11
2026-01-07: Migration 12 added to database
2026-01-09: Image A deployed → CRASH!
            Error: "migration 12 was previously applied but is missing"
```

### Why This Happened in Staging

On 2026-01-09, we discovered two services crashing:

1. **content-service** (image `96f78f17` from 2025-12-28)
   - Built with 11 migrations (up to `20251228`)
   - Database had 13 migrations (including `20260107` and `20260109`)
   - Missing: `20260107_add_author_account_type.sql`, `20260109_remove_unused_social_tables.sql`

2. **social-service** (image `c880a115` from 2025-12-28)
   - Built with 6 migrations (up to `006`)
   - Database had 7 migrations (including `007`)
   - Missing: `007_add_author_account_type.sql`

The old images were accidentally deployed (possibly via `kubectl set image` with SHA digest), causing the crash.

## Solutions

### 1. Immediate Fix (Already Applied)

Rollback to working images:
```bash
kubectl set image deployment/content-service \
  content-service=asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/content-service:cba93b7 \
  -n nova-staging

kubectl set image deployment/social-service \
  social-service=asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/social-service:6ef9949 \
  -n nova-staging
```

### 2. Prevention: Migration Validation Script

We've added `.github/scripts/validate-migrations.sh` that:
- Counts migrations in codebase
- Queries database for applied migrations
- Fails CI/CD if code has fewer migrations than database
- Runs automatically before deployment

Usage:
```bash
.github/scripts/validate-migrations.sh content-service nova-staging
```

### 3. CI/CD Integration

The validation script is now integrated into:
- `.github/workflows/gcp-build-deploy-one.yml` (line 140-143)

It runs before `kubectl set image`, preventing deployment of incompatible images.

## Best Practices

### ✅ DO

1. **Always build fresh images** when deploying after migrations are added
2. **Use git commit SHA tags** for images (e.g., `content-service:abc123`)
3. **Never delete migration files** that have been applied to any environment
4. **Use `.down.sql` files** for rollbacks instead of deleting migrations
5. **Test migrations** in development before applying to staging/production
6. **Keep migration files in git** - they are part of the application code

### ❌ DON'T

1. **Don't deploy old images** after new migrations have been applied
2. **Don't use `latest` tag** for production deployments
3. **Don't manually edit migration files** after they've been applied
4. **Don't skip migrations** or apply them out of order
5. **Don't delete migration files** from the codebase

## Migration Workflow

### Adding a New Migration

1. Create migration file:
   ```bash
   # content-service example
   touch backend/content-service/migrations/20260110_add_new_feature.sql
   ```

2. Write migration SQL:
   ```sql
   -- Migration: Add new feature
   -- Description: What this migration does

   ALTER TABLE posts ADD COLUMN new_field VARCHAR(255);
   ```

3. Test locally:
   ```bash
   cargo run -p content-service
   # Service will apply migration automatically
   ```

4. Commit and push:
   ```bash
   git add backend/content-service/migrations/20260110_add_new_feature.sql
   git commit -m "feat(content): add new feature migration"
   git push
   ```

5. Deploy:
   ```bash
   # CI/CD will build new image with migration embedded
   # Validation script will check compatibility
   # Service will apply migration on startup
   ```

### Rolling Back a Migration

1. Create `.down.sql` file:
   ```bash
   touch backend/content-service/migrations/20260110_add_new_feature.down.sql
   ```

2. Write rollback SQL:
   ```sql
   -- Rollback: Add new feature

   ALTER TABLE posts DROP COLUMN new_field;
   ```

3. Apply manually (SQLx doesn't auto-apply .down.sql):
   ```bash
   kubectl exec -n nova-staging postgres-0 -- \
     psql -U nova -d nova_content -f /path/to/migration.down.sql
   ```

4. Rebuild and deploy image without the migration

## Troubleshooting

### Service crashes with "migration X was previously applied but is missing"

**Cause**: Image was built before migration X was added to codebase

**Fix**:
1. Check which migrations are in database:
   ```bash
   kubectl exec -n nova-staging postgres-0 -- \
     psql -U nova -d nova_content -c "SELECT version, description FROM _sqlx_migrations ORDER BY version;"
   ```

2. Check which migrations are in codebase:
   ```bash
   ls -1 backend/content-service/migrations/*.sql | grep -v ".down.sql"
   ```

3. If database has more migrations, rebuild image:
   ```bash
   # Trigger CI/CD build
   git commit --allow-empty -m "chore: rebuild image with latest migrations"
   git push
   ```

### How to check which image is running

```bash
kubectl get deployment content-service -n nova-staging -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### How to find image build date

```bash
gcloud artifacts docker images list \
  asia-northeast1-docker.pkg.dev/banded-pad-479802-k9/nova/content-service \
  --include-tags --limit=50 --format="table(version,tags,create_time)"
```

## Architecture Notes

### How SQLx Migrations Work

1. **Compile time**: `sqlx::migrate!("./migrations")` macro:
   - Scans migrations directory
   - Embeds all `.sql` files into binary
   - Generates Rust code to apply migrations

2. **Runtime**: On service startup:
   - Connects to database
   - Checks `_sqlx_migrations` table
   - Compares embedded migrations with applied migrations
   - **Fails if any applied migration is missing from embedded set**
   - Applies new migrations if any

### Why Migrations Are Embedded

- **Consistency**: Binary and migrations are always in sync
- **Deployment simplicity**: No need to copy migration files separately
- **Compile-time validation**: Syntax errors caught during build
- **Immutability**: Can't accidentally modify migrations at runtime

### Trade-offs

**Pros**:
- Guaranteed consistency between code and migrations
- No runtime file I/O for migrations
- Compile-time validation

**Cons**:
- Must rebuild image for any migration changes
- Old images can't be deployed after new migrations
- Requires careful version management

## Related Files

- `.github/scripts/validate-migrations.sh` - Migration validation script
- `.github/workflows/gcp-build-deploy-one.yml` - CI/CD with validation
- `backend/*/migrations/` - Migration directories for each service
- `backend/CLAUDE.md` - Backend development guidelines

## References

- [SQLx Migrations Documentation](https://docs.rs/sqlx/latest/sqlx/macro.migrate.html)
- [Database Migration Best Practices](https://www.postgresql.org/docs/current/ddl-alter.html)
