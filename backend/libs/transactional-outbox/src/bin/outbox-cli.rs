use std::env;

use chrono::{DateTime, Utc};
use sqlx::PgPool;
use transactional_outbox::SqlxOutboxRepository;
use uuid::Uuid;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage:");
        eprintln!("  outbox-cli replay-since <rfc3339_ts> <DATABASE_URL>");
        eprintln!("  outbox-cli replay-range <from_uuid> <to_uuid> <DATABASE_URL>");
        std::process::exit(1);
    }

    let cmd = args[1].as_str();

    match cmd {
        "replay-since" if args.len() == 4 => {
            let ts: DateTime<Utc> = DateTime::parse_from_rfc3339(&args[2])?.with_timezone(&Utc);
            let db_url = &args[3];
            let pool = PgPool::connect(db_url).await?;
            let repo = SqlxOutboxRepository::new(pool);
            let count = repo.replay_since(ts).await?;
            println!("Replayed {} events since {}", count, ts);
        }
        "replay-range" if args.len() == 5 => {
            let from = Uuid::parse_str(&args[2])?;
            let to = Uuid::parse_str(&args[3])?;
            let db_url = &args[4];
            let pool = PgPool::connect(db_url).await?;
            let repo = SqlxOutboxRepository::new(pool);
            let count = repo.replay_range(from, to).await?;
            println!("Replayed {} events between {} and {}", count, from, to);
        }
        _ => {
            eprintln!("Invalid arguments");
            std::process::exit(1);
        }
    }

    Ok(())
}
