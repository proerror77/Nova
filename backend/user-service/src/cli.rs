//! Command-line interface handling
//!
//! Separates CLI-specific logic from main application startup

use std::io;

/// Handle CLI commands (healthcheck, etc.)
/// 
/// Returns true if a command was processed (program should exit).
/// Returns false if no CLI command was found (normal startup).
pub async fn handle_cli_commands() -> io::Result<bool> {
    let mut args = std::env::args();
    let _bin = args.next();
    
    match args.next().as_deref() {
        Some("healthcheck") | Some("healthcheck-http") => {
            handle_healthcheck().await
        }
        _ => Ok(false),
    }
}

/// Handle healthcheck command
/// 
/// Performs HTTP health check against the running service
async fn handle_healthcheck() -> io::Result<bool> {
    let url = "http://127.0.0.1:8080/api/v1/health";
    
    match reqwest::Client::new().get(url).send().await {
        Ok(resp) if resp.status().is_success() => {
            tracing::info!("Healthcheck passed");
            Ok(true)
        }
        Ok(resp) => {
            eprintln!("healthcheck failed: HTTP {}", resp.status());
            Err(io::Error::new(
                io::ErrorKind::Other,
                format!("healthcheck failed: HTTP {}", resp.status()),
            ))
        }
        Err(e) => {
            eprintln!("healthcheck error: {}", e);
            Err(io::Error::new(
                io::ErrorKind::Other,
                format!("healthcheck error: {}", e),
            ))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_healthcheck_handles_no_command() {
        let result = handle_cli_commands().await;
        // Should return false when no command is given (but this test has no args)
        // This is more of a smoke test
        assert!(result.is_ok());
    }
}
