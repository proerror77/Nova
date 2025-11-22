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
fn feed_service_does_not_query_content_posts_table() {
    let src_root = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("src");
    let mut offenders = Vec::new();
    for file in collect_rs_files(&src_root) {
        let path_str = file.to_string_lossy();
        if path_str.contains("/target/") {
            continue;
        }
        if file_contains(&file, "FROM posts")
            || file_contains(&file, "INSERT INTO posts")
            || file_contains(&file, "UPDATE posts")
        {
            offenders.push(path_str.to_string());
        }
    }

    if !offenders.is_empty() {
        panic!(
            "Feed service must not directly query content-owned posts table. Offenders: {:?}",
            offenders
        );
    }
}
