use std::collections::HashSet;

pub struct OfflineQueue {
    seen: HashSet<String>,
}

impl OfflineQueue {
    pub fn new() -> Self { Self { seen: HashSet::new() } }
    pub fn enqueue(&mut self, idempotency_key: &str) -> bool {
        self.seen.insert(idempotency_key.to_string())
    }
}

