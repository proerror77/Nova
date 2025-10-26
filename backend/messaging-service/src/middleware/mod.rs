pub mod auth;
pub mod authorization;
pub mod error_handling;
pub mod guards;
pub mod logging;

use crate::state::AppState;
use axum::Router;

/// Apply default middleware layers (logging, etc.)
pub fn with_defaults(router: Router<AppState>) -> Router<AppState> {
    logging::add_tracing(router)
}
