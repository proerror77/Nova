//! Database seed script for creating initial admin user
//! Run with: cargo run --bin seed

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
    Argon2,
};
use sqlx::postgres::PgPoolOptions;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load environment
    dotenvy::dotenv().ok();

    let database_url = std::env::var("DATABASE_URL")
        .unwrap_or_else(|_| "postgres://postgres:postgres@localhost:55432/nova_auth".to_string());

    println!("Connecting to database...");

    let pool = PgPoolOptions::new()
        .max_connections(1)
        .connect(&database_url)
        .await?;

    println!("Connected successfully!");

    // Default admin credentials
    let email = std::env::var("ADMIN_EMAIL").unwrap_or_else(|_| "admin@nova.app".to_string());
    let password = std::env::var("ADMIN_PASSWORD").unwrap_or_else(|_| "Admin@123".to_string());
    let name = std::env::var("ADMIN_NAME").unwrap_or_else(|_| "系统管理员".to_string());

    // Hash the password with Argon2
    println!("Hashing password...");
    let salt = SaltString::generate(&mut OsRng);
    let argon2 = Argon2::default();
    let password_hash = argon2
        .hash_password(password.as_bytes(), &salt)
        .map_err(|e| anyhow::anyhow!("Password hashing failed: {}", e))?
        .to_string();

    // Check if admin exists
    let existing: Option<(String,)> = sqlx::query_as(
        "SELECT email FROM admins WHERE email = $1"
    )
    .bind(&email)
    .fetch_optional(&pool)
    .await?;

    if existing.is_some() {
        // Update existing admin's password
        println!("Updating existing admin password...");
        sqlx::query(
            "UPDATE admins SET password_hash = $1, updated_at = NOW() WHERE email = $2"
        )
        .bind(&password_hash)
        .bind(&email)
        .execute(&pool)
        .await?;
        println!("Admin password updated successfully!");
    } else {
        // Create new admin
        println!("Creating new admin...");
        sqlx::query(
            r#"
            INSERT INTO admins (email, password_hash, name, role, is_active)
            VALUES ($1, $2, $3, 'super_admin', true)
            "#
        )
        .bind(&email)
        .bind(&password_hash)
        .bind(&name)
        .execute(&pool)
        .await?;
        println!("Admin created successfully!");
    }

    println!("\n========================================");
    println!("Admin Account Ready!");
    println!("========================================");
    println!("Email:    {}", email);
    println!("Password: {}", password);
    println!("Role:     super_admin");
    println!("========================================");
    println!("\nYou can now login at http://localhost:3001");

    Ok(())
}
