#!/bin/bash

# Cross-Service Database Access Detection and Fix Script
# Author: System Architect (Following Linus Principles)
# Date: 2025-11-11
# Purpose: Detect and fix cross-service database access violations

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Service to table ownership mapping
declare -A TABLE_OWNERS=(
    ["users"]="user-service"
    ["roles"]="user-service"
    ["permissions"]="user-service"
    ["user_roles"]="user-service"
    ["role_permissions"]="user-service"

    ["sessions"]="identity-service"
    ["refresh_tokens"]="identity-service"
    ["revoked_tokens"]="identity-service"

    ["posts"]="content-service"
    ["articles"]="content-service"
    ["comments"]="content-service"
    ["content_versions"]="content-service"

    ["relationships"]="social-service"
    ["feeds"]="social-service"
    ["likes"]="social-service"
    ["shares"]="social-service"

    ["conversations"]="messaging-service"
    ["messages"]="messaging-service"
    ["message_status"]="messaging-service"

    ["notifications"]="notification-service"
    ["email_queue"]="notification-service"
    ["sms_queue"]="notification-service"
    ["push_tokens"]="notification-service"

    ["media_files"]="media-service"
    ["media_metadata"]="media-service"
    ["thumbnails"]="media-service"
    ["transcode_jobs"]="media-service"

    ["domain_events"]="events-service"
    ["event_handlers"]="events-service"
    ["event_subscriptions"]="events-service"
)

# Track violations
declare -a VIOLATIONS=()
VIOLATION_COUNT=0

# Function to extract service name from path
get_service_name() {
    local file_path=$1
    local service_name=$(echo "$file_path" | grep -oP "(?<=backend/)[^/]+-service" || echo "unknown")
    echo "$service_name"
}

# Function to check if a table is owned by a service
is_table_owned_by_service() {
    local table=$1
    local service=$2
    local owner="${TABLE_OWNERS[$table]:-unknown}"

    if [ "$owner" == "$service" ]; then
        return 0
    else
        return 1
    fi
}

# Function to scan for SQL queries in Rust files
scan_rust_files() {
    log_info "Scanning Rust files for cross-service database access..."

    while IFS= read -r -d '' file; do
        local service=$(get_service_name "$file")

        if [ "$service" == "unknown" ]; then
            continue
        fi

        # Extract SQL queries (simplified pattern - may need refinement)
        while IFS= read -r line_info; do
            local line_num=$(echo "$line_info" | cut -d: -f1)
            local line_content=$(echo "$line_info" | cut -d: -f2-)

            # Extract table names from SQL queries
            local tables=$(echo "$line_content" | grep -oP '(?i)(FROM|INTO|UPDATE|DELETE FROM)\s+\K[a-z_]+' || true)

            for table in $tables; do
                if [ -n "${TABLE_OWNERS[$table]:-}" ]; then
                    if ! is_table_owned_by_service "$table" "$service"; then
                        VIOLATIONS+=("${file}:${line_num}:${service} accessing ${table} (owned by ${TABLE_OWNERS[$table]})")
                        ((VIOLATION_COUNT++))
                        log_error "❌ Violation: ${file}:${line_num}"
                        log_error "   ${service} is accessing table '${table}' owned by ${TABLE_OWNERS[$table]}"
                    fi
                fi
            done
        done < <(grep -nE "sqlx::query|query_as|query!" "$file" 2>/dev/null || true)

    done < <(find "$BACKEND_DIR" -type f -name "*.rs" -print0)
}

# Function to generate gRPC client calls
generate_grpc_replacement() {
    local table=$1
    local operation=$2
    local owner="${TABLE_OWNERS[$table]}"

    case "$table" in
        "users")
            case "$operation" in
                "SELECT")
                    echo "let user = self.user_client.get_user(GetUserRequest { id: user_id }).await?;"
                    ;;
                "UPDATE")
                    echo "let user = self.user_client.update_user(UpdateUserRequest { id: user_id, data }).await?;"
                    ;;
            esac
            ;;
        "posts")
            case "$operation" in
                "SELECT")
                    echo "let post = self.content_client.get_post(GetPostRequest { id: post_id }).await?;"
                    ;;
            esac
            ;;
        *)
            echo "// TODO: Replace with gRPC call to ${owner}"
            ;;
    esac
}

# Function to create fix file
create_fix_file() {
    local violations_file="$BACKEND_DIR/cross_service_violations.txt"
    local fixes_file="$BACKEND_DIR/cross_service_fixes.md"

    log_info "Creating fix documentation..."

    cat > "$fixes_file" << 'EOF'
# Cross-Service Database Access Fixes

Generated: $(date)
Total Violations: ${VIOLATION_COUNT}

## Violations Found

EOF

    local prev_file=""
    for violation in "${VIOLATIONS[@]}"; do
        local file=$(echo "$violation" | cut -d: -f1)
        local line=$(echo "$violation" | cut -d: -f2)
        local desc=$(echo "$violation" | cut -d: -f3-)

        if [ "$file" != "$prev_file" ]; then
            echo -e "\n### ${file#$BACKEND_DIR/}" >> "$fixes_file"
            prev_file="$file"
        fi

        echo "- Line ${line}: ${desc}" >> "$fixes_file"

        # Add suggested fix
        local table=$(echo "$desc" | grep -oP "accessing \K\w+(?= \()")
        local owner="${TABLE_OWNERS[$table]}"

        cat >> "$fixes_file" << EOF

**Suggested Fix:**
\`\`\`rust
// Replace direct database query with gRPC call
$(generate_grpc_replacement "$table" "SELECT")
\`\`\`

EOF
    done

    log_info "Fix documentation created at: $fixes_file"
}

# Function to create automated fix script
create_automated_fix() {
    local fix_script="$BACKEND_DIR/apply_cross_service_fixes.rs"

    log_info "Creating automated fix script..."

    cat > "$fix_script" << 'EOF'
//! Automated Cross-Service Database Access Fixes
//!
//! This module provides helper functions to replace direct database
//! queries with appropriate gRPC service calls.

use anyhow::Result;
use uuid::Uuid;

/// Trait for service clients
pub trait ServiceClient: Send + Sync {
    type Error;
}

/// User Service Client wrapper
pub struct UserServiceClient {
    inner: user_service::client::UserServiceClient<tonic::transport::Channel>,
}

impl UserServiceClient {
    /// Get user by ID (replaces direct SELECT from users table)
    pub async fn get_user(&self, user_id: Uuid) -> Result<User> {
        let response = self.inner
            .get_user(GetUserRequest {
                id: user_id.to_string(),
            })
            .await?;

        Ok(response.into_inner().into())
    }

    /// Get user by email (replaces direct SELECT from users table)
    pub async fn get_user_by_email(&self, email: &str) -> Result<User> {
        let response = self.inner
            .get_user_by_email(GetUserByEmailRequest {
                email: email.to_string(),
            })
            .await?;

        Ok(response.into_inner().into())
    }
}

/// Content Service Client wrapper
pub struct ContentServiceClient {
    inner: content_service::client::ContentServiceClient<tonic::transport::Channel>,
}

impl ContentServiceClient {
    /// Get post by ID (replaces direct SELECT from posts table)
    pub async fn get_post(&self, post_id: Uuid) -> Result<Post> {
        let response = self.inner
            .get_post(GetPostRequest {
                id: post_id.to_string(),
            })
            .await?;

        Ok(response.into_inner().into())
    }

    /// List posts by author (replaces direct SELECT from posts table)
    pub async fn list_posts_by_author(&self, author_id: Uuid) -> Result<Vec<Post>> {
        let response = self.inner
            .list_posts(ListPostsRequest {
                filter: Some(PostFilter {
                    author_id: Some(author_id.to_string()),
                    ..Default::default()
                }),
                ..Default::default()
            })
            .await?;

        Ok(response.into_inner().posts.into_iter().map(Into::into).collect())
    }
}

/// Helper macro to replace SQL queries
#[macro_export]
macro_rules! replace_query {
    // Replace user queries
    (SELECT * FROM users WHERE id = $id:expr) => {
        $crate::get_user_client().await?.get_user($id).await
    };

    (SELECT * FROM users WHERE email = $email:expr) => {
        $crate::get_user_client().await?.get_user_by_email($email).await
    };

    // Replace post queries
    (SELECT * FROM posts WHERE id = $id:expr) => {
        $crate::get_content_client().await?.get_post($id).await
    };

    (SELECT * FROM posts WHERE author_id = $author_id:expr) => {
        $crate::get_content_client().await?.list_posts_by_author($author_id).await
    };
}

/// Migration helper to update existing code
pub mod migration {
    use super::*;
    use std::fs;
    use std::path::Path;
    use regex::Regex;

    pub fn fix_cross_service_queries(file_path: &Path) -> Result<()> {
        let content = fs::read_to_string(file_path)?;

        // Pattern to match SQL queries
        let patterns = vec![
            (
                r#"sqlx::query.*?SELECT \* FROM users WHERE id = \$1.*?fetch_one"#,
                "self.user_client.get_user(user_id).await?"
            ),
            (
                r#"sqlx::query.*?SELECT \* FROM posts WHERE id = \$1.*?fetch_one"#,
                "self.content_client.get_post(post_id).await?"
            ),
        ];

        let mut fixed_content = content.clone();
        for (pattern, replacement) in patterns {
            let re = Regex::new(pattern)?;
            fixed_content = re.replace_all(&fixed_content, replacement).to_string();
        }

        if fixed_content != content {
            fs::write(file_path, fixed_content)?;
            println!("Fixed cross-service queries in: {:?}", file_path);
        }

        Ok(())
    }
}

EOF

    log_info "Automated fix script created at: $fix_script"
}

# Function to update service dependencies
update_service_dependencies() {
    log_info "Updating Cargo.toml files to add gRPC client dependencies..."

    for service_dir in "$BACKEND_DIR"/*-service; do
        if [ -d "$service_dir" ] && [ -f "$service_dir/Cargo.toml" ]; then
            local service_name=$(basename "$service_dir")

            # Check if service has violations
            local has_violations=false
            for violation in "${VIOLATIONS[@]}"; do
                if [[ "$violation" == *"$service_name"* ]]; then
                    has_violations=true
                    break
                fi
            done

            if [ "$has_violations" = true ]; then
                log_info "Updating dependencies for $service_name..."

                # Add gRPC client dependencies (simplified - you might need to adjust)
                if ! grep -q "user-service-client" "$service_dir/Cargo.toml"; then
                    cat >> "$service_dir/Cargo.toml" << 'EOF'

# gRPC service clients for cross-service communication
[dependencies.user-service-client]
path = "../user-service/client"

[dependencies.content-service-client]
path = "../content-service/client"

[dependencies.messaging-service-client]
path = "../messaging-service/client"
EOF
                fi
            fi
        fi
    done
}

# Main execution
main() {
    echo "========================================="
    echo "Cross-Service Database Access Scanner"
    echo "========================================="
    echo ""

    # Run scan
    scan_rust_files

    echo ""
    echo "========================================="
    echo "Scan Results"
    echo "========================================="

    if [ ${VIOLATION_COUNT} -eq 0 ]; then
        log_info "✅ No cross-service database access violations found!"
    else
        log_error "❌ Found ${VIOLATION_COUNT} violations"
        echo ""

        # Create fix documentation
        create_fix_file
        create_automated_fix

        echo ""
        log_info "Violation Summary:"

        # Group violations by service
        declare -A service_violations
        for violation in "${VIOLATIONS[@]}"; do
            local service=$(echo "$violation" | cut -d: -f3 | cut -d' ' -f1)
            ((service_violations[$service]++))
        done

        for service in "${!service_violations[@]}"; do
            echo "  - ${service}: ${service_violations[$service]} violations"
        done

        echo ""
        read -p "Would you like to update service dependencies? (y/N): " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_service_dependencies

            echo ""
            log_info "Next steps:"
            echo "  1. Review the fixes in: cross_service_fixes.md"
            echo "  2. Apply the automated fixes using: apply_cross_service_fixes.rs"
            echo "  3. Update service clients to use gRPC instead of direct DB access"
            echo "  4. Run tests to ensure functionality is preserved"
        fi
    fi

    echo ""
    log_info "Remember: 'Never break userspace' - ensure backward compatibility during migration"
}

# Run main
main "$@"