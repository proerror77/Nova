pub mod auth;
pub mod authorization;
pub mod error_handling;
pub mod logging;
pub mod guards;

use axum::Router;
use crate::state::AppState;

/// Apply default middleware layers (logging, etc.)
pub fn with_defaults(router: Router<AppState>) -> Router<AppState> {
    logging::add_tracing(router)
}

