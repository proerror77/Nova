#!/usr/bin/env python3
"""
Add missing Path import from actix_web::web where needed.
"""

import re
from pathlib import Path

def fix_imports(content: str) -> str:
    """Add web::Path import if Path is used but not imported"""

    # Check if Path is used in function signatures
    has_path_usage = bool(re.search(r'Path<', content) or re.search(r'web::Path<', content))

    if not has_path_usage:
        return content

    # Check if web is already imported
    has_web_import = 'use actix_web::web' in content or 'use actix_web::{.*web' in content

    if not has_web_import:
        # Find the actix_web import line and add web
        # Look for: use actix_web::{...};
        match = re.search(r'(use actix_web::\{[^}]+)', content)
        if match:
            import_line = match.group(1)
            if 'web' not in import_line:
                new_import = import_line.rstrip('}') + ', web'
                content = content.replace(import_line, new_import)

    return content

def process_file(file_path: Path):
    """Process a single Rust file"""
    content = file_path.read_text()
    original = content

    # Apply fixes
    content = fix_imports(content)

    if content != original:
        file_path.write_text(content)
        print(f"✅ Fixed imports in: {file_path}")
        return True
    return False

def main():
    messaging_dir = Path("/Users/proerror/Documents/nova/backend/messaging-service")

    routes_dir = messaging_dir / "src" / "routes"

    total_fixed = 0

    for rs_file in routes_dir.glob("*.rs"):
        if process_file(rs_file):
            total_fixed += 1

    print(f"\n📊 Total files fixed: {total_fixed}")

if __name__ == "__main__":
    main()
