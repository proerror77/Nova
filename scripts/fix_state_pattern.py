#!/usr/bin/env python3
"""
Fix State() pattern matching issues in Actix-Web handlers.
In Actix, we use web::Data<T> directly, not State(value) pattern.
"""

import re
import sys
from pathlib import Path

def fix_state_pattern(content: str) -> str:
    """
    Transform:
        State(state): web::Data<AppState>
    To:
        state: web::Data<AppState>
    """
    # Pattern 1: State(var): web::Data<T>
    content = re.sub(
        r'State\((\w+)\):\s*web::Data<',
        r'\1: web::Data<',
        content
    )

    # Pattern 2: Path((var1, var2)): web::Path<...>
    # This is actually correct for Actix, but we need Path from actix_web::web
    # Just ensure we have the right import

    return content

def process_file(file_path: Path):
    """Process a single Rust file"""
    content = file_path.read_text()
    original = content

    # Apply fixes
    content = fix_state_pattern(content)

    if content != original:
        file_path.write_text(content)
        print(f"✅ Fixed: {file_path}")
        return True
    return False

def main():
    messaging_dir = Path("/Users/proerror/Documents/nova/backend/messaging-service")

    # Target directories
    routes_dir = messaging_dir / "src" / "routes"
    handlers_dir = messaging_dir / "src" / "handlers"
    websocket_dir = messaging_dir / "src" / "websocket"

    total_fixed = 0

    for directory in [routes_dir, handlers_dir, websocket_dir]:
        if not directory.exists():
            continue

        for rs_file in directory.glob("*.rs"):
            if process_file(rs_file):
                total_fixed += 1

    print(f"\n📊 Total files fixed: {total_fixed}")

if __name__ == "__main__":
    main()
