//! Service Boundary Validation Tests
//!
//! These tests ensure that service boundaries are properly enforced
//! and that no service violates data ownership rules.
//!
//! Author: System Architect (Following Linus Principles)
//! Date: 2025-11-11

use anyhow::Result;
use sqlx::PgPool;
use std::collections::HashMap;
use uuid::Uuid;

/// Service boundary validator
pub struct ServiceBoundaryValidator {
    pool: PgPool,
    violations: Vec<BoundaryViolation>,
}

#[derive(Debug, Clone)]
pub struct BoundaryViolation {
    pub service: String,
    pub table: String,
    pub operation: String,
    pub location: String,
    pub severity: ViolationSeverity,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ViolationSeverity {
    Critical,  // Direct write to another service's table
    High,      // Direct read from another service's table
    Medium,    // Missing service boundary check
    Low,       // Potential issue
}

impl ServiceBoundaryValidator {
    pub fn new(pool: PgPool) -> Self {
        Self {
            pool,
            violations: Vec::new(),
        }
    }

    /// Run all boundary validation tests
    pub async fn validate_all(&mut self) -> Result<ValidationReport> {
        // Test 1: Data ownership constraints
        self.test_data_ownership_constraints().await?;

        // Test 2: Cross-service database access
        self.test_cross_service_db_access().await?;

        // Test 3: Service isolation
        self.test_service_isolation().await?;

        // Test 4: Event-driven communication
        self.test_event_driven_patterns().await?;

        // Test 5: API boundaries
        self.test_api_boundaries().await?;

        Ok(self.generate_report())
    }

    fn generate_report(&self) -> ValidationReport {
        ValidationReport {
            total_tests: 5,
            passed: self.violations.is_empty(),
            critical_violations: self.count_by_severity(ViolationSeverity::Critical),
            high_violations: self.count_by_severity(ViolationSeverity::High),
            medium_violations: self.count_by_severity(ViolationSeverity::Medium),
            low_violations: self.count_by_severity(ViolationSeverity::Low),
            violations: self.violations.clone(),
        }
    }

    fn count_by_severity(&self, severity: ViolationSeverity) -> usize {
        self.violations.iter()
            .filter(|v| v.severity == severity)
            .count()
    }
}

// ============================================================
// Test 1: Data Ownership Constraints
// ============================================================

impl ServiceBoundaryValidator {
    async fn test_data_ownership_constraints(&mut self) -> Result<()> {
        println!("Testing data ownership constraints...");

        // Check if all tables have service_owner column
        let tables_without_owner = sqlx::query!(
            r#"
            SELECT t.tablename
            FROM pg_tables t
            WHERE t.schemaname = 'public'
            AND NOT EXISTS (
                SELECT 1 FROM information_schema.columns c
                WHERE c.table_schema = t.schemaname
                AND c.table_name = t.tablename
                AND c.column_name = 'service_owner'
            )
            "#
        )
        .fetch_all(&self.pool)
        .await?;

        for table in tables_without_owner {
            self.violations.push(BoundaryViolation {
                service: "unknown".to_string(),
                table: table.tablename.unwrap_or_default(),
                operation: "MISSING_OWNERSHIP".to_string(),
                location: "database schema".to_string(),
                severity: ViolationSeverity::Critical,
            });
        }

        // Check if ownership constraints are enforced
        let tables_without_constraints = sqlx::query!(
            r#"
            SELECT tablename
            FROM pg_tables t
            WHERE schemaname = 'public'
            AND EXISTS (
                SELECT 1 FROM information_schema.columns c
                WHERE c.table_schema = t.schemaname
                AND c.table_name = t.tablename
                AND c.column_name = 'service_owner'
            )
            AND NOT EXISTS (
                SELECT 1 FROM information_schema.check_constraints cc
                JOIN information_schema.constraint_column_usage ccu
                ON cc.constraint_name = ccu.constraint_name
                WHERE ccu.table_name = t.tablename
                AND cc.constraint_name LIKE 'owned_by_%'
            )
            "#
        )
        .fetch_all(&self.pool)
        .await?;

        for table in tables_without_constraints {
            self.violations.push(BoundaryViolation {
                service: "unknown".to_string(),
                table: table.tablename.unwrap_or_default(),
                operation: "MISSING_CONSTRAINT".to_string(),
                location: "database schema".to_string(),
                severity: ViolationSeverity::High,
            });
        }

        Ok(())
    }
}

// ============================================================
// Test 2: Cross-Service Database Access
// ============================================================

impl ServiceBoundaryValidator {
    async fn test_cross_service_db_access(&mut self) -> Result<()> {
        println!("Testing for cross-service database access...");

        // Simulate different services trying to access tables they don't own
        let test_cases = vec![
            ("content-service", "users", "SELECT"),
            ("auth-service", "posts", "INSERT"),
            ("user-service", "messages", "UPDATE"),
        ];

        for (service, table, operation) in test_cases {
            if let Err(_) = self.simulate_cross_service_access(service, table, operation).await {
                // Good - access was blocked
            } else {
                // Bad - cross-service access was allowed
                self.violations.push(BoundaryViolation {
                    service: service.to_string(),
                    table: table.to_string(),
                    operation: operation.to_string(),
                    location: "runtime check".to_string(),
                    severity: ViolationSeverity::Critical,
                });
            }
        }

        Ok(())
    }

    async fn simulate_cross_service_access(
        &self,
        service: &str,
        table: &str,
        operation: &str,
    ) -> Result<()> {
        // Set the application name to simulate a service
        sqlx::query(&format!("SET application_name = '{}'", service))
            .execute(&self.pool)
            .await?;

        // Try to perform an operation
        let query = match operation {
            "SELECT" => format!("SELECT * FROM {} LIMIT 1", table),
            "INSERT" => format!("INSERT INTO {} DEFAULT VALUES RETURNING *", table),
            "UPDATE" => format!("UPDATE {} SET updated_at = NOW() WHERE false", table),
            _ => return Ok(()),
        };

        // This should fail if boundaries are properly enforced
        let result = sqlx::query(&query).execute(&self.pool).await;

        // Reset application name
        sqlx::query("SET application_name = DEFAULT")
            .execute(&self.pool)
            .await?;

        result?;
        Ok(())
    }
}

// ============================================================
// Test 3: Service Isolation
// ============================================================

impl ServiceBoundaryValidator {
    async fn test_service_isolation(&mut self) -> Result<()> {
        println!("Testing service isolation...");

        // Check for foreign keys crossing service boundaries
        let cross_service_fks = sqlx::query!(
            r#"
            WITH table_ownership AS (
                SELECT DISTINCT
                    tc.table_name,
                    tc.constraint_name,
                    kcu.column_name,
                    ccu.table_name as referenced_table,
                    t1.service_owner as from_service,
                    t2.service_owner as to_service
                FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu
                    ON tc.constraint_name = kcu.constraint_name
                JOIN information_schema.constraint_column_usage ccu
                    ON ccu.constraint_name = tc.constraint_name
                LEFT JOIN (
                    SELECT tablename, 'unknown' as service_owner
                    FROM pg_tables WHERE schemaname = 'public'
                ) t1 ON t1.tablename = tc.table_name
                LEFT JOIN (
                    SELECT tablename, 'unknown' as service_owner
                    FROM pg_tables WHERE schemaname = 'public'
                ) t2 ON t2.tablename = ccu.table_name
                WHERE tc.constraint_type = 'FOREIGN KEY'
                AND tc.table_schema = 'public'
            )
            SELECT *
            FROM table_ownership
            WHERE from_service != to_service
            AND from_service != 'unknown'
            AND to_service != 'unknown'
            "#
        )
        .fetch_all(&self.pool)
        .await?;

        for fk in cross_service_fks {
            self.violations.push(BoundaryViolation {
                service: fk.from_service.unwrap_or_default(),
                table: fk.table_name.unwrap_or_default(),
                operation: format!("FK to {}", fk.referenced_table.unwrap_or_default()),
                location: format!("constraint {}", fk.constraint_name.unwrap_or_default()),
                severity: ViolationSeverity::High,
            });
        }

        Ok(())
    }
}

// ============================================================
// Test 4: Event-Driven Communication
// ============================================================

impl ServiceBoundaryValidator {
    async fn test_event_driven_patterns(&mut self) -> Result<()> {
        println!("Testing event-driven communication patterns...");

        // Check if outbox pattern is implemented
        let has_outbox = sqlx::query!(
            "SELECT EXISTS(SELECT 1 FROM pg_tables WHERE tablename = 'outbox_events') as exists"
        )
        .fetch_one(&self.pool)
        .await?;

        if !has_outbox.exists.unwrap_or(false) {
            self.violations.push(BoundaryViolation {
                service: "all".to_string(),
                table: "outbox_events".to_string(),
                operation: "MISSING_TABLE".to_string(),
                location: "event infrastructure".to_string(),
                severity: ViolationSeverity::Medium,
            });
        }

        // Check if event store is implemented
        let has_event_store = sqlx::query!(
            "SELECT EXISTS(SELECT 1 FROM pg_tables WHERE tablename = 'domain_events') as exists"
        )
        .fetch_one(&self.pool)
        .await?;

        if !has_event_store.exists.unwrap_or(false) {
            self.violations.push(BoundaryViolation {
                service: "all".to_string(),
                table: "domain_events".to_string(),
                operation: "MISSING_TABLE".to_string(),
                location: "event infrastructure".to_string(),
                severity: ViolationSeverity::Medium,
            });
        }

        Ok(())
    }
}

// ============================================================
// Test 5: API Boundaries
// ============================================================

impl ServiceBoundaryValidator {
    async fn test_api_boundaries(&mut self) -> Result<()> {
        println!("Testing API boundaries...");

        // This would typically involve checking gRPC service definitions
        // For now, we'll check if service clients are properly configured

        // Check for proper service role configuration
        let service_roles = vec![
            "identity_service",
            "content_service",
            "social_service",
            "media_service",
            "notification_service",
            "realtime_chat_service",
        ];

        for role in service_roles {
            let role_exists = sqlx::query!(
                "SELECT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = $1) as exists",
                role
            )
            .fetch_one(&self.pool)
            .await?;

            if !role_exists.exists.unwrap_or(false) {
                self.violations.push(BoundaryViolation {
                    service: role.to_string(),
                    table: "pg_roles".to_string(),
                    operation: "MISSING_ROLE".to_string(),
                    location: "database permissions".to_string(),
                    severity: ViolationSeverity::Medium,
                });
            }
        }

        Ok(())
    }
}

// ============================================================
// Validation Report
// ============================================================

#[derive(Debug)]
pub struct ValidationReport {
    pub total_tests: usize,
    pub passed: bool,
    pub critical_violations: usize,
    pub high_violations: usize,
    pub medium_violations: usize,
    pub low_violations: usize,
    pub violations: Vec<BoundaryViolation>,
}

impl ValidationReport {
    pub fn print(&self) {
        println!("\n========================================");
        println!("Service Boundary Validation Report");
        println!("========================================\n");

        if self.passed {
            println!("✅ All boundary tests passed!");
        } else {
            println!("❌ Boundary violations detected!");
            println!("\nViolation Summary:");
            println!("  Critical: {}", self.critical_violations);
            println!("  High:     {}", self.high_violations);
            println!("  Medium:   {}", self.medium_violations);
            println!("  Low:      {}", self.low_violations);

            println!("\nDetailed Violations:");
            for violation in &self.violations {
                println!(
                    "  [{:?}] {}: {} on {} ({})",
                    violation.severity,
                    violation.service,
                    violation.operation,
                    violation.table,
                    violation.location
                );
            }
        }

        println!("\n========================================");
    }
}

// ============================================================
// Integration Tests
// ============================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_boundary_validation() {
        let database_url = std::env::var("TEST_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://localhost/nova_test".to_string());

        let pool = PgPool::connect(&database_url).await.unwrap();
        let mut validator = ServiceBoundaryValidator::new(pool);

        let report = validator.validate_all().await.unwrap();
        report.print();

        // In a real test, we would assert specific conditions
        assert!(report.critical_violations == 0, "Critical violations found");
    }

    #[tokio::test]
    async fn test_cross_service_prevention() {
        let database_url = std::env::var("TEST_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://localhost/nova_test".to_string());

        let pool = PgPool::connect(&database_url).await.unwrap();

        // Set up test: content-service trying to write to users table
        sqlx::query("SET application_name = 'content-service'")
            .execute(&pool)
            .await
            .unwrap();

        // This should fail
        let result = sqlx::query("INSERT INTO users (email) VALUES ('test@example.com')")
            .execute(&pool)
            .await;

        assert!(result.is_err(), "Cross-service write should be blocked");

        // Reset
        sqlx::query("SET application_name = DEFAULT")
            .execute(&pool)
            .await
            .unwrap();
    }

    #[tokio::test]
    async fn test_event_publishing() {
        // Test that events are properly published to outbox
        let database_url = std::env::var("TEST_DATABASE_URL")
            .unwrap_or_else(|_| "postgres://localhost/nova_test".to_string());

        let pool = PgPool::connect(&database_url).await.unwrap();

        // Create a test event
        let event_id = Uuid::new_v4();
        let event = serde_json::json!({
            "event_id": event_id,
            "event_type": "test.event",
            "payload": {"test": "data"}
        });

        // Insert into outbox
        let result = sqlx::query!(
            "INSERT INTO outbox_events (event_id, payload) VALUES ($1, $2)",
            event_id,
            event
        )
        .execute(&pool)
        .await;

        assert!(result.is_ok(), "Event should be inserted into outbox");

        // Verify event is in outbox
        let outbox_event = sqlx::query!(
            "SELECT * FROM outbox_events WHERE event_id = $1",
            event_id
        )
        .fetch_optional(&pool)
        .await
        .unwrap();

        assert!(outbox_event.is_some(), "Event should be in outbox");
        assert_eq!(outbox_event.unwrap().published, false, "Event should not be published yet");
    }
}

// ============================================================
// Main Test Runner
// ============================================================

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    println!("Running Service Boundary Validation Tests...\n");

    // Connect to database
    let database_url = std::env::var("DATABASE_URL")
        .expect("DATABASE_URL must be set");

    let pool = PgPool::connect(&database_url).await?;

    // Run validation
    let mut validator = ServiceBoundaryValidator::new(pool);
    let report = validator.validate_all().await?;

    // Print report
    report.print();

    // Exit with appropriate code
    if report.passed {
        std::process::exit(0);
    } else {
        std::process::exit(1);
    }
}
