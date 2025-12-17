use std::fs;
use std::path::{Path, PathBuf};

fn collect_rs_files(root: &Path) -> Vec<PathBuf> {
    let mut files = Vec::new();
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        if let Ok(read_dir) = fs::read_dir(&dir) {
            for entry in read_dir.flatten() {
                let path = entry.path();
                if path.is_dir() {
                    stack.push(path);
                } else if path.extension().map(|e| e == "rs").unwrap_or(false) {
                    files.push(path);
                }
            }
        }
    }
    files
}

fn file_contains(path: &Path, needle: &str) -> bool {
    fs::read_to_string(path)
        .map(|c| c.contains(needle))
        .unwrap_or(false)
}

#[test]
fn follow_writes_only_from_social_or_graph_service() {
    // workspace root = backend
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let backend_root = manifest
        .parent()
        .expect("social-service has a parent dir")
        .to_path_buf();

    let allowed = [
        // social-service: entry points for follow operations
        "backend/social-service/src/workers/graph_sync.rs",
        "backend/social-service/src/services/follow.rs",
        "backend/social-service/src/grpc/server_v2.rs",
        // graph-service: internal implementation
        "backend/graph-service/src/grpc/server.rs",
        "backend/graph-service/src/repository/graph_repository.rs",
        "backend/graph-service/src/repository/trait.rs",
        "backend/graph-service/src/repository/dual_write_repository.rs",
        "backend/graph-service/src/repository/postgres_repository.rs",
        "backend/graph-service/src/repository/cached_repository.rs",
        "backend/graph-service/src/consumers/social_events.rs",
        // graphql-gateway: REST API passthrough
        "backend/graphql-gateway/src/rest_api/graph.rs",
    ];

    let mut offenders = Vec::new();
    for file in collect_rs_files(&backend_root) {
        let path_str = file.to_string_lossy();
        if allowed.iter().any(|a| path_str.ends_with(a)) || path_str.ends_with("follow_boundary.rs")
        {
            continue;
        }
        if path_str.contains("/target/") {
            continue; // ignore generated code
        }
        if file_contains(&file, "CreateFollowRequest")
            || file_contains(&file, "DeleteFollowRequest")
            || file_contains(&file, "create_follow(")
        {
            offenders.push(path_str.to_string());
        }
    }

    if !offenders.is_empty() {
        panic!(
            "Follow graph writes must go through social-service -> graph-service only. Offenders: {:?}",
            offenders
        );
    }
}
